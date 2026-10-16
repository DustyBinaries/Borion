// A interface do app. invoke chama os comandos registrados no .dpr
// (.Command('saudar', Saudar)); os plugins têm módulos próprios.
import './style.css';
import { invoke, isBorion, version } from '@borion/api';
import { open } from '@borion/api/dialog';

const $ = (id) => document.getElementById(id);

$('form-saudar').onsubmit = async (e) => {
  e.preventDefault();
  try {
    $('saudacao').textContent = await invoke('saudar', { nome: $('nome').value });
    $('saudacao').className = 'saida';
  } catch (erro) {
    // exceções do Delphi chegam com o code (EBorionError) e a mensagem
    $('saudacao').textContent = `[${erro.code}] ${erro.message}`;
    $('saudacao').className = 'saida erro';
  }
};

$('abrir').onclick = async () => {
  const caminho = await open({ title: 'Escolha um arquivo' });
  $('arquivo').textContent = caminho ?? '(cancelado)';
};

$('rodape').textContent = isBorion()
  ? `Borion ${version()}`
  : 'Fora do Borion: abra pelo exe (build.bat ou dev.bat).';
