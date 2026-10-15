export interface OsInfo {
  platform: 'windows';
  family: 'windows';
  type: 'windows';
  /** Arquitetura do Windows */
  arch: 'x86_64' | 'aarch64' | 'x86' | 'arm' | 'unknown';
  /** Arquitetura do processo: o Delphi 7 só gera 32 bits */
  processArch: 'x86';
  /** Versão real, ex.: '10.0.22631' */
  version: string;
  build: number;
  /** '23H2' ('' em versões antigas) */
  displayVersion: string;
  /** 'Windows 11 Pro' */
  name: string;
  /** BCP 47, ex.: 'pt-BR' */
  locale: string | null;
  hostname: string;
  eol: '\r\n';
  exeExtension: 'exe';
}

export declare function info(): Promise<OsInfo>;
export declare function platform(): Promise<OsInfo['platform']>;
export declare function family(): Promise<OsInfo['family']>;
export declare function type(): Promise<OsInfo['type']>;
export declare function arch(): Promise<OsInfo['arch']>;
export declare function version(): Promise<string>;
export declare function locale(): Promise<string | null>;
export declare function hostname(): Promise<string>;
export declare function eol(): Promise<'\r\n'>;
export declare function exeExtension(): Promise<'exe'>;
