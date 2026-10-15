// Carrega a ponte real (gerada pelo Delphi) num contexto isolado do node:vm,
// com um chrome.webview falso que registra o que a ponte envia e permite
// simular as mensagens que o Delphi manda.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

// Exportada pelo teste DUnit TTestBorionBridge.TestExportaParaTestesJs
export const BRIDGE_PATH = path.resolve(here, '../../Tests/out/borion-bridge.js');

let source = null;
export function bridgeSource() {
  if (source === null) {
    if (!fs.existsSync(BRIDGE_PATH)) {
      throw new Error(
        'Ponte não encontrada em ' + BRIDGE_PATH +
        '. Rode Tests/run-tests.bat: os testes DUnit exportam a ponte antes dos testes JS.'
      );
    }
    source = fs.readFileSync(BRIDGE_PATH, 'utf8');
  }
  return source;
}

export function fakeWebview() {
  const handlers = [];
  const sent = [];
  return {
    sent,
    handlers,
    postMessage(msg) {
      sent.push(JSON.parse(JSON.stringify(msg)));
    },
    addEventListener(type, fn) {
      if (type === 'message') handlers.push(fn);
    },
    // Delphi -> página. Devolve true se algum listener chamou stopImmediatePropagation.
    deliver(data) {
      let stopped = false;
      const ev = { data, stopImmediatePropagation() { stopped = true; } };
      for (const h of handlers.slice()) {
        h(ev);
        if (stopped) break;
      }
      return stopped;
    },
  };
}

// Simula uma página: roda a ponte `runs` vezes num contexto novo.
export function bootPage({ webview = fakeWebview(), runs = 1 } = {}) {
  const consoleErrors = [];
  const sandbox = {
    setTimeout,
    clearTimeout,
    console: { error: (...args) => consoleErrors.push(args), log() {} },
  };
  if (webview) sandbox.chrome = { webview };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  for (let i = 0; i < runs; i++) vm.runInContext(bridgeSource(), sandbox);
  return { win: sandbox, wv: webview, borion: sandbox.borion, consoleErrors };
}

export function response(id, result) {
  return { __borion: 1, kind: 'response', id, ok: true, result };
}

export function failure(id, code, message) {
  return { __borion: 1, kind: 'response', id, ok: false, error: { code, message } };
}

export function event(name, payload) {
  return { __borion: 1, kind: 'event', event: name, payload };
}
