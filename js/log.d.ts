export interface LogOptions {
  /** Rótulo da linha no arquivo (padrão 'js') */
  target?: string;
}

export declare function trace(message: string, options?: LogOptions): Promise<void>;
export declare function debug(message: string, options?: LogOptions): Promise<void>;
export declare function info(message: string, options?: LogOptions): Promise<void>;
export declare function warn(message: string, options?: LogOptions): Promise<void>;
export declare function error(message: string, options?: LogOptions): Promise<void>;
/** Caminho do arquivo de log */
export declare function logPath(): Promise<string>;
/** console.* e erros não tratados da página também vão para o arquivo; devolve quem desfaz */
export declare function forwardConsole(): () => void;
/** Mostra no console do DevTools o que for gravado no log; devolve quem desfaz */
export declare function attachConsole(): Promise<() => void>;
