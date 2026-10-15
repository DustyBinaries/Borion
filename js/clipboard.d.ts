/** Copia texto (Unicode completo, inclusive emoji). */
export declare function writeText(text: string): Promise<void>;
/** Texto da área de transferência, ou null se não houver texto nela. Rejeita com FORBIDDEN se o app desligou a leitura (AllowRead). */
export declare function readText(): Promise<string | null>;
/** Copia HTML; altText é o texto puro para programas que não entendem HTML. */
export declare function writeHtml(html: string, altText?: string): Promise<void>;
/** Esvazia a área de transferência. */
export declare function clear(): Promise<void>;
