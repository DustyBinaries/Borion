// @borion/api/notification — notificações nativas do Windows (plugin "notification"
// do Delphi: TBorionNotificationPlugin). Interface parecida com a do Tauri.
//
//   import { sendNotification, onAction } from '@borion/api/notification';
//   await sendNotification({ title: 'Pedido 42', body: 'Aprovar?', actions: [{ id: 'sim', title: 'Aprovar' }] });
//   onAction(({ id, action }) => ...);
import { invoke, listen } from './index.js';
import { asciiString } from './ascii-json.js';

/** true se o Windows deixa o app mostrar notificações. */
export async function isPermissionGranted() {
  return (await invoke('notification:permission')) === 'granted';
}

/** 'granted' ou 'denied'. O Windows não pergunta ao usuário: só informa o ajuste atual. */
export function requestPermission() {
  return invoke('notification:permission');
}

/**
 * Mostra uma notificação. options: string (o título) ou
 * { title, body?, id?, silent?, actions?: [{ id, title }] }. Devolve o id.
 */
export function sendNotification(options) {
  const o = typeof options === 'string' ? { title: options } : options || {};
  const args = { title: asciiString(o.title ?? '') };
  if (o.body !== undefined && o.body !== null) args.body = asciiString(o.body);
  if (o.id !== undefined) args.id = String(o.id);
  if (o.silent) args.silent = true;
  if (o.actions) args.actions = o.actions.map((a) => ({ id: String(a.id), title: asciiString(a.title) }));
  return invoke('notification:send', args);
}

/** Tira da tela uma notificação mostrada. */
export function hide(id) {
  return invoke('notification:hide', { id: String(id) }).then(() => undefined);
}

/** Clique na notificação ({ id, action: null }) ou num botão ({ id, action }). */
export function onAction(handler) {
  return listen('notification:click', (p) => handler(p));
}

/** Notificação fechada: { id, reason: 'user' | 'hidden' | 'timeout' }. */
export function onDismissed(handler) {
  return listen('notification:dismissed', (p) => handler(p));
}
