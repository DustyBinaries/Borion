// Uma nota: criada pela principal com createWindow; manda o texto de volta com emitTo.
import { emitTo, windowLabel } from '@borion/api';
import * as win from '@borion/api/window';
import { aplicarTema } from './tema.js';

const $ = (id) => document.getElementById(id);

aplicarTema();
$('rotulo').textContent = windowLabel();
$('enviar').onclick = () => emitTo('main', 'nota', { de: windowLabel(), texto: $('texto').value });
$('fechar').onclick = () => win.close();
