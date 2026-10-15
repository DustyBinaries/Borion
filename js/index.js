// @borion/api — API ESM do Borion — Native Application Engine.
//
// Camada fina sobre a ponte que o TBorionIpc injeta em todo documento
// (window.__BORION__). Serve para apps com bundler (Vite, Rollup, esbuild...):
//
//   import { invoke, listen, emit } from '@borion/api';
//   const soma = await invoke('somar', { a: 20, b: 22 });
//
// A ponte é procurada a cada chamada (não na importação), então o módulo pode
// ser importado em qualquer ordem. Fora de um app Borion (ex.: a página aberta
// num navegador comum), invoke rejeita e listen/once/emit lançam um erro com
// code = 'NOT_AVAILABLE'; use isBorion() para tratar esse caso.

/** Código do erro quando a página não está rodando dentro de um app Borion. */
export const NOT_AVAILABLE = 'NOT_AVAILABLE';

function bridge() {
  return typeof globalThis !== 'undefined' ? globalThis.__BORION__ : undefined;
}

function notAvailable(what) {
  const e = new Error(
    'Borion indisponível: a página não está rodando dentro de um app Borion (' + what + ')'
  );
  e.code = NOT_AVAILABLE;
  return e;
}

function bridgeOrThrow(what) {
  const b = bridge();
  if (!b) throw notAvailable(what);
  return b;
}

/** true quando a ponte do Borion está presente. */
export function isBorion() {
  return !!bridge();
}

/** Versão da ponte (BORION_VERSION do Delphi), ou null fora do Borion. */
export function version() {
  const b = bridge();
  return b ? b.version : null;
}

/**
 * Chama um comando Delphi registrado com TBorionIpc.RegisterCommand.
 * Rejeita com um Error que tem `code` (e `command`).
 */
export function invoke(cmd, args, options) {
  const b = bridge();
  if (!b) {
    const e = notAvailable('invoke "' + cmd + '"');
    e.command = cmd;
    return Promise.reject(e);
  }
  return b.invoke(cmd, args, options);
}

/** Escuta um evento emitido pelo Delphi (Ipc.Emit). Devolve a função para parar. */
export function listen(event, handler) {
  return bridgeOrThrow('listen "' + event + '"').listen(event, handler);
}

/** Como listen, mas só a primeira ocorrência. */
export function once(event, handler) {
  return bridgeOrThrow('once "' + event + '"').once(event, handler);
}

/** Emite um evento para o Delphi (Ipc.Listen). */
export function emit(event, payload) {
  bridgeOrThrow('emit "' + event + '"').emit(event, payload);
}

export default { invoke, listen, once, emit, isBorion, version, NOT_AVAILABLE };
