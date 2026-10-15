// Exemplo do plugin "clipboard": copiar texto e HTML, ler e esvaziar.
import { isBorion } from '@borion/api';
import * as clipboard from '@borion/api/clipboard';

const $ = (id) => document.getElementById(id);

$('texto').value = 'Olá, Borion! 😀 “aspas curvas” — € ✓ 日本語';

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

// --- 1. copiar ---------------------------------------------------------------------

async function copiar() {
  await clipboard.writeText($('texto').value);
  registrar(`writeText: ${[...$('texto').value].length} caracteres`);
}

$('copiar').onclick = () => tentar(copiar);
$('copiar-depois').onclick = () => {
  registrar('copiando em 3 s...');
  setTimeout(() => tentar(copiar), 3000);
};

// --- 2. ler ------------------------------------------------------------------------

$('ler').onclick = () => tentar(async () => {
  const texto = await clipboard.readText();
  if (texto === null) {
    $('lido').textContent = '(a área de transferência não tem texto)';
  } else {
    const pontos = [...texto].slice(0, 12).map((c) => 'U+' + c.codePointAt(0).toString(16).toUpperCase());
    $('lido').textContent = texto + '\n\n' + [...texto].length + ' caracteres: ' + pontos.join(' ') +
      ([...texto].length > 12 ? ' ...' : '');
  }
  registrar('readText');
});

$('limpar').onclick = () => tentar(async () => {
  await clipboard.clear();
  registrar('clear');
});

// --- 3. HTML -----------------------------------------------------------------------

$('copiar-html').onclick = () => tentar(async () => {
  const rico = $('rico');
  await clipboard.writeHtml(rico.innerHTML, rico.innerText);
  registrar('writeHtml (com altText)');
});

if (!isBorion()) registrar('fora do Borion: abra pelo ClipboardDemo.exe');
