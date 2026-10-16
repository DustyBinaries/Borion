// @borion/api/deep-link — links meuapp://... abrem o app (plugin "deep-link" do
// Delphi: TBorionDeepLinkPlugin). Interface do deep-link do Tauri.
//
// ATENÇÃO: qualquer site pode abrir um link do seu esquema: trate a URL como
// entrada não confiável (valide antes de agir).
import { invoke, listen } from './index.js';

// as URLs vêm como literais JSON só com ASCII (Unicode completo)
const decodificar = (lista) => lista.map((u) => JSON.parse(u));

/** URLs que abriram esta execução do app, ou null se ele não foi aberto por um link. */
export async function getCurrent() {
  const urls = decodificar(await invoke('deep-link:getCurrent'));
  return urls.length ? urls : null;
}

/** Links abertos com o app já rodando (precisa do plugin single-instance): handler(urls). */
export function onOpenUrl(handler) {
  return listen('deep-link:open', (p) => handler(decodificar(p.urls)));
}

/** Só esquemas declarados no Delphi (TBorionDeepLinkPlugin.Create). */
export function register(scheme) {
  return invoke('deep-link:register', { scheme: String(scheme) }).then(() => undefined);
}

/** Só apaga o registro se ele apontar para este app. */
export function unregister(scheme) {
  return invoke('deep-link:unregister', { scheme: String(scheme) }).then(() => undefined);
}

/** true se o esquema está registrado para este app. */
export function isRegistered(scheme) {
  return invoke('deep-link:isRegistered', { scheme: String(scheme) });
}
