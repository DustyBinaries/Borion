// Exemplo de modo kiosk. O app.json já abriu a janela em tela cheia, sem borda, por cima
// de tudo e sem DevTools; aqui a página fecha o que sobra: o fechamento (X, Alt+F4), o menu
// de contexto e os atalhos do navegador. A saída é escondida: cinco toques no canto superior
// esquerdo e o PIN.
import { isBorion } from '@borion/api';
import * as win from '@borion/api/window';

const PIN = '1234';        // de exemplo: um app real confere num comando Delphi, não na página
const TOQUES = 5;          // toques no canto para abrir o PIN
const JANELA_MS = 3000;    // os toques precisam vir em sequência
const CURSOR_MS = 3000;    // sem mexer o mouse, o cursor some

const $ = (id) => document.getElementById(id);

// --- relógio ---------------------------------------------------------------------
function relogio() {
  const agora = new Date();
  $('hora').textContent = agora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  $('data').textContent = agora.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
}
relogio();
setInterval(relogio, 1000);

// --- o que o navegador faria ---------------------------------------------------------
document.addEventListener('contextmenu', (e) => e.preventDefault());
document.addEventListener('dragstart', (e) => e.preventDefault());
// F5/Ctrl+R recarregam, Ctrl+P imprime, Ctrl+/- dão zoom, F11 e F12 não valem
document.addEventListener('keydown', (e) => {
  const bloqueada = /^F(5|11|12)$/.test(e.key) ||
    (e.ctrlKey && /^[rpsuw+=\-0]$/i.test(e.key));
  if (bloqueada) e.preventDefault();
});
document.addEventListener('wheel', (e) => { if (e.ctrlKey) e.preventDefault(); }, { passive: false });

// --- cursor ----------------------------------------------------------------------
let timerCursor;
function mexeu() {
  document.body.classList.remove('parado');
  clearTimeout(timerCursor);
  timerCursor = setTimeout(() => document.body.classList.add('parado'), CURSOR_MS);
}
document.addEventListener('mousemove', mexeu);
mexeu();

// --- o app de verdade seria aqui: o botão só mostra que a página responde ------------------
$('comecar').onclick = () => {
  $('aviso').textContent = 'Toque registrado. Aqui começaria o fluxo do quiosque.';
  setTimeout(() => { $('aviso').textContent = ''; }, 2500);
};

// --- a saída escondida -------------------------------------------------------------
let toques = 0;
let timerToques;
$('canto').onclick = () => {
  toques += 1;
  $('contagem').textContent = String(toques);
  clearTimeout(timerToques);
  timerToques = setTimeout(() => { toques = 0; $('contagem').textContent = ''; }, JANELA_MS);
  if (toques >= TOQUES) {
    toques = 0;
    $('contagem').textContent = '';
    abrirPin();
  }
};

function abrirPin() {
  $('senha').value = '';
  $('erro').hidden = true;
  $('pin').showModal();
  $('senha').focus();
}
$('cancelar').onclick = () => $('pin').close();
$('form-pin').onsubmit = async (e) => {
  e.preventDefault();
  if ($('senha').value !== PIN) {
    $('erro').hidden = false;
    $('senha').value = '';
    return;
  }
  $('pin').close();
  // destroy() fecha sem passar pelo onCloseRequested, que está barrando tudo
  if (isBorion()) await win.destroy();
};

// --- fechamento ----------------------------------------------------------------------
if (isBorion()) {
  // o X, o Alt+F4 e o app.exit() viram este evento; preventDefault mantém a janela
  win.onCloseRequested((event) => {
    event.preventDefault();
    $('aviso').textContent = 'Este aplicativo não pode ser fechado.';
    setTimeout(() => { $('aviso').textContent = ''; }, 2500);
  });
} else {
  $('aviso').textContent = 'fora do Borion: abra pelo KioskDemo.exe';
}
