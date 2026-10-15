// Borion Editor: um editor de texto feito só com os plugins oficiais do Borion
// (dialog, fs, shell). Não há nenhum comando Delphi próprio no exemplo.
import './style.css';
import { isBorion } from '@borion/api';
import { open, save, ask, message } from '@borion/api/dialog';
import { readTextFile, writeTextFile, BaseDirectory } from '@borion/api/fs';
import { open as abrirExterno, showInFolder } from '@borion/api/shell';

const FILTROS = [
  { name: 'Texto', extensions: ['txt', 'md', 'log', 'csv', 'json', 'ini'] },
  { name: 'Todos os arquivos', extensions: ['*'] },
];
const RECENTES = 'recentes.json';  // em %APPDATA%\Borion Editor (liberado no escopo)
const MAX_RECENTES = 8;

const $ = (id) => document.getElementById(id);
const texto = $('texto');

const estado = { caminho: null, salvo: '' };

const modificado = () => texto.value !== estado.salvo;
const nome = (caminho) => caminho.split(/[\\/]/).pop();

function atualizarTela() {
  const titulo = (estado.caminho ? nome(estado.caminho) : 'sem título') + (modificado() ? ' •' : '');
  document.title = titulo + ' - Borion Editor';
  $('arquivo').textContent = estado.caminho || 'sem título';
  $('mostrar').disabled = !estado.caminho;
  const linhas = texto.value === '' ? 0 : texto.value.split('\n').length;
  $('contagem').textContent = `${texto.value.length} caracteres · ${linhas} linhas`;
}

async function erro(e, contexto) {
  await message(`${contexto}\n\n[${e.code}] ${e.message}`, { title: 'Borion Editor', kind: 'error' });
}

// --- arquivos recentes (fs com baseDir) ---------------------------------------

async function lerRecentes() {
  try {
    return JSON.parse(await readTextFile(RECENTES, { baseDir: BaseDirectory.AppData }));
  } catch (e) {
    if (e.code !== 'NOT_FOUND') console.warn('recentes:', e);
    return [];
  }
}

async function lembrar(caminho) {
  const lista = [caminho, ...(await lerRecentes()).filter((c) => c.toLowerCase() !== caminho.toLowerCase())];
  await writeTextFile(RECENTES, JSON.stringify(lista.slice(0, MAX_RECENTES), null, 2), {
    baseDir: BaseDirectory.AppData,
  });
  await mostrarRecentes();
}

async function mostrarRecentes() {
  const lista = await lerRecentes();
  const ul = $('recentes');
  ul.innerHTML = '';
  if (!lista.length) {
    ul.innerHTML = '<li class="vazio">nenhum ainda</li>';
    return;
  }
  for (const caminho of lista) {
    const li = document.createElement('li');
    li.textContent = nome(caminho);
    li.title = caminho;
    li.onclick = () => abrirCaminho(caminho, true);
    ul.appendChild(li);
  }
}

// --- ações ---------------------------------------------------------------------

async function podeDescartar() {
  return !modificado() || ask('Há alterações não salvas. Descartar?', { title: 'Borion Editor', kind: 'warning' });
}

async function abrirCaminho(caminho, deRecentes = false) {
  if (!(await podeDescartar())) return;
  try {
    const conteudo = await readTextFile(caminho);
    texto.value = conteudo;
    estado.caminho = caminho;
    estado.salvo = conteudo;
    atualizarTela();
    await lembrar(caminho);
  } catch (e) {
    if (deRecentes && e.code === 'FORBIDDEN_PATH') {
      // Segurança: o escopo só libera o que o usuário escolheu NESTA sessão (e as
      // pastas fixas do app). Um recente de outra sessão precisa ser apontado de novo.
      await message(
        `Por segurança, o Borion só lê arquivos que você escolheu nesta sessão.\n\n${caminho}\n\nConfirme o arquivo na próxima janela.`,
        { title: 'Borion Editor' });
      const escolhido = await open({ title: 'Abrir', filters: FILTROS, defaultPath: caminho });
      if (escolhido) {
        estado.salvo = texto.value;  // já confirmou o descarte
        await abrirCaminho(escolhido);
      }
    } else {
      await erro(e, `Não foi possível abrir ${caminho}`);
    }
  }
}

async function abrir() {
  if (!(await podeDescartar())) return;
  const caminho = await open({ title: 'Abrir', filters: FILTROS, defaultPath: estado.caminho || undefined });
  if (caminho) {
    estado.salvo = texto.value;  // já confirmou o descarte
    await abrirCaminho(caminho);
  }
}

async function salvarComo() {
  const caminho = await save({ title: 'Salvar como', filters: FILTROS, defaultPath: estado.caminho || 'sem título.txt' });
  if (caminho) await gravar(caminho);
}

async function salvar() {
  if (estado.caminho) await gravar(estado.caminho);
  else await salvarComo();
}

async function gravar(caminho) {
  try {
    await writeTextFile(caminho, texto.value);
    estado.caminho = caminho;
    estado.salvo = texto.value;
    atualizarTela();
    await lembrar(caminho);
  } catch (e) {
    await erro(e, `Não foi possível salvar ${caminho}`);
  }
}

async function novo() {
  if (!(await podeDescartar())) return;
  texto.value = '';
  estado.caminho = null;
  estado.salvo = '';
  atualizarTela();
  texto.focus();
}

// --- ligação com a tela ------------------------------------------------------------

$('novo').onclick = novo;
$('abrir').onclick = abrir;
$('salvar').onclick = salvar;
$('salvar-como').onclick = salvarComo;
$('mostrar').onclick = () => showInFolder(estado.caminho).catch((e) => erro(e, 'Não foi possível mostrar o arquivo'));
$('ajuda').onclick = () => abrirExterno('https://developer.microsoft.com/microsoft-edge/webview2/');
texto.addEventListener('input', atualizarTela);

document.addEventListener('keydown', (e) => {
  if (!e.ctrlKey) return;
  const k = e.key.toLowerCase();
  const acao = k === 's' ? (e.shiftKey ? salvarComo : salvar) : k === 'o' ? abrir : k === 'n' ? novo : null;
  if (acao) {
    e.preventDefault();
    acao();
  }
});

atualizarTela();
if (isBorion()) {
  mostrarRecentes();
} else {
  texto.value = 'Abra pelo app (Editor.exe ou dev.bat): fora do Borion os plugins não existem.';
  texto.disabled = true;
}
