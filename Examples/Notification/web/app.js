// Exemplo do plugin "notification": toasts com botões e eventos.
import { isBorion } from '@borion/api';
import {
  isPermissionGranted, sendNotification, hide, onAction, onDismissed,
} from '@borion/api/notification';

const $ = (id) => document.getElementById(id);

function registrar(texto) {
  const li = document.createElement('li');
  li.textContent = new Date().toLocaleTimeString() + '  ' + texto;
  $('log').prepend(li);
}

async function tentar(fn) {
  try {
    await fn();
  } catch (e) {
    registrar(`erro [${e.code}] ${e.message}`);
  }
}

let ultima = null;
let pedidos = 0;

async function simples() {
  ultima = await sendNotification({
    title: $('titulo').value,
    body: $('corpo').value,
    silent: $('silenciosa').checked,
  });
  registrar(`sendNotification -> ${ultima}`);
}

$('enviar').onclick = () => tentar(simples);
$('enviar-depois').onclick = () => {
  registrar('notificando em 5 s...');
  setTimeout(() => tentar(simples), 5000);
};

$('pedido').onclick = () => tentar(async () => {
  pedidos++;
  ultima = await sendNotification({
    id: `pedido-${pedidos}`,  // o mesmo id substituiria a notificação anterior
    title: `Pedido #${pedidos} aguardando aprovação`,
    body: 'Cliente: José da Silva · R$ 1.234,56',
    actions: [
      { id: 'aprovar', title: 'Aprovar ✓' },
      { id: 'recusar', title: 'Recusar' },
    ],
  });
  registrar(`sendNotification -> ${ultima}`);
});

$('esconder').onclick = () => tentar(async () => {
  if (ultima) await hide(ultima);
});

onAction(({ id, action }) => {
  registrar(action ? `onAction: botão "${action}" de ${id}` : `onAction: clique em ${id}`);
});
onDismissed(({ id, reason }) => registrar(`onDismissed: ${id} (${reason})`));

if (isBorion()) {
  isPermissionGranted().then((ok) => {
    $('permissao').textContent = ok ? 'concedida' : 'negada nas Configurações do Windows';
  });
} else {
  registrar('fora do Borion: abra pelo NotificationDemo.exe');
}
