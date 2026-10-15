import type { FsOptions } from './plugins';

/** Abre uma URL (https, http, mailto) ou um arquivo do escopo no programa padrão. */
export declare function open(target: string): Promise<void>;
/** Abre o Explorer com o item selecionado. */
export declare function showInFolder(path: string, options?: FsOptions): Promise<void>;
