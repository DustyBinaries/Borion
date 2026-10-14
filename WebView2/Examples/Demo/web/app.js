var host = window.chrome && window.chrome.webview;

document.getElementById('origem').textContent = location.origin;

function enviar(msg) {
  if (!host) { alert('Fora do WebView2'); return; }
  host.postMessage(msg);
}

function enviarObjeto() {
  enviar({ acao: 'salvar', id: 123, itens: ['a', 'b'] });
}

// chamada pelo Delphi via ExecuteScript; o retorno volta como JSON
function somar(a, b) { return a + b; }

// --- API local: respondida pelo OnWebResourceRequested do Delphi ---
function mostrar(texto) { document.getElementById('resposta').textContent = texto; }

function listarClientes() {
  fetch('api/clientes')
    .then(function (r) { return r.json(); })
    .then(function (lista) {
      var ul = document.getElementById('clientes');
      ul.innerHTML = '';
      lista.forEach(function (c) {
        var li = document.createElement('li');
        li.textContent = c.id + ' - ' + c.nome + ' (' + c.cidade + ')';
        ul.appendChild(li);
      });
      mostrar(lista.length + ' clientes recebidos do Delphi');
    })
    .catch(function (e) { mostrar('falhou: ' + e); });
}

function enviarEco() {
  fetch('api/eco?origem=demo', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ texto: document.getElementById('texto').value, quando: new Date().toISOString() })
  })
    .then(function (r) { return r.text(); })
    .then(mostrar)
    .catch(function (e) { mostrar('falhou: ' + e); });
}

function chamar(caminho) {
  fetch(caminho)
    .then(function (r) { return r.text().then(function (t) { return r.status + ' ' + t; }); })
    .then(mostrar)
    .catch(function (e) { mostrar('falhou: ' + e); });
}

if (host) {
  host.addEventListener('message', function (e) {
    var ul = document.getElementById('recebidas');
    if (ul.querySelector('em')) ul.innerHTML = '';
    var li = document.createElement('li');
    li.textContent = new Date().toLocaleTimeString() + '  ' + e.data;
    ul.insertBefore(li, ul.firstChild);
  });
}
