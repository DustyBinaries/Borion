// @borion/api/fs — arquivos e pastas (plugin "fs" do Delphi: TBorionFsPlugin).
// Todo caminho passa pelo escopo configurado no Delphi (TBorionScope): fora dele,
// a Promise rejeita com code = 'FORBIDDEN_PATH'.
import { invoke } from './index.js';
import { bytesParaBase64, base64ParaBytes } from './base64.js';

/** Diretórios-base para caminhos relativos (opção baseDir). */
export const BaseDirectory = Object.freeze({
  AppData: 'appData',
  AppLocalData: 'appLocalData',
  Document: 'document',
  Desktop: 'desktop',
  Download: 'download',
  Picture: 'picture',
  Home: 'home',
  Temp: 'temp',
  Exe: 'exe',
});

const call = (cmd, args) => invoke('fs:' + cmd, args);

/** Lê um arquivo de texto (UTF-8 por padrão; encoding: 'ansi' para legado). */
export function readTextFile(path, options = {}) {
  return call('readTextFile', { ...options, path });
}

/** Grava texto (UTF-8 sem BOM por padrão). append: true acrescenta no fim. */
export function writeTextFile(path, contents, options = {}) {
  return call('writeTextFile', { ...options, path, contents: String(contents) }).then(() => undefined);
}

/** Lê um arquivo binário. */
export async function readFile(path, options = {}) {
  return base64ParaBytes(await call('readFile', { ...options, path }));
}

/** Grava bytes (Uint8Array, ArrayBuffer ou array de números). */
export function writeFile(path, data, options = {}) {
  return call('writeFile', { ...options, path, data: bytesParaBase64(data) }).then(() => undefined);
}

export function exists(path, options = {}) {
  return call('exists', { ...options, path });
}

/** { isFile, isDirectory, size, modified (ISO, hora local), readonly } */
export function stat(path, options = {}) {
  return call('stat', { ...options, path });
}

/** [{ name, isFile, isDirectory, size, modified, readonly }] */
export function readDir(path, options = {}) {
  return call('readDir', { ...options, path });
}

export function mkdir(path, options = {}) {
  return call('mkdir', { ...options, path }).then(() => undefined);
}

/** Apaga arquivo ou pasta (pasta com conteúdo exige recursive: true). */
export function remove(path, options = {}) {
  return call('remove', { ...options, path }).then(() => undefined);
}

export function rename(from, to, options = {}) {
  return call('rename', { ...options, from, to }).then(() => undefined);
}

export function copyFile(from, to, options = {}) {
  return call('copyFile', { ...options, from, to }).then(() => undefined);
}
