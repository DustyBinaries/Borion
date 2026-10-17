// @borion/api/window — a janela do app (plugin "window" do Delphi: TBorionWindowPlugin).
// Tamanhos e posições em pixels, da janela inteira (como o width/height do app.json).
import { invoke, listen } from './index.js';

const ok = () => undefined;
const cmd = (name, args) => invoke('window:' + name, args).then(ok);

export function setTitle(title) {
  return cmd('setTitle', { title: String(title) });
}

export const minimize = () => cmd('minimize');
export const unminimize = () => cmd('unminimize');
export const maximize = () => cmd('maximize');
export const unmaximize = () => cmd('unmaximize');
export const toggleMaximize = () => cmd('toggleMaximize');
export const show = () => cmd('show');
export const hide = () => cmd('hide');
/** Mostra, restaura e traz a janela para frente. */
export const setFocus = () => cmd('setFocus');
/** Centraliza na área de trabalho do monitor onde a janela está. */
export const center = () => cmd('center');

export function setSize(width, height) {
  return cmd('setSize', { width, height });
}

export function setPosition(x, y) {
  return cmd('setPosition', { x, y });
}

/** 0 (ou null) = sem limite. */
export function setMinSize(width, height) {
  return cmd('setMinSize', { width: width || 0, height: height || 0 });
}

export function setMaxSize(width, height) {
  return cmd('setMaxSize', { width: width || 0, height: height || 0 });
}

export function setFullscreen(fullscreen) {
  return cmd('setFullscreen', { fullscreen: !!fullscreen });
}

export function setAlwaysOnTop(alwaysOnTop) {
  return cmd('setAlwaysOnTop', { alwaysOnTop: !!alwaysOnTop });
}

export function setResizable(resizable) {
  return cmd('setResizable', { resizable: !!resizable });
}

/** false: sem borda nem barra de título. */
export function setDecorations(decorations) {
  return cmd('setDecorations', { decorations: !!decorations });
}

/** { title, x, y, width, height, minimized, maximized, fullscreen, visible, focused, alwaysOnTop, resizable, decorations } */
export function state() {
  return invoke('window:state');
}

export const isMinimized = () => state().then((s) => s.minimized);
export const isMaximized = () => state().then((s) => s.maximized);
export const isFullscreen = () => state().then((s) => s.fullscreen);
export const isVisible = () => state().then((s) => s.visible);
export const isFocused = () => state().then((s) => s.focused);

/** Pede para fechar: passa pelo onCloseRequested e pelo OnCloseQuery do Delphi. */
export const close = () => cmd('close');
/** Fecha sem o onCloseRequested (o OnCloseQuery do Delphi ainda vale). */
export const destroy = () => cmd('destroy');

/** handler({ width, height, minimized, maximized }) */
export function onResized(handler) {
  return listen('window:resized', (p) => handler(p));
}

/** handler({ x, y }) */
export function onMoved(handler) {
  return listen('window:moved', (p) => handler(p));
}

/** handler(focused) */
export function onFocusChanged(handler) {
  return listen('window:focus-changed', (p) => handler(p.focused));
}

// --- fechamento interceptado ---------------------------------------------------
// Com pelo menos um handler, o Delphi não fecha a janela sozinho: avisa a página
// (window:close-requested), que confirma o recebimento na hora (closeAck) e
// responde depois dos handlers (closeResolve). Sem a confirmação, o Delphi fecha
// assim mesmo depois de um tempo: uma página travada não prende o app.

const closeHandlers = [];
let stopListening = null;

async function closeRequested(payload) {
  const id = payload && payload.id;
  invoke('window:closeAck', { id }).catch(() => {});
  const event = {
    id,
    defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true; },
  };
  let close = true;
  try {
    for (const handler of closeHandlers.slice()) await handler(event);
    close = !event.defaultPrevented;
  } catch (e) {
    // um handler com erro não pode prender a janela aberta
    console.error('onCloseRequested:', e);
  }
  await invoke('window:closeResolve', { id, close });
}

/**
 * Chamado quando o usuário tenta fechar a janela (X, Alt+F4, app.exit, close()).
 * event.preventDefault() mantém a janela aberta; o handler pode ser async (um
 * diálogo "deseja salvar?"). Devolve uma Promise com a função para parar.
 */
export async function onCloseRequested(handler) {
  closeHandlers.push(handler);
  if (closeHandlers.length === 1) {
    stopListening = listen('window:close-requested', closeRequested);
    await invoke('window:interceptClose', { enabled: true });
  }
  let removed = false;
  return () => {
    if (removed) return Promise.resolve();
    removed = true;
    const i = closeHandlers.indexOf(handler);
    if (i >= 0) closeHandlers.splice(i, 1);
    if (closeHandlers.length > 0) return Promise.resolve();
    stopListening();
    stopListening = null;
    return cmd('interceptClose', { enabled: false });
  };
}
