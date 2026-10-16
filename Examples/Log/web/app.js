// Exemplo do plugin "log": a página e o Delphi gravando no mesmo arquivo.
import { isBorion, listen } from '@borion/api';
import * as log from '@borion/api/log';

const $ = (id) => document.getElementById(id);

for (const b of document.querySelectorAll('[data-nivel]')) {
  b.onclick = () => log[b.dataset.nivel]($('mensagem').value);
}

let desfazer = null;
function repassar(ligado) {
  if (ligado && !desfazer) desfazer = log.forwardConsole();
  if (!ligado && desfazer) {
    desfazer();
    desfazer = null;
  }
}
$('repassar').onchange = (e) => repassar(e.target.checked);

$('console-log').onclick = () => console.log('clique em', { botao: 'console.log', hora: new Date().toISOString() });
$('console-error').onclick = () => console.error(new Error('algo deu errado'));
$('excecao').onclick = () => {
  setTimeout(() => { throw new Error('exceção não tratada'); });
};

// mostra na página as linhas que chegam pelo attachConsole (inclusive as do Delphi)
function mostrarLinha(p) {
  const linha = `${p.time} [${p.level.toUpperCase().padEnd(5)}] [${p.target}] ${JSON.parse(p.message)}\n`;
  $('linhas').textContent = linha + $('linhas').textContent;
}

if (isBorion()) {
  log.logPath().then((p) => { $('caminho').textContent = p; });
  repassar(true);
  log.attachConsole().then(() => {
    listen('log:entry', mostrarLinha);
    log.info('página carregada');
  });
} else {
  $('caminho').textContent = 'fora do Borion: abra pelo LogDemo.exe';
}
