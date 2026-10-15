// @borion/api/shell — abrir no programa padrão (plugin "shell" do Delphi: TBorionShellPlugin).
// URLs só com esquemas liberados (https, http, mailto por padrão); arquivos só dentro
// do escopo e nunca executáveis.
import { invoke } from './index.js';

/** Abre uma URL no navegador padrão, ou um arquivo/pasta no programa associado. */
export function open(target) {
  return invoke('shell:open', { target: String(target) }).then(() => undefined);
}

/** Abre o Explorer com o arquivo ou pasta selecionado. */
export function showInFolder(path, options = {}) {
  return invoke('shell:showInFolder', { ...options, path }).then(() => undefined);
}
