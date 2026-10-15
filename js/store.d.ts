import type { UnlistenFn } from './borion';

export declare class Store {
  /** Prefira load(name), que já abre o arquivo e valida o nome. */
  constructor(name: string);
  readonly name: string;
  /** Nome do arquivo, normalizado ('Settings' -> 'settings.json') */
  readonly file: string;
  /** Valor da chave, ou undefined se ela não existir */
  get<T = unknown>(key: string): Promise<T | undefined>;
  /** value: qualquer coisa que o JSON.stringify aceite */
  set(key: string, value: unknown): Promise<void>;
  has(key: string): Promise<boolean>;
  /** true se a chave existia */
  delete(key: string): Promise<boolean>;
  clear(): Promise<void>;
  /** Na ordem em que as chaves foram criadas */
  entries<T = unknown>(): Promise<Array<[key: string, value: T]>>;
  keys(): Promise<string[]>;
  values<T = unknown>(): Promise<T[]>;
  length(): Promise<number>;
  /** Grava agora (só é preciso com o AutoSave desligado no Delphi) */
  save(): Promise<void>;
  /** Descarta o que não foi gravado e relê o arquivo */
  reload(): Promise<void>;
  /** Qualquer alteração; value undefined = chave apagada */
  onChange<T = unknown>(handler: (key: string, value: T | undefined) => void): UnlistenFn;
  onKeyChange<T = unknown>(key: string, handler: (value: T | undefined) => void): UnlistenFn;
}

/** Abre o store (lê o arquivo, se existir). Nome: letras, números, '.', '_' e '-'; '.json' é opcional. */
export declare function load(name: string): Promise<Store>;
