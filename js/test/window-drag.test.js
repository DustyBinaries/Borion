// Testes do script que o plugin window injeta em cada janela (a mesma string do
// BorionWindowDragScript): a região de arrastar e a borda de redimensionar.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { windowDragSource } from './helpers.js';

const tick = () => new Promise((r) => setTimeout(r, 0));

function fakeElement(attrs = {}) {
  return {
    attrs: { ...attrs },
    children: [],
    getAttribute(n) { return n in this.attrs ? this.attrs[n] : null; },
    setAttribute(n, v) { this.attrs[n] = String(v); },
    removeAttribute(n) { delete this.attrs[n]; },
    appendChild(c) { this.children.push(c); },
  };
}

function fakeTarget() {
  const handlers = [];
  return {
    handlers,
    addEventListener(type, fn, capture) { handlers.push({ type, fn, capture: !!capture }); },
  };
}

// Roda o script numa página falsa de 800x600. resizeBorder: o que o Delphi responde
// ao window:internalResizeBorder.
async function boot({ resizeBorder = false, bridge = true, top = true } = {}) {
  const calls = [];
  const listeners = {};
  const root = fakeElement();
  const head = fakeElement();
  const win = fakeTarget();
  const doc = fakeTarget();
  Object.assign(doc, { documentElement: root, head, createElement: () => fakeElement() });
  const sandbox = Object.assign(win, { document: doc, innerWidth: 800, innerHeight: 600 });
  sandbox.window = sandbox;
  sandbox.top = top ? sandbox : {};
  if (bridge) {
    sandbox.__BORION__ = {
      invoke(cmd, args) {
        // JSON: os objetos do contexto do vm têm outro Object.prototype
        calls.push(args === undefined ? [cmd] : [cmd, JSON.parse(JSON.stringify(args))]);
        return Promise.resolve(cmd === 'window:internalResizeBorder' ? { enabled: resizeBorder } : null);
      },
      listen(event, fn) { listeners[event] = fn; return () => {}; },
    };
  }
  vm.createContext(sandbox);
  vm.runInContext(windowDragSource(), sandbox);
  await tick();

  // dispara um evento do mouse: primeiro a fase de captura da janela, depois o document
  function fire(type, { x = 400, y = 300, button = 0, detail = 1, target = fakeElement() } = {}) {
    const ev = {
      type, clientX: x, clientY: y, button, detail, target,
      defaultPrevented: false, stopped: false,
      preventDefault() { this.defaultPrevented = true; },
      stopImmediatePropagation() { this.stopped = true; },
    };
    for (const h of win.handlers.filter((h) => h.type === type && h.capture)) {
      if (!ev.stopped) h.fn(ev);
    }
    for (const h of doc.handlers.filter((h) => h.type === type)) {
      if (!ev.stopped) h.fn(ev);
    }
    return ev;
  }
  const commands = () => calls.filter((c) => c[0] !== 'window:internalResizeBorder');
  return { sandbox, calls, commands, listeners, root, head, win, doc, fire };
}

describe('script de arrastar: região', () => {
  test('mousedown no elemento com data-borion-drag-region arrasta', async () => {
    const p = await boot();
    const ev = p.fire('mousedown', { target: fakeElement({ 'data-borion-drag-region': '' }) });
    assert.deepEqual(p.commands(), [['window:startDragging']]);
    assert.ok(ev.defaultPrevented, 'sem seleção de texto');
  });

  test('duplo clique maximiza/restaura', async () => {
    const p = await boot();
    p.fire('mousedown', { detail: 2, target: fakeElement({ 'data-borion-drag-region': '' }) });
    assert.deepEqual(p.commands(), [['window:internalToggleMaximize']]);
  });

  test('ignora outros elementos, outros botões, valor "false" e clique triplo', async () => {
    const p = await boot();
    p.fire('mousedown', { target: fakeElement() });
    p.fire('mousedown', { button: 2, target: fakeElement({ 'data-borion-drag-region': '' }) });
    p.fire('mousedown', { target: fakeElement({ 'data-borion-drag-region': 'false' }) });
    p.fire('mousedown', { detail: 3, target: fakeElement({ 'data-borion-drag-region': '' }) });
    p.fire('mousedown', { target: null });
    assert.deepEqual(p.commands(), []);
  });

  test('não instala sem a ponte, num iframe ou duas vezes', async () => {
    assert.equal((await boot({ bridge: false })).doc.handlers.length, 0);
    assert.equal((await boot({ top: false })).doc.handlers.length, 0);
    const p = await boot();
    vm.runInContext(windowDragSource(), p.sandbox);
    assert.equal(p.doc.handlers.length, 1);
  });
});

describe('script de arrastar: borda de redimensionar', () => {
  test('desligada (janela com borda): a borda da página é página', async () => {
    const p = await boot({ resizeBorder: false });
    p.fire('mousemove', { x: 0, y: 300 });
    assert.equal(p.root.getAttribute('data-borion-resize'), null);
    const ev = p.fire('mousedown', { x: 0, y: 300 });
    assert.deepEqual(p.commands(), []);
    assert.ok(!ev.defaultPrevented);
  });

  test('ligada: cursor e direção em cada borda e canto', async () => {
    const p = await boot({ resizeBorder: true });
    const casos = [
      [0, 300, 'West', 'ew'], [799, 300, 'East', 'ew'], [400, 0, 'North', 'ns'], [400, 599, 'South', 'ns'],
      [2, 2, 'NorthWest', 'nwse'], [797, 597, 'SouthEast', 'nwse'], [797, 2, 'NorthEast', 'nesw'],
      [2, 597, 'SouthWest', 'nesw'],
      // cantos mais largos que a borda
      [12, 1, 'NorthWest', 'nwse'], [1, 590, 'SouthWest', 'nesw'],
    ];
    for (const [x, y, dir, cursor] of casos) {
      p.calls.length = 0;
      p.fire('mousemove', { x, y });
      assert.equal(p.root.getAttribute('data-borion-resize'), cursor, `${x},${y}`);
      const ev = p.fire('mousedown', { x, y, target: fakeElement({ 'data-borion-drag-region': '' }) });
      assert.deepEqual(p.commands(), [['window:startResizeDragging', { direction: dir }]], `${x},${y}`);
      assert.ok(ev.stopped, 'a página e a região de arrastar não recebem');
    }
    p.fire('mousemove', { x: 400, y: 300 });
    assert.equal(p.root.getAttribute('data-borion-resize'), null, 'no meio, o cursor da página');
    assert.equal(p.head.children.length, 1, 'um <style> só');
    assert.match(p.head.children[0].textContent, /html\[data-borion-resize=nwse\] \* \{ cursor: nwse-resize !important; \}/);
  });

  test('o evento window:resize-border liga e desliga', async () => {
    const p = await boot({ resizeBorder: false });
    p.listeners['window:resize-border']({ enabled: true });
    p.fire('mousemove', { x: 0, y: 300 });
    assert.equal(p.root.getAttribute('data-borion-resize'), 'ew');
    p.listeners['window:resize-border']({ enabled: false });
    assert.equal(p.root.getAttribute('data-borion-resize'), null, 'desligar tira o cursor');
    p.fire('mousedown', { x: 0, y: 300 });
    assert.deepEqual(p.commands(), []);
  });
});
