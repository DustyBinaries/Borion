// @borion/api/window — as janelas do app (plugin "window" do Delphi: TBorionWindowPlugin).
// Tamanhos e posições em pixels, da janela inteira (como o width/height do app.json).
//
// As funções soltas (setTitle, setSize...) agem sobre a janela desta página.
// getWindow('config') devolve um objeto com os mesmos métodos para outra janela.
import { invoke, listen, windowLabel } from './index.js';

const ok = () => undefined;

// Os métodos de uma janela. label undefined = a janela que chama.
function methods(label) {
  const withLabel = (args) => (label === undefined ? args : { ...args, label });
  const cmd = (name, args) => invoke('window:' + name, withLabel(args)).then(ok);
  const state = () => invoke('window:state', withLabel());
  return {
    setTitle: (title) => cmd('setTitle', { title: String(title) }),
    minimize: () => cmd('minimize'),
    unminimize: () => cmd('unminimize'),
    maximize: () => cmd('maximize'),
    unmaximize: () => cmd('unmaximize'),
    toggleMaximize: () => cmd('toggleMaximize'),
    show: () => cmd('show'),
    hide: () => cmd('hide'),
    /** Mostra, restaura e traz a janela para frente. */
    setFocus: () => cmd('setFocus'),
    /** Centraliza na área de trabalho do monitor onde a janela está. */
    center: () => cmd('center'),
    setSize: (width, height) => cmd('setSize', { width, height }),
    setPosition: (x, y) => cmd('setPosition', { x, y }),
    /** 0 (ou null) = sem limite. */
    setMinSize: (width, height) => cmd('setMinSize', { width: width || 0, height: height || 0 }),
    setMaxSize: (width, height) => cmd('setMaxSize', { width: width || 0, height: height || 0 }),
    setFullscreen: (fullscreen) => cmd('setFullscreen', { fullscreen: !!fullscreen }),
    setAlwaysOnTop: (alwaysOnTop) => cmd('setAlwaysOnTop', { alwaysOnTop: !!alwaysOnTop }),
    setResizable: (resizable) => cmd('setResizable', { resizable: !!resizable }),
    /** false: sem borda nem barra de título. */
    setDecorations: (decorations) => cmd('setDecorations', { decorations: !!decorations }),
    /** { label, title, x, y, width, height, minimized, maximized, fullscreen, visible, focused, alwaysOnTop, resizable, decorations } */
    state,
    isMinimized: () => state().then((s) => s.minimized),
    isMaximized: () => state().then((s) => s.maximized),
    isFullscreen: () => state().then((s) => s.fullscreen),
    isVisible: () => state().then((s) => s.visible),
    isFocused: () => state().then((s) => s.focused),
    /** Pede para fechar: passa pelo onCloseRequested da janela e pelo OnCloseQuery do Delphi. */
    close: () => cmd('close'),
    /** Fecha sem o onCloseRequested (o OnCloseQuery do Delphi ainda vale). */
    destroy: () => cmd('destroy'),
  };
}

const current = methods(undefined);

export const {
  setTitle, minimize, unminimize, maximize, unmaximize, toggleMaximize, show, hide, setFocus,
  center, setSize, setPosition, setMinSize, setMaxSize, setFullscreen, setAlwaysOnTop,
  setResizable, setDecorations, state, isMinimized, isMaximized, isFullscreen, isVisible,
  isFocused, close, destroy,
} = current;

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

// --- várias janelas -----------------------------------------------------------

function windowObject(label) {
  return Object.freeze({ label, ...methods(label) });
}

/** A janela desta página: { label, setTitle, setSize, ... }. */
export function getCurrent() {
  return windowObject(windowLabel() || 'main');
}

/** Uma janela pelo rótulo (sem verificar se está aberta: os métodos rejeitam com WINDOW_NOT_FOUND). */
export function getWindow(label) {
  return windowObject(String(label));
}

/** As janelas abertas: [{ label, title, visible, main, setTitle, ... }]. */
export async function getAllWindows() {
  const list = await invoke('window:list');
  return list.map((w) => Object.freeze({ ...w, ...methods(w.label) }));
}

/**
 * Abre uma janela: a do app.json com esse rótulo (as opções vencem) ou uma nova.
 * options: { url, title, width, height, minWidth, minHeight, maxWidth, maxHeight,
 * resizable, center, maximized, decorations, alwaysOnTop, visible }.
 * Rejeita com WINDOW_EXISTS se ela já estiver aberta.
 */
export async function createWindow(label, options = {}) {
  await invoke('window:create', { ...options, label: String(label) });
  return getWindow(label);
}

/** Uma janela foi aberta: handler(label). Vale para todas as janelas do app. */
export function onCreated(handler) {
  return listen('window:created', (p) => handler(p.label));
}

/** Uma janela fechou: handler(label). */
export function onDestroyed(handler) {
  return listen('window:destroyed', (p) => handler(p.label));
}

// --- fechamento interceptado ---------------------------------------------------
// Com pelo menos um handler, o Delphi não fecha esta janela sozinho: avisa a
// página (window:close-requested), que confirma o recebimento na hora
// (closeAck) e responde depois dos handlers (closeResolve). Sem a confirmação,
// o Delphi fecha assim mesmo depois de um tempo: uma página travada não prende
// o app.

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
 * Chamado quando o usuário tenta fechar esta janela (X, Alt+F4, app.exit, close()).
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
    return invoke('window:interceptClose', { enabled: false }).then(ok);
  };
}
