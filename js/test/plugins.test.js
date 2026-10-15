// Testes dos módulos de plugins (@borion/api/dialog, /fs, /shell): verificam que
// cada função chama o comando certo do Delphi com os argumentos certos.
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as dialog from '../dialog.js';
import * as fs from '../fs.js';
import * as shell from '../shell.js';

let chamadas;
let respostas;

function ponteFalsa() {
  return {
    version: 'teste',
    invoke(cmd, args) {
      chamadas.push([cmd, args]);
      return Promise.resolve(cmd in respostas ? respostas[cmd] : null);
    },
    listen() {}, once() {}, emit() {},
  };
}

beforeEach(() => {
  chamadas = [];
  respostas = {};
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
