// Exemplo do plugin "window": controle da janela pela página, eventos e o
// fechamento interceptado ("deseja salvar?").
import { isBorion } from '@borion/api';
import * as win from '@borion/api/window';

const $ = (id) => document.getElementById(id);

function registrar(texto) {
  const li = document.createElement('li');
  li.textContent = new Date().toLocaleTimeString() + '  ' + texto;
  $('log').prepend(li);
}

async function tentar(promessa) {
  try {
    return await promessa;
  } catch (e) {
    registrar(`erro [${e.code}] ${e.message}`);
  }
}

// --- 1. estado -----------------------------------------------------------------------------

const CAMPOS = ['title', 'x', 'y', 'width', 'height', 'minimized', 'maximized', 'fullscreen',
  'visible', 'focused', 'alwaysOnTop', 'resizable', 'decorations'];

async function atualizarEstado() {
  const s = await win.state();
  const tabela = $('estado');
  tabela.innerHTML = '';
  for (const campo of CAMPOS) {
    const tr = tabela.insertRow();
    tr.insertCell().textContent = campo;
    tr.insertCell().textContent = String(s[campo]);
  }
  $('topo').checked = s.alwaysOnTop;
  $('redimensionavel').checked = s.resizable;
  $('borda').checked = s.decorations;
}

// os eventos chegam em rajada ao arrastar: uma atualização por quadro basta
let pendente = false;
function agendarEstado() {
  if (pendente) return;
  pendente = true;
  requestAnimationFrame(() => { pendente = false; tentar(atualizarEstado()); });
}

// --- 2. título -----------------------------------------------------------------------------

$('definir-titulo').onclick = () => {
  registrar(`setTitle("${$('titulo').value}")`);
  tentar(win.setTitle($('titulo').value).then(agendarEstado));
};

// --- 3. tamanho e posição ------------------------------------------------------------------

for (const botao of document.querySelectorAll('[data-tamanho]')) {
  botao.onclick = () => {
    const [w, h] = botao.dataset.tamanho.split('x').map(Number);
    registrar(`setSize(${w}, ${h})`);
    tentar(win.setSize(w, h));
  };
}
$('centralizar').onclick = () => { registrar('center()'); tentar(win.center()); };
$('canto').onclick = () => { registrar('setPosition(0, 0)'); tentar(win.setPosition(0, 0)); };

// --- 4. estado da janela -------------------------------------------------------------------

$('minimizar').onclick = async () => {
  registrar('minimize(); setFocus() em 3 s');
  await tentar(win.minimize());
  setTimeout(() => tentar(win.setFocus()), 3000);
};
$('maximizar').onclick = () => { registrar('toggleMaximize()'); tentar(win.toggleMaximize()); };
$('tela-cheia').onclick = () => { registrar('setFullscreen(true)'); tentar(win.setFullscreen(true).then(agendarEstado)); };
document.addEventListener('keydown', async (e) => {
  if (e.key === 'Escape' && await win.isFullscreen()) {
    registrar('setFullscreen(false)');
    tentar(win.setFullscreen(false).then(agendarEstado));
  }
});
$('topo').onchange = (e) => {
  registrar(`setAlwaysOnTop(${e.target.checked})`);
  tentar(win.setAlwaysOnTop(e.target.checked).then(agendarEstado));
};
$('redimensionavel').onchange = (e) => {
  registrar(`setResizable(${e.target.checked})`);
  tentar(win.setResizable(e.target.checked).then(agendarEstado));
};
$('borda').onchange = (e) => {
  registrar(`setDecorations(${e.target.checked})`);
  tentar(win.setDecorations(e.target.checked).then(agendarEstado));
};

// --- 5. fechar -----------------------------------------------------------------------------

let salvo = $('documento').value;
const alterado = () => $('documento').value !== salvo;

$('documento').oninput = () => {
  $('situacao').textContent = alterado() ? 'alterado (não salvo)' : 'sem alterações';
  $('situacao').classList.toggle('mudou', alterado());
};

// abre o <dialog> e espera a escolha: 'salvar' | 'descartar' | 'cancelar'
function perguntarSalvar() {
  const dialogo = $('salvar');
  return new Promise((resolver) => {
    for (const botao of dialogo.querySelectorAll('button')) {
      botao.onclick = () => { dialogo.close(); resolver(botao.value); };
    }
    dialogo.oncancel = () => resolver('cancelar');  // Esc
    dialogo.showModal();
  });
}

async function aoFechar(event) {
  registrar(`onCloseRequested (pedido ${event.id})`);
  if (!alterado()) return;  // nada a perder: deixa fechar
  const escolha = await perguntarSalvar();
  registrar('escolha: ' + escolha);
  if (escolha === 'cancelar') {
    event.preventDefault();
  } else if (escolha === 'salvar') {
    salvo = $('documento').value;  // aqui iria um fs.writeTextFile
  }
}

$('fechar').onclick = () => { registrar('close()'); tentar(win.close()); };
$('destruir').onclick = () => { registrar('destroy()'); tentar(win.destroy()); };

// --- início --------------------------------------------------------------------------------

if (isBorion()) {
  win.onResized(agendarEstado);
  win.onMoved(agendarEstado);
  win.onFocusChanged((focada) => { registrar(focada ? 'janela ganhou o foco' : 'janela perdeu o foco'); agendarEstado(); });
  tentar(win.onCloseRequested(aoFechar));
  tentar(atualizarEstado());
} else {
  $('estado').innerHTML = '<tr><td>fora do Borion: abra pelo WindowDemo.exe</td></tr>';
}
