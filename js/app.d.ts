export interface AppInfo {
  name: string;
  /** FileVersion do recurso de versão do exe ('' se não houver) */
  version: string;
  exe: string;
  pid: number;
}

export declare function exit(): Promise<void>;
export declare function show(): Promise<void>;
export declare function hide(): Promise<void>;
export declare function minimize(): Promise<void>;
export declare function info(): Promise<AppInfo>;
