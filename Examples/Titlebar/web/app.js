// Exemplo de janela sem borda com a barra de título em HTML.
// Arrastar pela barra e redimensionar pela beirada não precisam de código: o plugin
// window injeta isso em toda página (data-borion-drag-region). Aqui só os botões.
import { isBorion } from '@borion/api';
import * as win from '@borion/api/window';

const $ = (id) => document.getElementById(id);

$('min').onclick = () => win.minimize();
$('max').onclick = () => win.toggleMaximize();
$('close').onclick = () => win.close();

// o ícone do botão do meio: maximizar ou restaurar
function mostrarMaximizada(maximizada) {
  $('max').innerHTML = maximizada ? '&#xE923;' : '&#xE922;';
  $('max').title = maximizada ? 'Restaurar' : 'Maximizar';
}

async function atualizar() {
  const s = await win.state();
  mostrarMaximizada(s.maximized);
  document.body.classList.toggle('decorada', s.decorations);
  $('decorations').checked = s.decorations;
  $('resizable').checked = s.resizable;
  $('estado').textContent = `${s.width} x ${s.height} em (${s.x}, ${s.y})` +
    (s.maximized ? ', maximizada' : '');
}

$('resizable').onchange = (e) => win.setResizable(e.target.checked).then(atualizar);
$('decorations').onchange = (e) => win.setDecorations(e.target.checked).then(atualizar);

// fora de uma barra: startDragging() a partir de qualquer elemento
$('alca').onmousedown = (e) => {
  if (e.button === 0) win.startDragging();
};

if (isBorion()) {
  win.onResized((s) => {
    mostrarMaximizada(s.maximized);
    requestAnimationFrame(atualizar);
  });
  win.onMoved(() => requestAnimationFrame(atualizar));
  win.onFocusChanged((focada) => document.body.classList.toggle('inativa', !focada));
  atualizar();
} else {
  $('estado').textContent = 'fora do Borion: abra pelo TitlebarDemo.exe';
}
