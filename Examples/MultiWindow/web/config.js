// Janela de configurações (definida no app.json, com "create": false).
import { invoke, emitTo } from '@borion/api';
import * as win from '@borion/api/window';
import { aplicarTema, temaAtual } from './tema.js';

const $ = (id) => document.getElementById(id);

aplicarTema();
for (const radio of document.querySelectorAll('input[name=tema]')) {
  radio.checked = radio.value === temaAtual();
  radio.onchange = () => {
    localStorage.setItem('tema', radio.value);
    emitTo('*', 'tema', radio.value);  // todas as janelas, esta inclusive
  };
}

$('contar').onclick = async () => {
  $('contagem').textContent = await invoke('contar');
};
$('fechar').onclick = () => win.close();
