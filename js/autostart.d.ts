/** Liga a inicialização com o Windows */
export declare function enable(): Promise<void>;
export declare function disable(): Promise<void>;
/** Considera o "Desabilitado" do Gerenciador de Tarefas */
export declare function isEnabled(): Promise<boolean>;
/** Esta execução veio do login */
export declare function launchedAtLogin(): Promise<boolean>;
