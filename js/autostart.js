// @borion/api/autostart — iniciar o app com o Windows (plugin "autostart" do
// Delphi: TBorionAutostartPlugin). Interface do autostart do Tauri.
import { invoke } from './index.js';

const ok = () => undefined;

/** Liga a inicialização com o Windows (desfaz também um "Desabilitado" do Gerenciador de Tarefas). */
export function enable() {
  return invoke('autostart:enable').then(ok);
}

export function disable() {
  return invoke('autostart:disable').then(ok);
}

/** true se o app vai iniciar com o Windows (considera o Gerenciador de Tarefas). */
export function isEnabled() {
  return invoke('autostart:isEnabled');
}

/** true se esta execução veio do login (para abrir minimizado na bandeja, por exemplo). */
export function launchedAtLogin() {
  return invoke('autostart:launchedAtLogin');
}
