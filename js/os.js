// @borion/api/os — informações do sistema (plugin "os" do Delphi: TBorionOsPlugin).
// Como o plugin os do Tauri, mas todas as funções são assíncronas.
import { invoke } from './index.js';

/** Tudo de uma vez: { platform, family, type, arch, processArch, version, build,
 *  displayVersion, name, locale, hostname, eol, exeExtension }. */
export function info() {
  return invoke('os:info');
}

const campo = (nome) => () => info().then((i) => i[nome]);

/** 'windows' */
export const platform = campo('platform');
/** 'windows' */
export const family = campo('family');
/** 'windows' */
export const type = campo('type');
/** Arquitetura do Windows: 'x86_64', 'aarch64', 'x86' ou 'arm'. */
export const arch = campo('arch');
/** Versão real do Windows, ex.: '10.0.22631'. */
export const version = campo('version');
/** Idioma do usuário em BCP 47 ('pt-BR'), ou null. */
export const locale = campo('locale');
/** Nome do computador. */
export const hostname = campo('hostname');
/** '\r\n' */
export const eol = campo('eol');
/** 'exe' */
export const exeExtension = campo('exeExtension');
