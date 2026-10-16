export interface AppInfo {
  name: string;
  /** "version" do app.json; sem ela, o FileVersion do exe ('' se não houver) */
  version: string;
  /** "identifier" do app.json ('' se não houver) */
  identifier: string;
  exe: string;
  pid: number;
}

export declare function exit(): Promise<void>;
export declare function show(): Promise<void>;
export declare function hide(): Promise<void>;
export declare function minimize(): Promise<void>;
export declare function info(): Promise<AppInfo>;
