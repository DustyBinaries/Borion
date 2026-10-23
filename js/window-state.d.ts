/** Grava agora o estado das janelas abertas */
export declare function saveWindowState(): Promise<void>;
/** Volta a janela da página (ou a do rótulo) ao estado gravado; false se não houver estado dela */
export declare function restoreState(label?: string): Promise<boolean>;
/** Caminho do arquivo do estado */
export declare function filename(): Promise<string>;
