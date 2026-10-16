// @borion/api/global-shortcut — atalhos de teclado globais, que funcionam com o
// app em segundo plano (plugin "global-shortcut" do Delphi:
// TBorionGlobalShortcutPlugin). Interface do global-shortcut do Tauri.
//
//   await register('CmdOrCtrl+Shift+Space', (e) => app.show());
import { invoke, listen } from './index.js';

const handlers = new Map();  // atalho normalizado -> handler
let parar = null;

function ouvir() {
  if (parar) return;
  parar = listen('global-shortcut:pressed', (p) => {
    const h = handlers.get(p.shortcut);
    if (h) h({ shortcut: p.shortcut, state: p.state });
  });
}

const lista = (x) => (Array.isArray(x) ? x : [x]);

/**
 * Registra um ou mais atalhos ('Ctrl+Shift+K', 'CmdOrCtrl+Alt+F5', 'MediaPlayPause').
 * Registrar de novo um atalho deste app só troca o handler. Devolve o(s) atalho(s)
 * normalizado(s).
 */
export async function register(shortcuts, handler) {
  ouvir();
  const feitos = [];
  for (const s of lista(shortcuts)) {
    const normalizado = await invoke('global-shortcut:register', { shortcut: String(s) });
    handlers.set(normalizado, handler);
    feitos.push(normalizado);
  }
  return Array.isArray(shortcuts) ? feitos : feitos[0];
}

export async function unregister(shortcuts) {
  for (const s of lista(shortcuts)) {
    handlers.delete(await invoke('global-shortcut:unregister', { shortcut: String(s) }));
  }
}

export async function unregisterAll() {
  await invoke('global-shortcut:unregisterAll');
  handlers.clear();
}

/** true se o atalho está registrado por este app. */
export function isRegistered(shortcut) {
  return invoke('global-shortcut:isRegistered', { shortcut: String(shortcut) });
}
