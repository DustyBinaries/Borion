// Exemplo do plugin "global-shortcut": atalhos globais registrados pela página.
import { isBorion } from '@borion/api';
import { register, unregister, unregisterAll } from '@borion/api/global-shortcut';

const $ = (id) => document.getElementById(id);
const registrados = new Set();
let vezes = 0;

function pressionado({ shortcut }) {
  if (!vezes) $('log').innerHTML = '';
  vezes++;
  const li = document.createElement('li');
  li.textContent = `${new Date().toLocaleTimeString()}  ${shortcut}`;
  $('log').prepend(li);
  document.title = `Borion: global-shortcut (${vezes})`;  // aparece na barra de tarefas
}

function mostrar() {
  const ul = $('lista');
  ul.innerHTML = '';
  if (!registrados.size) ul.innerHTML = '<li>nenhum</li>';
  for (const atalho of registrados) {
    const li = document.createElement('li');
    li.textContent = atalho + ' ';
    const b = document.createElement('button');
    b.textContent = 'Desregistrar';
    b.onclick = async () => {
      await unregister(atalho);
      registrados.delete(atalho);
      mostrar();
    };
    li.appendChild(b);
    ul.appendChild(li);
  }
}

async function registrar(texto) {
  $('erro').textContent = '';
  try {
    registrados.add(await register(texto, pressionado));  // devolve o atalho normalizado
  } catch (e) {
    $('erro').textContent = `[${e.code}] ${e.message}`;
  }
  mostrar();
}

$('registrar').onclick = () => registrar($('atalho').value);
$('todos').onclick = async () => {
  await unregisterAll();
  registrados.clear();
  mostrar();
};

if (isBorion()) {
  registrar('CmdOrCtrl+Shift+F9');
} else {
  $('erro').textContent = 'fora do Borion: abra pelo GlobalShortcutDemo.exe';
}
