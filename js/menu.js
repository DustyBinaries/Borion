// @borion/api/menu — barra de menu da janela e menus de contexto nativos
// (plugin "menu" do Delphi: TBorionMenuPlugin).
import { invoke, listen } from './index.js';

/**
 * Monta a barra de menu da janela. Os atalhos (accelerator: 'Ctrl+S') funcionam
 * mesmo com o foco na página, e a página não recebe a tecla.
 * Lista vazia remove a barra.
 */
export function setMenu(items) {
  return invoke('menu:setMenu', { items }).then(() => undefined);
}

/** Altera um item da barra: { enabled, checked, label, accelerator }. */
export function update(id, props) {
  return invoke('menu:update', { ...props, id }).then(() => undefined);
}

/** Remove a barra de menu. */
export function clear() {
  return invoke('menu:clear').then(() => undefined);
}

/**
 * Abre um menu de contexto nativo (no cursor, ou em x/y da página) e devolve o id
 * escolhido, ou null se o usuário fechar sem escolher.
 */
export function popup(items, position = {}) {
  return invoke('menu:popup', { ...position, items });
}

/**
 * Clique num item da barra (ou o atalho dele). handler(id, checked?).
 * Devolve a função para parar de escutar.
 */
export function onClick(handler) {
  return listen('menu:click', (p) => handler(p.id, p.checked));
}

/** Atalho: um handler por id. Devolve a função para parar de escutar. */
export function onItems(handlers) {
  return onClick((id, checked) => {
    if (Object.prototype.hasOwnProperty.call(handlers, id)) handlers[id](checked);
  });
}
