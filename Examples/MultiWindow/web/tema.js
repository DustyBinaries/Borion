// O tema vale para todas as janelas: o localStorage (a mesma origem) dá o
// inicial, e o evento "tema", mandado com emitTo('*', ...), muda todas na hora.
import { listen } from '@borion/api';

export function temaAtual() {
  return localStorage.getItem('tema') || 'claro';
}

export function aplicarTema() {
  const aplicar = (tema) => document.body.classList.toggle('escuro', tema === 'escuro');
  aplicar(temaAtual());
  listen('tema', (tema) => aplicar(tema));
}
