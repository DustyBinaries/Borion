// window.borion é injetado pelo TBorionIpc antes deste script.
// Tipos: Borion/js/borion.d.ts

function $(id) { return document.getElementById(id); }
function valor(id) { return $(id).value; }
function num(id) { return Number($(id).value); }
function mostrar(id, texto) { $(id).textContent = texto; }

$('origem').textContent = location.origin;
$('versao').textContent = window.borion ? 'v' + borion.version : '(não injetada)';

// --- 1 e 2: comandos e erros ------------------------------------------------

function executar(cmd, args, saida) {
  saida = saida || 'saida-comandos';
  var inicio = performance.now();
  return borion.invoke(cmd, args)
    .then(function (r) {
      mostrar(saida, cmd + ' -> ' + JSON.stringify(r, null, 2) +
        '\n(' + (performance.now() - inicio).toFixed(1) + ' ms)');
      return r;
    })
    .catch(function (e) {
      mostrar(saida, cmd + ' falhou\n  code:    ' + e.code + '\n  message: ' + e.message +
        '\n  command: ' + e.command);
    });
}

function listarArquivos() {
  executar('listarArquivos').then(function (lista) {
    var ul = $('arquivos');
    ul.innerHTML = '';
    if (!lista) return;
    mostrar('saida-comandos', 'listarArquivos -> ' + lista.length + ' itens na pasta do executável');
    lista.forEach(function (f) {
      var li = document.createElement('li');
      li.textContent = (f.pasta ? '[pasta] ' : '') + f.nome + (f.pasta ? '' : '  (' + f.tamanho + ' bytes)');
      ul.appendChild(li);
    });
  });
}

function timeout() {
  // tarefaLonga leva ~2,5 s; com timeout de 500 ms o JS desiste antes
  borion.invoke('tarefaLonga', { passos: 10 }, { timeout: 500 })
    .then(function () { mostrar('saida-erros', 'respondeu a tempo?'); })
    .catch(function (e) {
      mostrar('saida-erros', 'tarefaLonga falhou\n  code:    ' + e.code + '\n  message: ' + e.message);
    });
}

// --- 3: comando assíncrono ---------------------------------------------------

function tarefaLonga() {
  var barra = $('progresso');
  $('btn-tarefa').disabled = true;
  barra.value = 0;
  var parar = borion.listen('tarefa:progresso', function (p) {
    barra.max = p.total;
    barra.value = p.passo;
    $('contador').textContent = p.passo + ' / ' + p.total;
  });
  mostrar('saida-tarefa', 'em andamento... (a página continua respondendo)');
  borion.invoke('tarefaLonga', { passos: 10 })
    .then(function (r) { mostrar('saida-tarefa', 'tarefaLonga -> ' + JSON.stringify(r, null, 2)); })
    .catch(function (e) { mostrar('saida-tarefa', 'falhou: [' + e.code + '] ' + e.message); })
    .then(function () { parar(); $('btn-tarefa').disabled = false; });
}

// --- 4: eventos ----------------------------------------------------------------

function emitir() {
  borion.emit('pagina:mensagem', { texto: valor('evento-texto'), quando: new Date().toISOString() });
}

if (window.borion) {
  borion.listen('delphi:mensagem', function (p) {
    var ul = $('eventos');
    if (ul.querySelector('em')) ul.innerHTML = '';
    var li = document.createElement('li');
    li.textContent = p.hora + '  ' + p.texto;
    ul.insertBefore(li, ul.firstChild);
  });
}
