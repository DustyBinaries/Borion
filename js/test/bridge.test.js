// Testes da ponte JS real (a mesma string que o TBorionIpc injeta nas páginas).
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { bootPage, fakeWebview, response, failure, event } from './helpers.js';

describe('ponte: instalação', () => {
  test('expõe window.__BORION__ (congelado), sem window.borion', () => {
    const { win, borion } = bootPage();
    assert.ok(borion);
    assert.equal(win.borion, undefined);
    assert.ok(Object.isFrozen(borion));
    for (const fn of ['invoke', 'listen', 'once', 'emit', 'emitTo']) assert.equal(typeof borion[fn], 'function');
    assert.match(borion.version, /^\d+\.\d+\.\d+$/);
  });

  test('a página não consegue substituir window.__BORION__', () => {
    const { win, borion } = bootPage();
    assert.throws(() => { win.__BORION__ = {}; }, TypeError);
    assert.equal(win.__BORION__, borion);
  });

  test('sem chrome.webview (navegador comum) a API não é criada', () => {
    const { borion } = bootPage({ webview: null });
    assert.equal(borion, undefined);
  });

  test('injetar duas vezes não duplica o listener', () => {
    const { wv } = bootPage({ runs: 2 });
    assert.equal(wv.handlers.length, 1);
  });
});

describe('ponte: invoke', () => {
  test('envia a mensagem do protocolo', () => {
    const { wv, borion } = bootPage();
    borion.invoke('somar', { a: 20, b: 22 });
    borion.invoke('semArgs');
    borion.invoke('argsNull', null);
    assert.deepEqual(wv.sent[0], { __borion: 1, kind: 'invoke', id: 1, cmd: 'somar', args: { a: 20, b: 22 } });
    assert.deepEqual(wv.sent[1].args, {});
    assert.deepEqual(wv.sent[2].args, {});
    assert.equal(wv.sent[2].id, 3);
  });

  test('resolve cada Promise pelo id, mesmo fora de ordem', async () => {
    const { wv, borion } = bootPage();
    const a = borion.invoke('a');
    const b = borion.invoke('b');
    wv.deliver(response(2, 'resultado b'));
    wv.deliver(response(1, { x: 1 }));
    assert.deepEqual(await a, { x: 1 });
    assert.equal(await b, 'resultado b');
  });

  test('resultado null é válido', async () => {
    const { wv, borion } = bootPage();
    const p = borion.invoke('nada');
    wv.deliver(response(1, null));
    assert.equal(await p, null);
  });

  test('erro do Delphi rejeita com code, message e command', async () => {
    const { wv, borion } = bootPage();
    const p = borion.invoke('saudacao', { nome: '' });
    wv.deliver(failure(1, 'VALIDACAO', 'Informe o nome.'));
    await assert.rejects(p, (e) => {
      assert.equal(e.code, 'VALIDACAO');
      assert.equal(e.message, 'Informe o nome.');
      assert.equal(e.command, 'saudacao');
      return true;
    });
  });

  test('erro sem detalhes vira code ERROR', async () => {
    const { wv, borion } = bootPage();
    const p = borion.invoke('x');
    wv.deliver({ __borion: 1, kind: 'response', id: 1, ok: false });
    await assert.rejects(p, (e) => e.code === 'ERROR');
  });

  test('timeout rejeita com TIMEOUT e a resposta atrasada é ignorada', async () => {
    const { wv, borion } = bootPage();
    const p = borion.invoke('lento', {}, { timeout: 20 });
    await assert.rejects(p, (e) => e.code === 'TIMEOUT' && e.command === 'lento');
    assert.doesNotThrow(() => wv.deliver(response(1, 'tarde demais')));
  });

  test('resposta com id desconhecido é ignorada', () => {
    const { wv } = bootPage();
    assert.doesNotThrow(() => wv.deliver(response(999, 'x')));
  });
});

describe('ponte: eventos', () => {
  test('listen recebe payload e nome do evento; unlisten para', () => {
    const { wv, borion } = bootPage();
    const recebidos = [];
    const parar = borion.listen('progresso', (p, nome) => recebidos.push([nome, p]));
    wv.deliver(event('progresso', { pct: 50 }));
    wv.deliver(event('outro', 1));
    parar();
    wv.deliver(event('progresso', { pct: 100 }));
    assert.deepEqual(recebidos, [['progresso', { pct: 50 }]]);
  });

  test('once dispara uma única vez', () => {
    const { wv, borion } = bootPage();
    let n = 0;
    borion.once('x', () => n++);
    wv.deliver(event('x'));
    wv.deliver(event('x'));
    assert.equal(n, 1);
  });

  test('erro num listener não impede os outros', () => {
    const { wv, borion, consoleErrors } = bootPage();
    let chamou = false;
    borion.listen('x', () => { throw new Error('quebrado'); });
    borion.listen('x', () => { chamou = true; });
    wv.deliver(event('x'));
    assert.ok(chamou);
    assert.equal(consoleErrors.length, 1);
  });

  test('emit envia o evento; payload ausente vira null', () => {
    const { wv, borion } = bootPage();
    borion.emit('salvou', { id: 7 });
    borion.emit('ping');
    assert.deepEqual(wv.sent[0], { __borion: 1, kind: 'emit', event: 'salvou', payload: { id: 7 } });
    assert.equal(wv.sent[1].payload, null);
  });

  test('emitTo envia para outra janela; label vem do Delphi (main por padrão)', () => {
    const { wv, borion } = bootPage();
    borion.emitTo('config', 'tema', { escuro: true });
    borion.emitTo('*', 'oi');
    assert.deepEqual(wv.sent[0], { __borion: 1, kind: 'emitTo', target: 'config', event: 'tema', payload: { escuro: true } });
    assert.equal(wv.sent[1].target, '*');
    assert.equal(wv.sent[1].payload, null);
    assert.equal(borion.label, 'main', 'sem o script do rótulo: main');
  });
});

describe('ponte: isolamento das mensagens', () => {
  test('mensagens do Borion não chegam aos listeners da própria página', () => {
    const wv = fakeWebview();
    bootPage({ webview: wv });
    const daPagina = [];
    wv.addEventListener('message', (e) => daPagina.push(e.data));
    assert.equal(wv.deliver(event('x', 1)), true, 'stopImmediatePropagation');
    wv.deliver('texto comum');
    wv.deliver({ acao: 'salvar' });
    assert.deepEqual(daPagina, ['texto comum', { acao: 'salvar' }]);
  });

  test('objetos sem __borion: 1 são ignorados pela ponte', () => {
    const { wv, borion } = bootPage();
    let n = 0;
    borion.listen('x', () => n++);
    wv.deliver({ kind: 'event', event: 'x' });
    wv.deliver({ __borion: 2, kind: 'event', event: 'x' });
    assert.equal(n, 0);
  });
});
