import type { UnlistenFn } from './borion';
import type { MenuItem } from './menu';

export declare function show(options?: { tooltip?: string }): Promise<void>;
export declare function hide(): Promise<void>;
export declare function setTooltip(tooltip: string): Promise<void>;
export declare function setMenu(items: MenuItem[] | null): Promise<void>;
export declare function notify(
  title: string,
  message: string,
  options?: { kind?: 'info' | 'warning' | 'error' | 'none' }
): Promise<void>;
export declare function onClick(handler: () => void): UnlistenFn;
export declare function onDoubleClick(handler: () => void): UnlistenFn;
export declare function onMenu(handler: (id: string) => void): UnlistenFn;
export declare function onNotificationClick(handler: () => void): UnlistenFn;
