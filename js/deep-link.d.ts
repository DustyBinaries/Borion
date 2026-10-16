import type { UnlistenFn } from './borion';

/** URLs que abriram esta execução, ou null */
export declare function getCurrent(): Promise<string[] | null>;
/** Links abertos com o app já rodando (precisa do plugin single-instance) */
export declare function onOpenUrl(handler: (urls: string[]) => void): UnlistenFn;
/** Só esquemas declarados no Delphi; rejeita com FORBIDDEN_SCHEME */
export declare function register(scheme: string): Promise<void>;
export declare function unregister(scheme: string): Promise<void>;
export declare function isRegistered(scheme: string): Promise<boolean>;
