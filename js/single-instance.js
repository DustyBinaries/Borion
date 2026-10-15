// @borion/api/single-instance — o app roda uma vez só (plugin "single-instance" do
// Delphi: TBorionSingleInstancePlugin). Abrir de novo traz a janela aberta para
// frente e entrega a ela os argumentos da nova execução.
import { invoke, listen } from './index.js';

// args e cwd vêm como literais JSON só com ASCII (Unicode completo)
const decodificar = (p) => ({ args: p.args.map((a) => JSON.parse(a)), cwd: JSON.parse(p.cwd) });

/** Outra execução do app foi aberta: handler({ args, cwd }). args não inclui o exe. */
export function onSecondInstance(handler) {
  return listen('single-instance:second', (p) => handler(decodificar(p)));
}

/** Os argumentos desta execução ({ args, cwd }), para tratar a primeira abertura do mesmo jeito. */
export async function args() {
  return decodificar(await invoke('single-instance:args'));
}
