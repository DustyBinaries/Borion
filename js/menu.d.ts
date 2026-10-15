import type { UnlistenFn } from './borion';

export interface MenuItem {
  /** Obrigatório em itens clicáveis; volta no clique */
  id?: string;
  /** Texto; '&' marca a letra de acesso ('&Arquivo') */
  label?: string;
  type?: 'normal' | 'checkbox' | 'separator';
  enabled?: boolean;
  checked?: boolean;
  /** Ex.: 'Ctrl+S', 'Ctrl+Shift+S', 'F5', 'Alt+F4' */
  accelerator?: string;
  /** Submenu */
  items?: MenuItem[];
}

export interface MenuItemUpdate {
  enabled?: boolean;
  checked?: boolean;
  label?: string;
  accelerator?: string;
}

export declare function setMenu(items: MenuItem[]): Promise<void>;
export declare function update(id: string, props: MenuItemUpdate): Promise<void>;
export declare function clear(): Promise<void>;
/** id escolhido, ou null */
export declare function popup(items: MenuItem[], position?: { x?: number; y?: number }): Promise<string | null>;
export declare function onClick(handler: (id: string, checked?: boolean) => void): UnlistenFn;
export declare function onItems(handlers: Record<string, (checked?: boolean) => void>): UnlistenFn;
