import type { UnlistenFn } from './borion';

export interface InstanceArgs {
  /** Argumentos da linha de comando, sem o exe */
  args: string[];
  /** Pasta atual da execução */
  cwd: string;
}

export declare function onSecondInstance(handler: (e: InstanceArgs) => void): UnlistenFn;
export declare function args(): Promise<InstanceArgs>;
