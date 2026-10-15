// Exemplo do plugin "store": preferências persistidas em JSON.
import { isBorion } from '@borion/api';
import { load } from '@borion/api/store';

const $ = (id) => document.getElementById(id);

function aplicarTema(tema) {
  document.documentElement.classList.toggle('escuro', tema === 'escuro');
}

function mostrarNotas(notas) {
  const ul = $('notas');
  ul.innerHTML = '';
  notas.forEach((nota, i) => {
    const li = document.createElement('li');
    li.textContent = nota + ' ';
    const x = document.createElement('button');
    x.textContent = '×';
    x.title = 'Remover';
    x.onclick = async () => {
      notas.splice(i, 1);
      await prefs.set('notas', notas);
      mostrarNotas(notas);
    };
    li.appendChild(x);
    ul.appendChild(li);
  });
}

async function mostrarArquivo() {
  const linhas = (await prefs.entries()).map(([k, v]) => `${JSON.stringify(k)}: ${JSON.stringify(v)}`);
  $('conteudo').textContent = linhas.length ? linhas.join('\n') : '(vazio)';
}

let prefs;

async function iniciar() {
  prefs = await load('prefs.json');

  // contador de aberturas: prova de que o arquivo sobrevive entre execuções
  const aberturas = ((await prefs.get('aberturas')) ?? 0) + 1;
  await prefs.set('aberturas', aberturas);
  $('aberturas').textContent = aberturas;

  $('nome').value = (await prefs.get('nome')) ?? '';
  $('nome').oninput = () => prefs.set('nome', $('nome').value);

  const tema = (await prefs.get('tema')) ?? 'claro';
  $('tema').value = tema;
  aplicarTema(tema);
  $('tema').onchange = () => prefs.set('tema', $('tema').value);
  prefs.onKeyChange('tema', (valor) => aplicarTema(valor));  // vale também para mudanças vindas do Delphi

  const notas = (await prefs.get('notas')) ?? [];
  mostrarNotas(notas);
  $('adicionar').onclick = async () => {
    const texto = $('nova-nota').value.trim();
    if (!texto) return;
    notas.push(texto);
    await prefs.set('notas', notas);
    $('nova-nota').value = '';
    mostrarNotas(notas);
  };

  prefs.onChange(() => mostrarArquivo());
  await mostrarArquivo();

  $('reler').onclick = async () => {
    await prefs.reload();
    await mostrarArquivo();
  };
  $('apagar').onclick = async () => {
    await prefs.clear();
    location.reload();
  };
}

if (isBorion()) {
  iniciar().catch((e) => { $('conteudo').textContent = `erro [${e.code}] ${e.message}`; });
} else {
  $('conteudo').textContent = 'fora do Borion: abra pelo StoreDemo.exe';
}
