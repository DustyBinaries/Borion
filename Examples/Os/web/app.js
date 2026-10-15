// Exemplo do plugin "os": informações do sistema.
import { isBorion } from '@borion/api';
import * as os from '@borion/api/os';

const $ = (id) => document.getElementById(id);

function tabela(id, linhas) {
  const t = $(id);
  t.innerHTML = '';
  for (const [chave, valor] of linhas) {
    const tr = t.insertRow();
    tr.insertCell().textContent = chave;
    tr.insertCell().textContent = valor;
  }
}

tabela('navegador', [
  ['navigator.userAgent', navigator.userAgent],
  ['navigator.language', navigator.language],
  ['navigator.platform', navigator.platform],
]);

async function iniciar() {
  const info = await os.info();
  tabela('info', Object.entries(info).map(([k, v]) => [k, JSON.stringify(v)]));

  // as funções avulsas, como no Tauri
  const idioma = (await os.locale()) || navigator.language;
  const agora = new Date();
  $('idioma').textContent =
    `os.locale() = ${idioma}: hoje é ${agora.toLocaleDateString(idioma, { dateStyle: 'full' })}, ` +
    `e 1234567.89 fica ${(1234567.89).toLocaleString(idioma)}.`;
}

if (isBorion()) {
  iniciar().catch((e) => { $('info').innerHTML = `<tr><td>erro [${e.code}] ${e.message}</td></tr>`; });
} else {
  $('info').innerHTML = '<tr><td>fora do Borion: abra pelo OsDemo.exe</td></tr>';
}
