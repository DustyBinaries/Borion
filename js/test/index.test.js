// Testes do pacote ESM @borion/api (index.js).
import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import * as api from '../index.js';
import apiDefault from '../index.js';
import { bootPage, response } from './helpers.js';

function fakeBridge() {
  const calls = [];
  const unlisten = () => {};
  return {
    calls,
    unlisten,
    version: '9.9.9',
    invoke: (...a) => { calls.push(['invoke', ...a]); return Promise.resolve('ok'); },
    listen: (...a) => { calls.push(['listen', ...a]); return unlisten; },
    once: (...a) => { calls.push(['once', ...a]); return unlisten; },
    emit: (...a) => { calls.push(['emit', ...a]); },
  };
}

beforeEach(() => { delete globalThis.__BORION__; });
afterEach(() => { delete globalThis.__BORION__; });

describe('@borion/api fora de um app Borion', () => {
  test('isBorion() é false e version() é null', () => {
    assert.equal(api.isBorion(), false);
    assert.equal(api.version(), null);
  });

  test('invoke rejeita com NOT_AVAILABLE (sem lançar)', async () => {
    const p = api.invoke('somar', { a: 1 });
    assert.ok(p instanceof Promise);
    await assert.rejects(p, (e) => e.code === api.NOT_AVAILABLE && e.command === 'somar');
  });

  test('listen, once e emit lançam NOT_AVAILABLE', () => {
    for (const fn of [() => api.listen('x', () => {}), () => api.once('x', () => {}), () => api.emit('x')]) {
      assert.throws(fn, (e) => e.code === 'NOT_AVAILABLE');
    }
  });
});

describe('@borion/api dentro de um app Borion', () => {
  test('delega para window.__BORION__ com os mesmos argumentos', async () => {
    const b = fakeBridge();
    globalThis.__BORION__ = b;
    const h = () => {};
    assert.equal(await api.invoke('cmd', { a: 1 }, { timeout: 5 }), 'ok');
    assert.equal(api.listen('ev', h), b.unlisten);
    assert.equal(api.once('ev2', h), b.unlisten);
    api.emit('ev3', { x: 1 });
    assert.deepEqual(b.calls, [
      ['invoke', 'cmd', { a: 1 }, { timeout: 5 }],
      ['listen', 'ev', h],
      ['once', 'ev2', h],
      ['emit', 'ev3', { x: 1 }],
    ]);
    assert.equal(api.isBorion(), true);
    assert.equal(api.version(), '9.9.9');
  });

  test('a ponte é procurada a cada chamada, não na importação', async () => {
    assert.equal(api.isBorion(), false);   // módulo já importado, ponte ausente
    globalThis.__BORION__ = fakeBridge();  // ponte aparece depois
    assert.equal(await api.invoke('x'), 'ok');
  });

  test('o export default tem as mesmas funções', () => {
    for (const k of ['invoke', 'listen', 'once', 'emit', 'isBorion', 'version']) {
      assert.equal(apiDefault[k], api[k]);
    }
    assert.equal(apiDefault.NOT_AVAILABLE, 'NOT_AVAILABLE');
  });

  test('de ponta a ponta com a ponte real', async () => {
    const { wv, borion } = bootPage();
    globalThis.__BORION__ = borion;
    const p = api.invoke('somar', { a: 20, b: 22 });
    assert.deepEqual(wv.sent[0], { __borion: 1, kind: 'invoke', id: 1, cmd: 'somar', args: { a: 20, b: 22 } });
    wv.deliver(response(1, 42));
    assert.equal(await p, 42);
    assert.equal(api.version(), borion.version);
  });
});
