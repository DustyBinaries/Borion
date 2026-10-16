// @borion/api/log — log em arquivo, o mesmo do Delphi (plugin "log" do Delphi:
// TBorionLogPlugin). Interface parecida com a do plugin log do Tauri.
//
//   import { info, error, forwardConsole, attachConsole } from '@borion/api/log';
//   info('pedido salvo');
//   forwardConsole();   // console.log/warn/error da página também vão para o arquivo
//   attachConsole();    // o que o Delphi loga aparece no console do DevTools
import { invoke, listen } from './index.js';
import { asciiString } from './ascii-json.js';

// o forwardConsole usa este target; o attachConsole não repete essas linhas no console
const DO_CONSOLE = 'console';
// true enquanto o attachConsole imprime: o forwardConsole não grava de novo o que
// já veio do arquivo (senão cada linha voltaria duplicada)
let ecoando = false;

function escrever(level, message, options = {}) {
  return invoke('log:write', {
    level,
    message: asciiString(message),
    target: options.target || 'js',
  }).then(() => undefined);
}

/** options.target: rótulo da linha (padrão 'js') */
export const trace = (message, options) => escrever('trace', message, options);
export const debug = (message, options) => escrever('debug', message, options);
export const info = (message, options) => escrever('info', message, options);
export const warn = (message, options) => escrever('warn', message, options);
export const error = (message, options) => escrever('error', message, options);

/** Caminho do arquivo de log. */
export async function logPath() {
  return JSON.parse(await invoke('log:path'));
}

function formatar(args) {
  return args.map((a) => {
    if (typeof a === 'string') return a;
    if (a instanceof Error) return a.stack || `${a.name}: ${a.message}`;
    try {
      return JSON.stringify(a);
    } catch {
      return String(a);
    }
  }).join(' ');
}

const NIVEL_DO_CONSOLE = { debug: 'debug', log: 'info', info: 'info', warn: 'warn', error: 'error' };

/**
 * Também grava no arquivo o que a página manda para o console (log, info, warn,
 * error, debug), além dos erros não tratados. Devolve uma função que desfaz.
 */
export function forwardConsole() {
  const originais = {};
  for (const [metodo, nivel] of Object.entries(NIVEL_DO_CONSOLE)) {
    originais[metodo] = console[metodo];
    console[metodo] = (...args) => {
      originais[metodo].apply(console, args);
      if (!ecoando) escrever(nivel, formatar(args), { target: DO_CONSOLE }).catch(() => {});
    };
  }
  const aoErro = (e) => escrever('error', formatar([e.error || e.message]), { target: DO_CONSOLE }).catch(() => {});
  const aoRejeitar = (e) => escrever('error', 'Promise rejeitada: ' + formatar([e.reason]), { target: DO_CONSOLE }).catch(() => {});
  const alvo = globalThis.addEventListener ? globalThis : null;
  if (alvo) {
    alvo.addEventListener('error', aoErro);
    alvo.addEventListener('unhandledrejection', aoRejeitar);
  }
  return () => {
    Object.assign(console, originais);
    if (alvo) {
      alvo.removeEventListener('error', aoErro);
      alvo.removeEventListener('unhandledrejection', aoRejeitar);
    }
  };
}

const NO_CONSOLE = { trace: 'debug', debug: 'debug', info: 'info', warn: 'warn', error: 'error' };

/**
 * Mostra no console do DevTools cada linha gravada no log (do Delphi e da página).
 * Devolve uma função que desfaz.
 */
export async function attachConsole() {
  await invoke('log:attach');
  const parar = listen('log:entry', (p) => {
    if (p.target === DO_CONSOLE) return;  // já apareceu no console
    ecoando = true;
    try {
      console[NO_CONSOLE[p.level] || 'log'](`[${p.target}] ${JSON.parse(p.message)}`);
    } finally {
      ecoando = false;
    }
  });
  return () => {
    parar();
    invoke('log:detach').catch(() => {});
  };
}
