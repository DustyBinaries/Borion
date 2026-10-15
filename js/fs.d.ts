import type { FsOptions, TextFileOptions, WriteOptions, FileInfo, DirEntry, BaseDirectoryName } from './plugins';

export type { FsOptions, TextFileOptions, WriteOptions, FileInfo, DirEntry, BaseDirectoryName } from './plugins';

export declare const BaseDirectory: {
  readonly AppData: 'appData';
  readonly AppLocalData: 'appLocalData';
  readonly Document: 'document';
  readonly Desktop: 'desktop';
  readonly Download: 'download';
  readonly Picture: 'picture';
  readonly Home: 'home';
  readonly Temp: 'temp';
  readonly Exe: 'exe';
};

export declare function readTextFile(path: string, options?: TextFileOptions): Promise<string>;
export declare function writeTextFile(path: string, contents: string, options?: TextFileOptions & WriteOptions): Promise<void>;
export declare function readFile(path: string, options?: FsOptions): Promise<Uint8Array>;
export declare function writeFile(path: string, data: Uint8Array | ArrayBuffer | number[], options?: WriteOptions): Promise<void>;
export declare function exists(path: string, options?: FsOptions): Promise<boolean>;
export declare function stat(path: string, options?: FsOptions): Promise<FileInfo>;
export declare function readDir(path: string, options?: FsOptions): Promise<DirEntry[]>;
export declare function mkdir(path: string, options?: FsOptions & { recursive?: boolean }): Promise<void>;
export declare function remove(path: string, options?: FsOptions & { recursive?: boolean }): Promise<void>;
export declare function rename(from: string, to: string, options?: FsOptions): Promise<void>;
export declare function copyFile(from: string, to: string, options?: FsOptions): Promise<void>;
