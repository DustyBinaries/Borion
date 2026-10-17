export interface WindowState {
  label: string;
  title: string;
  x: number;
  y: number;
  /** Tamanho da janela inteira, em pixels */
  width: number;
  height: number;
  minimized: boolean;
  maximized: boolean;
  fullscreen: boolean;
  visible: boolean;
  focused: boolean;
  alwaysOnTop: boolean;
  resizable: boolean;
  decorations: boolean;
}

export interface WindowSize {
  width: number;
  height: number;
  minimized: boolean;
  maximized: boolean;
}

export interface WindowPosition {
  x: number;
  y: number;
}

export type ResizeDirection =
  | 'North' | 'South' | 'East' | 'West'
  | 'NorthEast' | 'NorthWest' | 'SouthEast' | 'SouthWest';

export interface CloseRequestedEvent {
  readonly id: number;
  readonly defaultPrevented: boolean;
  /** Mantém a janela aberta */
  preventDefault(): void;
}

export declare function setTitle(title: string): Promise<void>;
export declare function minimize(): Promise<void>;
export declare function unminimize(): Promise<void>;
export declare function maximize(): Promise<void>;
export declare function unmaximize(): Promise<void>;
export declare function toggleMaximize(): Promise<void>;
export declare function show(): Promise<void>;
export declare function hide(): Promise<void>;
export declare function setFocus(): Promise<void>;
export declare function center(): Promise<void>;
export declare function setSize(width: number, height: number): Promise<void>;
export declare function setPosition(x: number, y: number): Promise<void>;
/** 0 ou null = sem limite */
export declare function setMinSize(width: number | null, height: number | null): Promise<void>;
export declare function setMaxSize(width: number | null, height: number | null): Promise<void>;
export declare function setFullscreen(fullscreen: boolean): Promise<void>;
export declare function setAlwaysOnTop(alwaysOnTop: boolean): Promise<void>;
export declare function setResizable(resizable: boolean): Promise<void>;
export declare function setDecorations(decorations: boolean): Promise<void>;
/**
 * Arrasta a janela com o mouse; chame num mousedown. Para a barra de título em HTML,
 * basta o atributo data-borion-drag-region.
 */
export declare function startDragging(): Promise<void>;
/** Redimensiona pela borda; chame num mousedown. Sem decorations, a borda da página já faz isso. */
export declare function startResizeDragging(direction: ResizeDirection): Promise<void>;
export declare function state(): Promise<WindowState>;
export declare function isMinimized(): Promise<boolean>;
export declare function isMaximized(): Promise<boolean>;
export declare function isFullscreen(): Promise<boolean>;
export declare function isVisible(): Promise<boolean>;
export declare function isFocused(): Promise<boolean>;
/** Pede para fechar: passa pelo onCloseRequested e pelo OnCloseQuery do Delphi */
export declare function close(): Promise<void>;
/** Fecha sem o onCloseRequested (o OnCloseQuery do Delphi ainda vale) */
export declare function destroy(): Promise<void>;
export declare function onResized(handler: (size: WindowSize) => void): () => void;
export declare function onMoved(handler: (position: WindowPosition) => void): () => void;
export declare function onFocusChanged(handler: (focused: boolean) => void): () => void;
/**
 * Chamado quando o usuário tenta fechar a janela. event.preventDefault() a mantém
 * aberta; o handler pode ser async. Resolve com a função para parar.
 */
export declare function onCloseRequested(
  handler: (event: CloseRequestedEvent) => void | Promise<void>
): Promise<() => Promise<void>>;

/** Os métodos de uma janela (getWindow / getCurrent / getAllWindows) */
export interface BorionWindow {
  readonly label: string;
  setTitle(title: string): Promise<void>;
  minimize(): Promise<void>;
  unminimize(): Promise<void>;
  maximize(): Promise<void>;
  unmaximize(): Promise<void>;
  toggleMaximize(): Promise<void>;
  show(): Promise<void>;
  hide(): Promise<void>;
  setFocus(): Promise<void>;
  center(): Promise<void>;
  setSize(width: number, height: number): Promise<void>;
  setPosition(x: number, y: number): Promise<void>;
  setMinSize(width: number | null, height: number | null): Promise<void>;
  setMaxSize(width: number | null, height: number | null): Promise<void>;
  setFullscreen(fullscreen: boolean): Promise<void>;
  setAlwaysOnTop(alwaysOnTop: boolean): Promise<void>;
  setResizable(resizable: boolean): Promise<void>;
  setDecorations(decorations: boolean): Promise<void>;
  startDragging(): Promise<void>;
  startResizeDragging(direction: ResizeDirection): Promise<void>;
  state(): Promise<WindowState>;
  isMinimized(): Promise<boolean>;
  isMaximized(): Promise<boolean>;
  isFullscreen(): Promise<boolean>;
  isVisible(): Promise<boolean>;
  isFocused(): Promise<boolean>;
  close(): Promise<void>;
  destroy(): Promise<void>;
}

export interface WindowInfo extends BorionWindow {
  readonly title: string;
  readonly visible: boolean;
  /** A janela principal: fechá-la fecha o app */
  readonly main: boolean;
}

export interface WindowOptions {
  /** Caminho do app, começando com '/' (ex.: '/config.html') */
  url?: string;
  title?: string;
  width?: number;
  height?: number;
  minWidth?: number;
  minHeight?: number;
  maxWidth?: number;
  maxHeight?: number;
  resizable?: boolean;
  center?: boolean;
  maximized?: boolean;
  decorations?: boolean;
  alwaysOnTop?: boolean;
  visible?: boolean;
}

/** A janela desta página */
export declare function getCurrent(): BorionWindow;
/** Uma janela pelo rótulo (os métodos rejeitam com WINDOW_NOT_FOUND se ela não estiver aberta) */
export declare function getWindow(label: string): BorionWindow;
/** As janelas abertas */
export declare function getAllWindows(): Promise<WindowInfo[]>;
/** Abre a janela do app.json com esse rótulo (as opções vencem) ou uma nova. Rejeita com WINDOW_EXISTS se já estiver aberta */
export declare function createWindow(label: string, options?: WindowOptions): Promise<BorionWindow>;
/** Uma janela foi aberta (em qualquer janela do app) */
export declare function onCreated(handler: (label: string) => void): () => void;
/** Uma janela fechou */
export declare function onDestroyed(handler: (label: string) => void): () => void;
