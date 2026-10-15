// @borion/api/dialog — diálogos nativos (plugin "dialog" do Delphi: TBorionDialogPlugin).
import { invoke } from './index.js';

/**
 * Abre arquivo(s) ou pasta. Devolve o caminho, uma lista (multiple) ou null se o
 * usuário cancelar. O que o usuário escolhe passa a ser permitido no escopo do fs.
 */
export function open(options = {}) {
  return invoke('dialog:open', options);
}

/** Escolhe onde salvar. Devolve o caminho ou null. */
export function save(options = {}) {
  return invoke('dialog:save', options);
}

/** Mensagem com um botão OK. kind: 'info' | 'warning' | 'error'. */
export function message(text, options = {}) {
  return invoke('dialog:message', { ...normalizar(options), message: String(text) }).then(() => undefined);
}

/** Pergunta OK/Cancelar (ou Sim/Não com buttons: 'yesNo'). Devolve true/false. */
export function confirm(text, options = {}) {
  return invoke('dialog:confirm', { ...normalizar(options), message: String(text) });
}

/** Atalho para confirm com Sim/Não. */
export function ask(text, options = {}) {
  return confirm(text, { ...normalizar(options), buttons: 'yesNo' });
}

// aceita message('texto', 'Título') como atalho para { title }
function normalizar(options) {
  return typeof options === 'string' ? { title: options } : options;
}
