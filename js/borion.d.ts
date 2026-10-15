// Borion — Native Application Engine
// Tipos da ponte injetada pelo TBorionIpc em todo documento (window.borion).
// Copie para o projeto do frontend (ex.: src/borion.d.ts) para ter autocomplete.

export interface BorionError extends Error {
  /** Código do erro: o Code do EBorionError, a classe da exceção Delphi,
   *  ou UNKNOWN_COMMAND / FORBIDDEN_ORIGIN / TIMEOUT
   *  (e NOT_AVAILABLE no pacote @borion/api, fora de um app Borion). */
  code: string;
  /** Nome do comando que falhou. */
  command?: string;
}

export interface InvokeOptions {
  /** Rejeita com code = 'TIMEOUT' se o Delphi não responder a tempo (ms). */
  timeout?: number;
}

export type UnlistenFn = () => void;

export interface Borion {
  /** Chama um comando registrado com Ipc.RegisterCommand. Rejeita com BorionError. */
  invoke<T = unknown>(cmd: string, args?: Record<string, unknown>, options?: InvokeOptions): Promise<T>;
  /** Escuta um evento emitido pelo Delphi (Ipc.Emit). Devolve a função para parar. */
  listen<T = unknown>(event: string, handler: (payload: T, event: string) => void): UnlistenFn;
  /** Como listen, mas só a primeira ocorrência. */
  once<T = unknown>(event: string, handler: (payload: T, event: string) => void): UnlistenFn;
  /** Emite um evento para o Delphi (Ipc.Listen). */
  emit(event: string, payload?: unknown): void;
  /** Versão do Borion (BORION_VERSION). */
  readonly version: string;
}

declare global {
  interface Window {
    borion: Borion;
    __BORION__: Borion;
  }
  const borion: Borion;
}
