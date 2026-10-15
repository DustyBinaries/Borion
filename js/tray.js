// @borion/api/tray — ícone na bandeja do Windows (plugin "tray" do Delphi: TBorionTrayPlugin).
import { invoke, listen } from './index.js';

const ok = () => undefined;

/** Mostra o ícone (o ícone em si é definido no Delphi). */
export function show(options = {}) {
  return invoke('tray:show', options).then(ok);
}

export function hide() {
  return invoke('tray:hide').then(ok);
}

export function setTooltip(tooltip) {
  return invoke('tray:setTooltip', { tooltip: String(tooltip) }).then(ok);
}

/** Menu do clique direito, no mesmo formato do @borion/api/menu. null remove. */
export function setMenu(items) {
  return invoke('tray:setMenu', { items }).then(ok);
}

/** Notificação (balão / toast). kind: 'info' | 'warning' | 'error' | 'none'. */
export function notify(title, message, options = {}) {
  return invoke('tray:notify', { ...options, title: String(title || ''), message: String(message) }).then(ok);
}

/** Clique simples no ícone. */
export function onClick(handler) {
  return listen('tray:click', () => handler());
}

export function onDoubleClick(handler) {
  return listen('tray:doubleClick', () => handler());
}

/** Item escolhido no menu do ícone: handler(id). */
export function onMenu(handler) {
  return listen('tray:menu', (p) => handler(p.id));
}

/** Clique na notificação. */
export function onNotificationClick(handler) {
  return listen('tray:balloonClick', () => handler());
}
