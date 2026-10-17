// Janela principal: lista as janelas, abre a de configurações e as notas, e
// recebe o que as notas mandam.
import { isBorion, invoke, listen, windowLabel } from '@borion/api';
import * as win from '@borion/api/window';
import { aplicarTema } from './tema.js';

const $ = (id) => document.getElementById(id);

async function listarJanelas() {
  const janelas = await win.getAllWindows();
  const tabela = $('janelas');
  tabela.innerHTML = '';
  for (const j of janelas) {
    const tr = tabela.insertRow();
    tr.insertCell().textContent = j.label + (j.main ? ' (principal)' : '');
    tr.insertCell().textContent = j.title;
    const acoes = tr.insertCell();
    const focar = document.createElement('button');
    focar.textContent = 'setFocus';
    focar.onclick = () => j.setFocus();
    acoes.append(focar);
    if (!j.main) {
      const fechar = document.createElement('button');
      fechar.textContent = 'close';
      fechar.onclick = () => j.close();
      acoes.append(' ', fechar);
    }
  }
}

$('config').onclick = async () => {
  try {
    await win.createWindow('config');  // a definição do app.json
  } catch (e) {
    if (e.code !== 'WINDOW_EXISTS') throw e;
    await win.getWindow('config').setFocus();  // já aberta: só traz para frente
  }
};

let notas = 0;
$('nota').onclick = () => {
  notas++;
  win.createWindow('nota-' + notas, {
    url: '/nota.html',
    title: 'Nota ' + notas,
    width: 380,
    height: 320,
    center: false,
  });
};

$('contar').onclick = async () => {
  $('contagem').textContent = await invoke('contar');
};

if (isBorion()) {
  $('rotulo').textContent = windowLabel();
  aplicarTema();
  win.onCreated(listarJanelas);
  win.onDestroyed(listarJanelas);
  listen('nota', ({ de, texto }) => {
    const li = document.createElement('li');
    li.textContent = `${de}: ${texto}`;
    $('notas').prepend(li);
  });
  listarJanelas();
} else {
  $('janelas').innerHTML = '<tr><td>fora do Borion: abra pelo MultiWindowDemo.exe</td></tr>';
}
