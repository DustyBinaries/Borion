// @borion/api/window-state — lembrar o tamanho e a posição das janelas (plugin
// "window-state" do Delphi: TBorionWindowStatePlugin). Interface do window-state do Tauri.
// O plugin já restaura cada janela ao abrir e grava ao fechar; estas funções são para
// gravar ou restaurar fora dessas horas.
import { invoke } from './index.js';

const ok = () => undefined;

/** Grava agora o estado das janelas abertas. */
export function saveWindowState() {
  return invoke('window-state:save').then(ok);
}

/** Volta a janela da página (ou a do rótulo) ao estado gravado. false se não houver estado dela. */
export function restoreState(label) {
  return invoke('window-state:restore', label === undefined ? {} : { label });
}

/** Caminho do arquivo do estado (%APPDATA%\<app>\.window-state.json). */
export function filename() {
  return invoke('window-state:filename');
}
