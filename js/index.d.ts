// Tipos do pacote ESM @borion/api.
import type { InvokeOptions, UnlistenFn } from './borion';

export type { Borion, BorionError, InvokeOptions, UnlistenFn } from './borion';

/** Código do erro quando a página não está rodando dentro de um app Borion. */
export declare const NOT_AVAILABLE: 'NOT_AVAILABLE';

/** true quando a ponte do Borion está presente. */
export declare function isBorion(): boolean;

/** Versão da ponte (BORION_VERSION do Delphi), ou null fora do Borion. */
export declare function version(): string | null;

/**
 * Chama um comando Delphi registrado com TBorionIpc.RegisterCommand.
 * Rejeita com BorionError (fora do Borion, code = 'NOT_AVAILABLE').
 */
export declare function invoke<T = unknown>(
  cmd: string,
  args?: Record<string, unknown> | null,
  options?: InvokeOptions
): Promise<T>;

/** Escuta um evento emitido pelo Delphi (Ipc.Emit). Lança fora do Borion. */
export declare function listen<T = unknown>(
  event: string,
  handler: (payload: T, event: string) => void
): UnlistenFn;

/** Como listen, mas só a primeira ocorrência. Lança fora do Borion. */
export declare function once<T = unknown>(
  event: string,
  handler: (payload: T, event: string) => void
): UnlistenFn;

/** Emite um evento para o Delphi (Ipc.Listen). Lança fora do Borion. */
export declare function emit(event: string, payload?: unknown): void;

declare const api: {
  invoke: typeof invoke;
  listen: typeof listen;
  once: typeof once;
  emit: typeof emit;
  isBorion: typeof isBorion;
  version: typeof version;
  NOT_AVAILABLE: typeof NOT_AVAILABLE;
};
export default api;
