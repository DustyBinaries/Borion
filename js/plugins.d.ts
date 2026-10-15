// Tipos dos módulos de plugins do @borion/api (dialog, fs, shell).

export interface DialogFilter {
  /** Nome exibido, ex.: 'Texto' */
  name: string;
  /** Extensões sem ponto, ex.: ['txt', 'md']; '*' = todos os arquivos */
  extensions: string[];
}

export interface OpenDialogOptions {
  title?: string;
  /** Permite escolher vários arquivos: o resultado vira uma lista */
  multiple?: boolean;
  /** Escolhe uma pasta em vez de arquivo(s) */
  directory?: boolean;
  filters?: DialogFilter[];
  /** Pasta inicial, ou caminho de arquivo sugerido */
  defaultPath?: string;
}

export interface SaveDialogOptions {
  title?: string;
  filters?: DialogFilter[];
  defaultPath?: string;
}

export interface MessageDialogOptions {
  title?: string;
  kind?: 'info' | 'warning' | 'error';
}

export interface ConfirmDialogOptions extends MessageDialogOptions {
  buttons?: 'okCancel' | 'yesNo';
}

export type BaseDirectoryName =
  | 'appData' | 'appLocalData' | 'document' | 'desktop' | 'download'
  | 'picture' | 'home' | 'temp' | 'exe';

export interface FsOptions {
  /** Caminho relativo a um diretório-base (ver BaseDirectory) */
  baseDir?: BaseDirectoryName;
}

export interface TextFileOptions extends FsOptions {
  /** 'utf8' (padrão) ou 'ansi' */
  encoding?: 'utf8' | 'ansi';
}

export interface WriteOptions extends FsOptions {
  append?: boolean;
}

export interface FileInfo {
  isFile: boolean;
  isDirectory: boolean;
  size: number;
  /** ISO 8601, hora local: 'yyyy-mm-ddThh:nn:ss' */
  modified: string;
  readonly: boolean;
}

export interface DirEntry extends FileInfo {
  name: string;
}
