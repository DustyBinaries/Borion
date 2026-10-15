// Exemplo do plugin "app": app.info e controle da janela (minimizar, esconder,
// mostrar, sair).
import { isBorion } from '@borion/api';
import * as app from '@borion/api/app';

const $ = (id) => document.getElementById(id);

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

function voltarEm3s() {
  setTimeout(() => {
    registrar('app.show()');
    tentar(app.show());
  }, 3000);
}

// --- 1. info -------------------------------------------------------------------------------

async function mostrarInfo() {
  const info = await app.info();  // { name, version, exe, pid }
  const tabela = $('info');
  tabela.innerHTML = '';
  for (const chave of ['name', 'version', 'exe', 'pid']) {
    const tr = tabela.insertRow();
    tr.insertCell().textContent = chave;
    tr.insertCell().textContent = info[chave] === '' ? '(sem recurso de versão)' : info[chave];
  }
}

// --- 2. janela -----------------------------------------------------------------------------

$('minimizar').onclick = () => { registrar('app.minimize()'); tentar(app.minimize()); };
$('minimizar-volta').onclick = () => {
  registrar('app.minimize()');
  tentar(app.minimize().then(voltarEm3s));
};
$('esconder-volta').onclick = () => {
  registrar('app.hide()');
  tentar(app.hide().then(voltarEm3s));
};

// --- 3. sair -------------------------------------------------------------------------------

$('sair').onclick = async () => {
  // resolve logo (o fechamento é postado); se o OnCloseQuery recusar, a página
  // simplesmente continua aqui
  registrar('app.exit()');
  await tentar(app.exit());
};

// --- início --------------------------------------------------------------------------------

if (isBorion()) {
  tentar(mostrarInfo());
} else {
  $('info').innerHTML = '<tr><td>fora do Borion: abra pelo AppDemo.exe</td></tr>';
}
