// Exemplo do plugin "single-instance": os argumentos desta execução e das
// próximas, que vêm para esta janela em vez de abrir outra.
import { isBorion } from '@borion/api';
import { args, onSecondInstance } from '@borion/api/single-instance';

const $ = (id) => document.getElementById(id);

const formatar = ({ args: lista, cwd }) =>
  `args: ${lista.length ? lista.map((a) => JSON.stringify(a)).join(' ') : '(nenhum)'}\ncwd:  ${cwd}`;

let outras = 0;
onSecondInstance((e) => {
  if (!outras) $('log').innerHTML = '';
  outras++;
  const li = document.createElement('li');
  li.textContent = `${new Date().toLocaleTimeString()}  ${formatar(e)}`;
  $('log').prepend(li);
  document.title = `Borion: single-instance (${outras} outra${outras > 1 ? 's' : ''} execução)`;
});

if (isBorion()) {
  args().then((e) => { $('minha').textContent = formatar(e); });
} else {
  $('minha').textContent = 'fora do Borion: abra pelo SingleInstanceDemo.exe';
}
