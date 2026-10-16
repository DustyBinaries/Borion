// Testes dos módulos de plugins (@borion/api/dialog, /fs, /shell, /menu...): verificam que
// cada função chama o comando certo do Delphi com os argumentos certos.
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as dialog from '../dialog.js';
import * as fs from '../fs.js';
import * as shell from '../shell.js';
import * as menu from '../menu.js';
import * as tray from '../tray.js';
import * as app from '../app.js';
import * as clipboard from '../clipboard.js';
import { load, Store } from '../store.js';
import { asciiJson } from '../ascii-json.js';
import * as os from '../os.js';
import { fetch as httpFetch } from '../http.js';
import * as notification from '../notification.js';
import * as singleInstance from '../single-instance.js';
import * as deepLink from '../deep-link.js';
import * as autostart from '../autostart.js';

let chamadas;
let respostas;
let ouvintes;

function ponteFalsa() {
  return {
    version: 'teste',
    invoke(cmd, args) {
      chamadas.push([cmd, args]);
      return Promise.resolve(cmd in respostas ? respostas[cmd] : null);
    },
    listen(evento, cb) {
      (ouvintes[evento] = ouvintes[evento] || []).push(cb);
      return () => { ouvintes[evento] = ouvintes[evento].filter((c) => c !== cb); };
    },
    once() {}, emit() {},
  };
}

// simula um evento vindo do Delphi
function delphiEmite(evento, payload) {
  (ouvintes[evento] || []).forEach((cb) => cb(payload, evento));
}

beforeEach(() => {
  chamadas = [];
  respostas = {};
  ouvintes = {};
  globalThis.__BORION__ = ponteFalsa();
});
afterEach(() => { delete globalThis.__BORION__; });

describe('@borion/api/dialog', () => {
  test('open repassa as opções e devolve o resultado', async () => {
    respostas['dialog:open'] = ['C:\\a.txt', 'C:\\b.txt'];
    const filtros = [{ name: 'Texto', extensions: ['txt'] }];
    assert.deepEqual(await dialog.open({ multiple: true, filters: filtros }), ['C:\\a.txt', 'C:\\b.txt']);
    assert.deepEqual(chamadas[0], ['dialog:open', { multiple: true, filters: filtros }]);
  });

  test('cancelar devolve null', async () => {
    assert.equal(await dialog.save({ title: 'Salvar' }), null);
    assert.deepEqual(chamadas[0], ['dialog:save', { title: 'Salvar' }]);
  });

  test('message aceita o título como string e resolve sem valor', async () => {
    assert.equal(await dialog.message('Salvo!', 'Editor'), undefined);
    assert.deepEqual(chamadas[0], ['dialog:message', { title: 'Editor', message: 'Salvo!' }]);
  });

  test('confirm devolve o boolean; ask usa Sim/Não', async () => {
    respostas['dialog:confirm'] = true;
    assert.equal(await dialog.confirm('Apagar?', { kind: 'warning' }), true);
    await dialog.ask('Sair sem salvar?');
    assert.deepEqual(chamadas[0], ['dialog:confirm', { kind: 'warning', message: 'Apagar?' }]);
    assert.deepEqual(chamadas[1], ['dialog:confirm', { buttons: 'yesNo', message: 'Sair sem salvar?' }]);
  });
});

describe('@borion/api/fs', () => {
  test('texto: caminho, conteúdo e opções', async () => {
    respostas['fs:readTextFile'] = 'olá';
    assert.equal(await fs.readTextFile('notas.txt', { baseDir: fs.BaseDirectory.AppData }), 'olá');
    await fs.writeTextFile('notas.txt', 'x', { baseDir: 'appData', append: true });
    assert.deepEqual(chamadas[0], ['fs:readTextFile', { baseDir: 'appData', path: 'notas.txt' }]);
    assert.deepEqual(chamadas[1], ['fs:writeTextFile', { baseDir: 'appData', append: true, path: 'notas.txt', contents: 'x' }]);
  });

  test('binário: bytes viram base64 e voltam iguais', async () => {
    const bytes = new Uint8Array(256).map((_, i) => i);
    await fs.writeFile('C:\\x.bin', bytes);
    const enviado = chamadas[0][1].data;
    assert.equal(enviado, Buffer.from(bytes).toString('base64'));
    respostas['fs:readFile'] = enviado;
    assert.deepEqual(await fs.readFile('C:\\x.bin'), bytes);
    await fs.writeFile('C:\\y.bin', [1, 2, 3]);
    assert.equal(chamadas[2][1].data, 'AQID');
  });

  test('rename e copyFile usam from/to; mkdir e remove repassam recursive', async () => {
    await fs.rename('a', 'b');
    await fs.copyFile('a', 'c', { baseDir: 'temp' });
    await fs.mkdir('d', { recursive: true });
    await fs.remove('d', { recursive: true });
    assert.deepEqual(chamadas, [
      ['fs:rename', { from: 'a', to: 'b' }],
      ['fs:copyFile', { baseDir: 'temp', from: 'a', to: 'c' }],
      ['fs:mkdir', { recursive: true, path: 'd' }],
      ['fs:remove', { recursive: true, path: 'd' }],
    ]);
  });

  test('BaseDirectory é imutável e bate com os nomes do Delphi', () => {
    assert.ok(Object.isFrozen(fs.BaseDirectory));
    assert.deepEqual(Object.values(fs.BaseDirectory).sort(),
      ['appData', 'appLocalData', 'desktop', 'document', 'download', 'exe', 'home', 'picture', 'temp']);
  });

  test('erros do Delphi chegam como rejeição com code', async () => {
    globalThis.__BORION__.invoke = () => {
      const e = new Error('fora do escopo permitido'); e.code = 'FORBIDDEN_PATH';
      return Promise.reject(e);
    };
    await assert.rejects(fs.readTextFile('C:\\Windows\\win.ini'), (e) => e.code === 'FORBIDDEN_PATH');
  });
});

describe('@borion/api/shell', () => {
  test('open e showInFolder', async () => {
    assert.equal(await shell.open('https://borion.dev'), undefined);
    await shell.showInFolder('nota.txt', { baseDir: 'document' });
    assert.deepEqual(chamadas, [
      ['shell:open', { target: 'https://borion.dev' }],
      ['shell:showInFolder', { baseDir: 'document', path: 'nota.txt' }],
    ]);
  });
});

describe('@borion/api/menu', () => {
  test('setMenu, update, clear e popup', async () => {
    const itens = [{ label: '&Arquivo', items: [{ id: 'salvar', label: 'Salvar', accelerator: 'Ctrl+S' }] }];
    await menu.setMenu(itens);
    await menu.update('salvar', { enabled: false });
    await menu.clear();
    respostas['menu:popup'] = 'copiar';
    assert.equal(await menu.popup([{ id: 'copiar', label: 'Copiar' }], { x: 10, y: 20 }), 'copiar');
    assert.deepEqual(chamadas, [
      ['menu:setMenu', { items: itens }],
      ['menu:update', { enabled: false, id: 'salvar' }],
      ['menu:clear', undefined],
      ['menu:popup', { x: 10, y: 20, items: [{ id: 'copiar', label: 'Copiar' }] }],
    ]);
  });

  test('onClick recebe id e checked; o retorno para de escutar', () => {
    const cliques = [];
    const parar = menu.onClick((id, checked) => cliques.push([id, checked]));
    delphiEmite('menu:click', { id: 'salvar' });
    delphiEmite('menu:click', { id: 'quebra', checked: false });
    parar();
    delphiEmite('menu:click', { id: 'depois' });
    assert.deepEqual(cliques, [['salvar', undefined], ['quebra', false]]);
  });

  test('onItems despacha por id e ignora os outros', () => {
    const feitos = [];
    menu.onItems({ salvar: () => feitos.push('salvar'), quebra: (c) => feitos.push('quebra=' + c) });
    delphiEmite('menu:click', { id: 'salvar' });
    delphiEmite('menu:click', { id: 'quebra', checked: true });
    delphiEmite('menu:click', { id: 'desconhecido' });
    delphiEmite('menu:click', { id: 'toString' });  // não pode cair no prototype
    assert.deepEqual(feitos, ['salvar', 'quebra=true']);
  });
});

describe('@borion/api/tray', () => {
  test('comandos', async () => {
    await tray.show({ tooltip: 'Editor' });
    await tray.setTooltip('nota.txt');
    await tray.setMenu([{ id: 'sair', label: 'Sair' }]);
    await tray.notify('Salvo', 'nota.txt', { kind: 'info' });
    await tray.hide();
    assert.deepEqual(chamadas.map((c) => c[0]), ['tray:show', 'tray:setTooltip', 'tray:setMenu', 'tray:notify', 'tray:hide']);
    assert.deepEqual(chamadas[3][1], { kind: 'info', title: 'Salvo', message: 'nota.txt' });
  });

  test('eventos', () => {
    const ev = [];
    tray.onClick(() => ev.push('click'));
    tray.onDoubleClick(() => ev.push('dbl'));
    tray.onMenu((id) => ev.push('menu:' + id));
    tray.onNotificationClick(() => ev.push('balao'));
    delphiEmite('tray:click', null);
    delphiEmite('tray:doubleClick', null);
    delphiEmite('tray:menu', { id: 'sair' });
    delphiEmite('tray:balloonClick', null);
    assert.deepEqual(ev, ['click', 'dbl', 'menu:sair', 'balao']);
  });
});

describe('@borion/api/app', () => {
  test('comandos', async () => {
    respostas['app:info'] = { name: 'Editor', version: '0.1.0.0', exe: 'C:/x.exe', pid: 1 };
    assert.equal((await app.info()).name, 'Editor');
    for (const fn of [app.exit, app.show, app.hide, app.minimize]) assert.equal(await fn(), undefined);
    assert.deepEqual(chamadas.map((c) => c[0]), ['app:info', 'app:exit', 'app:show', 'app:hide', 'app:minimize']);
  });
});

// Texto com acento e emoji: o Delphi 7 (ANSI) não os representaria em string,
// então clipboard e store trafegam JSON só com ASCII.
const B = String.fromCharCode(92);
const OLA = 'olá ' + String.fromCodePoint(0x1f600);
const OLA_ASCII = '"ol' + B + 'u00e1 ' + B + 'ud83d' + B + 'ude00"';

describe('JSON só com ASCII', () => {
  test('escapa tudo fora de ASCII imprimível e volta igual', () => {
    assert.equal(asciiJson(OLA), OLA_ASCII);
    const valor = { nome: OLA, lista: [1, null, true, 'a' + String.fromCharCode(127) + 'b'], n: 1.5 };
    const json = asciiJson(valor);
    assert.match(json, /^[ -~]*$/);
    assert.deepEqual(JSON.parse(json), valor);
    assert.equal(asciiJson(undefined), undefined);
    assert.equal(asciiJson(() => 1), undefined);
  });
});

describe('@borion/api/clipboard', () => {
  test('writeText e writeHtml mandam literais ASCII', async () => {
    await clipboard.writeText(OLA);
    await clipboard.writeHtml('<b>' + OLA + '</b>', OLA);
    await clipboard.writeHtml('<i>x</i>');
    await clipboard.clear();
    assert.deepEqual(chamadas, [
      ['clipboard:writeText', { text: OLA_ASCII }],
      ['clipboard:writeHtml', { html: asciiJson('<b>' + OLA + '</b>'), altText: OLA_ASCII }],
      ['clipboard:writeHtml', { html: '"<i>x</i>"' }],
      ['clipboard:clear', undefined],
    ]);
  });

  test('readText decodifica; null quando não há texto', async () => {
    respostas['clipboard:readText'] = OLA_ASCII;
    assert.equal(await clipboard.readText(), OLA);
    respostas['clipboard:readText'] = null;
    assert.equal(await clipboard.readText(), null);
  });
});

describe('@borion/api/store', () => {
  test('load valida pelo Delphi e devolve um Store', async () => {
    const s = await load('Settings');
    assert.ok(s instanceof Store);
    assert.equal(s.file, 'settings.json');
    assert.deepEqual(chamadas[0], ['store:load', { store: 'Settings' }]);
  });

  test('set e get com qualquer valor JSON, Unicode intacto', async () => {
    const s = new Store('prefs.json');
    await s.set('nome', OLA);
    await s.set('janela', { w: 800, h: 600 });
    assert.deepEqual(chamadas[0], ['store:set', { store: 'prefs.json', key: '"nome"', value: OLA_ASCII }]);
    assert.deepEqual(chamadas[1][1].value, '{"w":800,"h":600}');
    respostas['store:get'] = OLA_ASCII;
    assert.equal(await s.get('nome'), OLA);
    respostas['store:get'] = null;
    assert.equal(await s.get('nada'), undefined);
    respostas['store:get'] = 'null';
    assert.equal(await s.get('vazio'), null, 'null guardado é diferente de não existir');
  });

  test('valores e chaves inválidos são recusados no JS', async () => {
    const s = new Store('x');
    await assert.rejects(s.set('f', () => 1), TypeError);
    await assert.rejects(s.set('u', undefined), TypeError);
    await assert.rejects(s.get(1), TypeError);
    assert.equal(chamadas.length, 0);
  });

  test('entries, keys, values e length', async () => {
    const s = new Store('x');
    respostas['store:entries'] = [['"b"', '2'], ['"' + B + 'u00e9"', '{"a":[1]}']];
    assert.deepEqual(await s.entries(), [['b', 2], ['é', { a: [1] }]]);
    assert.deepEqual(await s.keys(), ['b', 'é']);
    assert.deepEqual(await s.values(), [2, { a: [1] }]);
    assert.equal(await s.length(), 2);
  });

  test('has, delete, clear, save e reload', async () => {
    const s = new Store('x');
    await s.has('a'); await s.delete('a'); await s.clear(); await s.save(); await s.reload();
    assert.deepEqual(chamadas.map((c) => c[0]), ['store:has', 'store:delete', 'store:clear', 'store:save', 'store:reload']);
    assert.deepEqual(chamadas[1][1], { store: 'x', key: '"a"' });
  });

  test('onChange e onKeyChange filtram pelo arquivo e decodificam', () => {
    const s = new Store('Prefs');
    const mudancas = [];
    const parar = s.onChange((k, v) => mudancas.push([k, v]));
    s.onKeyChange('tema', (v) => mudancas.push(['tema!', v]));
    delphiEmite('store:change', { store: 'prefs.json', key: '"tema"', value: '"escuro"' });
    delphiEmite('store:change', { store: 'outro.json', key: '"tema"', value: '"claro"' });
    delphiEmite('store:change', { store: 'prefs.json', key: '"n' + B + 'u00e3o"', value: null });
    parar();
    delphiEmite('store:change', { store: 'prefs.json', key: '"tema"', value: '1' });
    assert.deepEqual(mudancas, [['tema', 'escuro'], ['tema!', 'escuro'], ['não', undefined], ['tema!', 1]]);
  });
});

describe('@borion/api/os', () => {
  test('info e os campos', async () => {
    respostas['os:info'] = { platform: 'windows', arch: 'x86_64', version: '10.0.22631', locale: 'pt-BR', hostname: 'PC', eol: '\r\n' };
    assert.equal(await os.platform(), 'windows');
    assert.equal(await os.arch(), 'x86_64');
    assert.equal(await os.version(), '10.0.22631');
    assert.equal(await os.locale(), 'pt-BR');
    assert.equal(await os.hostname(), 'PC');
    assert.equal(await os.eol(), '\r\n');
    assert.equal((await os.info()).platform, 'windows');
    assert.ok(chamadas.every((c) => c[0] === 'os:info'));
  });
});

describe('@borion/api/http', () => {
  const base64 = (texto) => Buffer.from(texto).toString('base64');
  const ok = (extra = {}) => ({
    status: 200, statusText: 'OK', url: 'https://api.exemplo.com/x', redirected: false,
    headers: [['content-type', 'application/json']], body: base64('{"a":1}'), ...extra,
  });

  test('GET: devolve um Response de verdade', async () => {
    respostas['http:fetch'] = ok({ redirected: true });
    const r = await httpFetch('https://api.exemplo.com/x#frag', { headers: { 'X-Teste': '1' }, timeout: 5000 });
    assert.ok(r instanceof Response);
    assert.equal(r.status, 200);
    assert.equal(r.ok, true);
    assert.equal(r.url, 'https://api.exemplo.com/x');
    assert.equal(r.redirected, true);
    assert.equal(r.headers.get('Content-Type'), 'application/json');
    assert.deepEqual(await r.json(), { a: 1 });
    const [cmd, args] = chamadas[0];
    assert.equal(cmd, 'http:fetch');
    assert.equal(args.url, 'https://api.exemplo.com/x', 'sem o fragmento');
    assert.equal(args.method, 'GET');
    assert.deepEqual(args.headers, [['x-teste', '1']]);
    assert.equal(args.timeout, 5000);
    assert.equal(args.redirect, 'follow');
    assert.equal(args.body, undefined);
    assert.match(args.rid, /./);
  });

  test('corpo: string vira UTF-8 com Content-Type padrão; bytes passam iguais', async () => {
    respostas['http:fetch'] = ok();
    await httpFetch('https://api.exemplo.com/x', { method: 'post', body: 'olá' });
    assert.equal(chamadas[0][1].method, 'POST');
    assert.equal(chamadas[0][1].body, base64('olá'));
    assert.deepEqual(chamadas[0][1].headers, [['content-type', 'text/plain;charset=UTF-8']]);
    await httpFetch('https://api.exemplo.com/x', { method: 'PUT', body: new Uint8Array([0, 255, 7]), headers: { 'content-type': 'x/y' } });
    assert.equal(chamadas[1][1].body, Buffer.from([0, 255, 7]).toString('base64'));
    assert.deepEqual(chamadas[1][1].headers, [['content-type', 'x/y']]);
    await httpFetch('https://api.exemplo.com/x', { method: 'POST', body: new URLSearchParams({ q: 'a b' }) });
    assert.equal(Buffer.from(chamadas[2][1].body, 'base64').toString(), 'q=a+b');
    await assert.rejects(httpFetch('https://api.exemplo.com/x', { body: 'x' }), TypeError, 'GET com corpo');
    await assert.rejects(httpFetch('https://api.exemplo.com/x', { method: 'POST', body: { a: 1 } }), TypeError);
  });

  test('status sem corpo e erros HTTP resolvem', async () => {
    respostas['http:fetch'] = ok({ status: 204, statusText: 'No Content', body: '' });
    assert.equal((await httpFetch('https://api.exemplo.com/x', { method: 'DELETE' })).status, 204);
    respostas['http:fetch'] = ok({ status: 404, statusText: 'Not Found', body: base64('nada') });
    const r = await httpFetch('https://api.exemplo.com/x');
    assert.equal(r.ok, false);
    assert.equal(await r.text(), 'nada');
  });

  test('erros do Delphi chegam com code', async () => {
    globalThis.__BORION__.invoke = () => {
      const e = new Error('fora do escopo'); e.code = 'FORBIDDEN_URL';
      return Promise.reject(e);
    };
    await assert.rejects(httpFetch('https://outro.com/'), (e) => e.code === 'FORBIDDEN_URL');
  });

  test('AbortSignal cancela no Delphi e rejeita com AbortError', async () => {
    globalThis.__BORION__.invoke = (cmd, args) => {
      chamadas.push([cmd, args]);
      if (cmd === 'http:fetch') return new Promise(() => {});  // nunca responde
      return Promise.resolve(true);
    };
    const controle = new AbortController();
    const p = httpFetch('https://api.exemplo.com/lento', { signal: controle.signal });
    await new Promise((r) => setTimeout(r, 10));
    controle.abort();
    await assert.rejects(p, (e) => e.name === 'AbortError');
    assert.deepEqual(chamadas[1], ['http:cancel', { rid: chamadas[0][1].rid }]);
    await assert.rejects(httpFetch('https://api.exemplo.com/x', { signal: AbortSignal.abort() }), (e) => e.name === 'AbortError');
    assert.equal(chamadas.length, 2, 'já abortado: nem chama o Delphi');
  });

  test('aceita um Request', async () => {
    respostas['http:fetch'] = ok();
    await httpFetch(new Request('https://api.exemplo.com/r', { method: 'POST', body: 'x', headers: { 'x-a': 'b' } }));
    assert.equal(chamadas[0][1].method, 'POST');
    assert.equal(chamadas[0][1].url, 'https://api.exemplo.com/r');
    assert.equal(chamadas[0][1].body, base64('x'));
    assert.ok(chamadas[0][1].headers.some(([n, v]) => n === 'x-a' && v === 'b'));
  });
});

describe('@borion/api/notification', () => {
  test('sendNotification: título em string ou opções completas, textos em ASCII', async () => {
    respostas['notification:send'] = 'n1-1';
    assert.equal(await notification.sendNotification('Oi'), 'n1-1');
    await notification.sendNotification({
      id: 'pedido-1', title: OLA, body: 'corpo', silent: true,
      actions: [{ id: 'sim', title: 'Sim' }, { id: 'nao', title: 'Não' }],
    });
    assert.deepEqual(chamadas[0], ['notification:send', { title: '"Oi"' }]);
    assert.deepEqual(chamadas[1][1], {
      title: OLA_ASCII, body: '"corpo"', id: 'pedido-1', silent: true,
      actions: [{ id: 'sim', title: '"Sim"' }, { id: 'nao', title: '"N' + B + 'u00e3o"' }],
    });
  });

  test('permissão, hide e eventos', async () => {
    respostas['notification:permission'] = 'granted';
    assert.equal(await notification.isPermissionGranted(), true);
    assert.equal(await notification.requestPermission(), 'granted');
    respostas['notification:permission'] = 'denied';
    assert.equal(await notification.isPermissionGranted(), false);
    await notification.hide('x');
    assert.deepEqual(chamadas.at(-1), ['notification:hide', { id: 'x' }]);
    const ev = [];
    notification.onAction((e) => ev.push(['click', e.id, e.action]));
    notification.onDismissed((e) => ev.push(['fechou', e.id, e.reason]));
    delphiEmite('notification:click', { id: 'a', action: null });
    delphiEmite('notification:click', { id: 'a', action: 'sim' });
    delphiEmite('notification:dismissed', { id: 'b', reason: 'user' });
    assert.deepEqual(ev, [['click', 'a', null], ['click', 'a', 'sim'], ['fechou', 'b', 'user']]);
  });
});

describe('@borion/api/single-instance', () => {
  test('args e onSecondInstance decodificam os literais', async () => {
    const lit = (t) => asciiJson(t);
    respostas['single-instance:args'] = { args: [lit('--x'), lit('C:' + B + OLA)], cwd: lit('C:' + B + 'p') };
    assert.deepEqual(await singleInstance.args(), { args: ['--x', 'C:' + B + OLA], cwd: 'C:' + B + 'p' });
    const recebidos = [];
    singleInstance.onSecondInstance((e) => recebidos.push(e));
    delphiEmite('single-instance:second', { args: [lit('nota.txt')], cwd: lit('D:' + B) });
    assert.deepEqual(recebidos, [{ args: ['nota.txt'], cwd: 'D:' + B }]);
  });
});

describe('@borion/api/deep-link', () => {
  test('getCurrent: null sem link, URLs decodificadas com link', async () => {
    respostas['deep-link:getCurrent'] = [];
    assert.equal(await deepLink.getCurrent(), null);
    respostas['deep-link:getCurrent'] = [asciiJson('meuapp://abrir?nome=João')];
    assert.deepEqual(await deepLink.getCurrent(), ['meuapp://abrir?nome=João']);
  });

  test('onOpenUrl, register, unregister e isRegistered', async () => {
    const recebidas = [];
    deepLink.onOpenUrl((urls) => recebidas.push(urls));
    delphiEmite('deep-link:open', { urls: [asciiJson('meuapp://a'), asciiJson('meuapp://b')] });
    assert.deepEqual(recebidas, [['meuapp://a', 'meuapp://b']]);
    respostas['deep-link:isRegistered'] = true;
    await deepLink.register('meuapp');
    await deepLink.unregister('meuapp');
    assert.equal(await deepLink.isRegistered('meuapp'), true);
    assert.deepEqual(chamadas, [
      ['deep-link:register', { scheme: 'meuapp' }],
      ['deep-link:unregister', { scheme: 'meuapp' }],
      ['deep-link:isRegistered', { scheme: 'meuapp' }],
    ]);
  });
});

describe('@borion/api/autostart', () => {
  test('comandos', async () => {
    respostas['autostart:isEnabled'] = true;
    respostas['autostart:launchedAtLogin'] = false;
    assert.equal(await autostart.enable(), undefined);
    assert.equal(await autostart.isEnabled(), true);
    assert.equal(await autostart.launchedAtLogin(), false);
    assert.equal(await autostart.disable(), undefined);
    assert.deepEqual(chamadas.map((c) => c[0]),
      ['autostart:enable', 'autostart:isEnabled', 'autostart:launchedAtLogin', 'autostart:disable']);
  });
});
