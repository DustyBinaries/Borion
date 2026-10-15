import type {
  OpenDialogOptions, SaveDialogOptions, MessageDialogOptions, ConfirmDialogOptions,
} from './plugins';

export type { DialogFilter, OpenDialogOptions, SaveDialogOptions, MessageDialogOptions, ConfirmDialogOptions } from './plugins';

/** Caminho escolhido, ou null se cancelado */
export declare function open(options?: OpenDialogOptions & { multiple?: false; directory?: boolean }): Promise<string | null>;
/** Lista de caminhos, ou null se cancelado */
export declare function open(options: OpenDialogOptions & { multiple: true }): Promise<string[] | null>;

export declare function save(options?: SaveDialogOptions): Promise<string | null>;
export declare function message(text: string, options?: MessageDialogOptions | string): Promise<void>;
export declare function confirm(text: string, options?: ConfirmDialogOptions | string): Promise<boolean>;
export declare function ask(text: string, options?: MessageDialogOptions | string): Promise<boolean>;
