// Exemplo do plugin "tray": ícone, tooltip, menu do ícone, notificações e eventos.
import { isBorion } from '@borion/api';
import * as tray from '@borion/api/tray';

const $ = (id) => document.getElementById(id);

const estado = { visivel: false, naoPerturbe: false, contador: 0 };

function registrar(texto) {
  const li = document.createElement('li');
  li.textContent = new Date().toLocaleTimeString() + '  ' + texto;
  $('log').prepend(li);
}

async function tentar(promessa) {
  try {
    await promessa;
  } catch (e) {
    registrar(`erro [${e.code}] ${e.message}`);
  }
}

function atualizar() {
  $('estado').textContent = estado.visivel ? 'ícone visível' : 'ícone escondido';
  $('contador').textContent = estado.contador;
}

// --- 1. ícone e tooltip --------------------------------------------------------------

async function mostrar() {
  await tray.show({ tooltip: $('tooltip').value });
  estado.visivel = true;
  atualizar();
}

$('mostrar').onclick = () => tentar(mostrar());
$('esconder').onclick = () => tentar(tray.hide().then(() => { estado.visivel = false; atualizar(); }));
$('aplicar-tooltip').onclick = () => tentar(tray.setTooltip($('tooltip').value));

// --- 2. menu do ícone ----------------------------------------------------------------
// O menu só existe enquanto está aberto: um checkbox não muda sozinho, então a
// página guarda o estado e manda o menu de novo.

function montarMenu() {
  return tray.setMenu([
    { id: 'mais', label: '&Contador +1' },
    { id: 'zerar', label: '&Zerar o contador', enabled: estado.contador > 0 },
    { type: 'separator' },
    { id: 'nao-perturbe', label: '&Não perturbe', type: 'checkbox', checked: estado.naoPerturbe },
    { id: 'notificar', label: 'No&tificar agora', enabled: !estado.naoPerturbe },
    { type: 'separator' },
    { id: 'esconder', label: '&Esconder o ícone' },
  ]);
}

tray.onMenu(async (id) => {
  registrar(`tray:menu  ${id}`);
  if (id === 'mais') estado.contador++;
  else if (id === 'zerar') estado.contador = 0;
  else if (id === 'nao-perturbe') estado.naoPerturbe = !estado.naoPerturbe;
  else if (id === 'notificar') await notificar();
  else if (id === 'esconder') { await tray.hide(); estado.visivel = false; }
  atualizar();
  await tentar(montarMenu());
});

// --- 3. notificações -------------------------------------------------------------------

async function notificar() {
  if (estado.naoPerturbe) {
    registrar('não perturbe: notificação suprimida');
    return;
  }
  // notify mostra o ícone se estiver escondido (o Windows exige um ícone para notificar)
  await tray.notify($('titulo').value, $('mensagem').value, { kind: $('tipo').value });
  estado.visivel = true;
  atualizar();
}

$('notificar').onclick = () => tentar(notificar());
$('notificar-depois').onclick = () => {
  registrar('notificação em 5 s...');
  setTimeout(() => tentar(notificar()), 5000);
};

// --- eventos do ícone --------------------------------------------------------------------

tray.onClick(() => registrar('tray:click (com RestoreOnClick, também restaura a janela)'));
tray.onDoubleClick(() => registrar('tray:doubleClick'));
tray.onNotificationClick(() => registrar('tray:balloonClick (clicou na notificação)'));

// --- início ------------------------------------------------------------------------------

atualizar();
if (isBorion()) {
  tentar(montarMenu().then(mostrar));
} else {
  registrar('fora do Borion: abra pelo TrayDemo.exe');
}
