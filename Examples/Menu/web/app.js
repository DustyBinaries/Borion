// Exemplo do plugin "menu": barra de menu nativa, atalhos, update e popup.
import { isBorion } from '@borion/api';
import * as menu from '@borion/api/menu';

const $ = (id) => document.getElementById(id);

function registrar(texto) {
  const li = document.createElement('li');
  li.textContent = new Date().toLocaleTimeString() + '  ' + texto;
  $('log').prepend(li);
}

// --- a barra -----------------------------------------------------------------------

function barra() {
  return [
    { label: '&Arquivo', items: [
      { id: 'novo', label: '&Novo', accelerator: 'Ctrl+N' },
      { id: 'salvar', label: '&Salvar', accelerator: 'Ctrl+S' },
      { label: '&Exportar', items: [            // submenu
        { id: 'exportar-pdf', label: '&PDF' },
        { id: 'exportar-html', label: '&HTML' },
      ] },
      { type: 'separator' },
      { id: 'desabilitado', label: 'Item desabilitado', enabled: false },
    ] },
    { label: '&Exibir', items: [
      { id: 'lateral', label: '&Painel lateral', type: 'checkbox', checked: true, accelerator: 'Ctrl+B' },
      { id: 'escuro', label: '&Tema escuro', type: 'checkbox', checked: false, accelerator: 'Ctrl+D' },
    ] },
    { label: 'Aj&uda', items: [
      { id: 'sobre', label: '&Sobre', accelerator: 'F1' },
    ] },
  ];
}

// Todo clique chega aqui (também pelos atalhos); itens checkbox mandam o novo estado.
menu.onClick((id, checked) => {
  registrar(checked === undefined ? id : `${id} (checked: ${checked})`);
});

// onItems despacha por id; ids sem handler são ignorados.
menu.onItems({
  lateral: (ligado) => { $('lateral').hidden = !ligado; },
  escuro: (ligado) => { document.documentElement.classList.toggle('escuro', ligado); },
  sobre: () => alert('Exemplo do plugin menu do Borion.'),
});

// --- 1. teclas que chegam à página ---------------------------------------------------

document.addEventListener('keydown', (e) => {
  if (!e.ctrlKey && !e.key.startsWith('F')) return;
  const nome = (e.ctrlKey ? 'Ctrl+' : '') + (e.shiftKey ? 'Shift+' : '') +
    (e.key.length === 1 ? e.key.toUpperCase() : e.key);
  if (['Control', 'Shift'].includes(e.key)) return;
  $('teclas').textContent = 'a página recebeu: ' + nome;
  if (e.ctrlKey && e.key.toLowerCase() === 's') e.preventDefault();  // não abrir o "Salvar" do navegador
});

// --- 2. update -------------------------------------------------------------------------

async function tentar(promessa) {
  try {
    await promessa;
  } catch (e) {
    registrar(`erro [${e.code}] ${e.message}`);
  }
}

$('salvar-habilitado').onchange = (e) => tentar(menu.update('salvar', { enabled: e.target.checked }));
$('renomear').onclick = () => tentar(menu.update('novo', { label: $('rotulo').value }));
$('trocar-atalho').onclick = () => tentar(menu.update('salvar', { accelerator: $('atalho').value }));
$('remover').onclick = () => tentar(menu.clear());
$('recriar').onclick = () => {
  $('salvar-habilitado').checked = true;
  $('lateral').hidden = false;
  document.documentElement.classList.remove('escuro');
  tentar(menu.setMenu(barra()));
};

// --- 3. popup --------------------------------------------------------------------------

for (const li of $('cores').children) {
  li.oncontextmenu = async (e) => {
    e.preventDefault();  // no lugar do menu de contexto do WebView2
    const id = await menu.popup([
      { id: 'copiar-nome', label: `&Copiar "${li.textContent}"` },
      { id: 'destacar', label: '&Destacar', type: 'checkbox', checked: li.classList.contains('destaque') },
      { type: 'separator' },
      { label: '&Mais', items: [{ id: 'nada', label: 'Submenus também funcionam' }] },
    ]);  // sem posição: abre no cursor
    $('escolha').textContent = `popup em "${li.textContent}": ${JSON.stringify(id)}`;
    if (id === 'destacar') li.classList.toggle('destaque');
  };
}

$('popup-aqui').onclick = async (e) => {
  const r = e.target.getBoundingClientRect();
  // x, y em coordenadas da página (CSS px); o Delphi converte para a tela
  const id = await menu.popup(
    [{ id: 'um', label: 'Opção &1' }, { id: 'dois', label: 'Opção &2' }],
    { x: Math.round(r.left), y: Math.round(r.bottom) });
  $('escolha').textContent = 'popup do botão: ' + JSON.stringify(id);
};

// --- início ----------------------------------------------------------------------------

if (isBorion()) {
  menu.setMenu(barra()).catch((e) => registrar(`erro [${e.code}] ${e.message}`));
} else {
  registrar('fora do Borion: abra pelo MenuDemo.exe');
}
