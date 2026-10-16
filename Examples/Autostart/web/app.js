// Exemplo do plugin "autostart": iniciar o app com o Windows.
import { isBorion } from '@borion/api';
import { enable, disable, isEnabled, launchedAtLogin } from '@borion/api/autostart';

const $ = (id) => document.getElementById(id);

async function conferir() {
  $('ligado').checked = await isEnabled();
}

$('ligado').onchange = async () => {
  try {
    await ($('ligado').checked ? enable() : disable());
  } finally {
    await conferir();
  }
};
$('conferir').onclick = conferir;

if (isBorion()) {
  conferir();
  launchedAtLogin().then((login) => {
    $('login').textContent = login
      ? 'Este app foi aberto pelo login do Windows.'
      : 'Este app foi aberto por você (não pelo login).';
  });
} else {
  $('login').textContent = 'fora do Borion: abra pelo AutostartDemo.exe';
}
