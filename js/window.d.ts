export interface WindowState {
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
