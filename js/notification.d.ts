import type { UnlistenFn } from './borion';

export interface NotificationAction {
  /** Letras, números, '.', '_', ':' e '-' */
  id: string;
  title: string;
}

export interface NotificationOptions {
  title: string;
  body?: string;
  /** Letras, números, '.', '_', ':' e '-'; o mesmo id substitui a notificação anterior */
  id?: string;
  /** Sem som */
  silent?: boolean;
  /** Botões (até 5) */
  actions?: NotificationAction[];
}

export declare function isPermissionGranted(): Promise<boolean>;
/** O Windows não pergunta: só informa o ajuste atual */
export declare function requestPermission(): Promise<'granted' | 'denied'>;
/** Devolve o id da notificação */
export declare function sendNotification(options: NotificationOptions | string): Promise<string>;
export declare function hide(id: string): Promise<void>;
/** action: null no clique na notificação, ou o id do botão */
export declare function onAction(handler: (e: { id: string; action: string | null }) => void): UnlistenFn;
export declare function onDismissed(handler: (e: { id: string; reason: 'user' | 'hidden' | 'timeout' }) => void): UnlistenFn;
