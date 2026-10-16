// Exemplo do plugin "deep-link": links borion-exemplo://... abrem o app.
import { isBorion } from '@borion/api';
import { getCurrent, onOpenUrl, register, unregister, isRegistered } from '@borion/api/deep-link';

const $ = (id) => document.getElementById(id);
const ESQUEMA = 'borion-exemplo';

// qualquer site pode abrir um link do esquema: valide antes de agir
function descrever(texto) {
  let url;
  try {
    url = new URL(texto);
  } catch {
    return `${texto}  (URL inválida, ignorada)`;
  }
  const params = [...url.searchParams].map(([k, v]) => `${k}=${v}`).join(', ');
  return `${texto}\n  ação: ${url.host}${url.pathname}  parâmetros: ${params || '(nenhum)'}`;
}

async function mostrarRegistro() {
  $('registro').textContent = (await isRegistered(ESQUEMA)) ? 'registrado para este exe' : 'não registrado';
}

let recebidos = 0;
onOpenUrl((urls) => {
  if (!recebidos) $('log').innerHTML = '';
  for (const u of urls) {
    recebidos++;
    const li = document.createElement('li');
    li.textContent = `${new Date().toLocaleTimeString()}  ${descrever(u)}`;
    $('log').prepend(li);
  }
});

$('registrar').onclick = () => register(ESQUEMA).then(mostrarRegistro);
$('desregistrar').onclick = () => unregister(ESQUEMA).then(mostrarRegistro);

if (isBorion()) {
  getCurrent().then((urls) => {
    $('inicial').textContent = urls ? urls.map(descrever).join('\n') : '(o app não foi aberto por um link)';
  });
  mostrarRegistro();
} else {
  $('inicial').textContent = 'fora do Borion: abra pelo DeepLinkDemo.exe';
}
