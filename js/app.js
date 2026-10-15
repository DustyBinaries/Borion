// @borion/api/app — janela e ciclo de vida do app (plugin "app" do Delphi: TBorionAppPlugin).
import { invoke } from './index.js';

const ok = () => undefined;

/** Fecha a janela principal (passa pelo OnCloseQuery/OnClose do form). */
export function exit() {
  return invoke('app:exit').then(ok);
}

/** Mostra e traz a janela para frente (inclusive se estiver na bandeja). */
export function show() {
  return invoke('app:show').then(ok);
}

export function hide() {
  return invoke('app:hide').then(ok);
}

export function minimize() {
  return invoke('app:minimize').then(ok);
}

/** { name, version, exe, pid } */
export function info() {
  return invoke('app:info');
}
