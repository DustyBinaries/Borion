export interface ShortcutEvent {
  /** Atalho normalizado, ex.: 'Ctrl+Shift+K' */
  shortcut: string;
  state: 'pressed';
}

export type ShortcutHandler = (event: ShortcutEvent) => void;

/** Devolve o atalho normalizado (ou a lista, se recebeu uma lista) */
export declare function register(shortcut: string, handler: ShortcutHandler): Promise<string>;
export declare function register(shortcuts: string[], handler: ShortcutHandler): Promise<string[]>;
export declare function unregister(shortcuts: string | string[]): Promise<void>;
export declare function unregisterAll(): Promise<void>;
export declare function isRegistered(shortcut: string): Promise<boolean>;
