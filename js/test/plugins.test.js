// Testes dos módulos de plugins (@borion/api/dialog, /fs, /shell): verificam que
// cada função chama o comando certo do Delphi com os argumentos certos.
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as dialog from '../dialog.js';
import * as fs from '../fs.js';
import * as shell from '../shell.js';
import * as menu from '../menu.js';
import * as tray from '../tray.js';
import * as app from '../app.js';

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
