// Exemplo do plugin "http": fetch pelo Delphi, sem CORS, com escopo de URLs.
import { isBorion } from '@borion/api';
import { fetch as httpFetch } from '@borion/api/http';

const $ = (id) => document.getElementById(id);

function mostrar(id, texto, classe = '') {
  $(id).className = 'saida ' + classe;
  $(id).textContent = texto;
}

function descreverErro(e) {
  return typeof e.code === 'string' ? `[${e.code}] ${e.message}` : `${e.name}: ${e.message}`;
}

async function medir(fn) {
  const inicio = performance.now();
  const r = await fn();
  return [r, Math.round(performance.now() - inicio)];
}

// --- 1. sem CORS ---------------------------------------------------------------------

$('comparar').onclick = async () => {
  mostrar('navegador', '...');
  mostrar('borion', '...');
  try {
    const r = await fetch('https://example.com/');
    mostrar('navegador', `${r.status}`, 'ok');
  } catch (e) {
    mostrar('navegador', `${descreverErro(e)}\n\n(bloqueado por CORS: veja o console do DevTools)`, 'erro');
  }
  try {
    const [r, ms] = await medir(() => httpFetch('https://example.com/'));
    const html = await r.text();
    const titulo = new DOMParser().parseFromString(html, 'text/html').title;
    mostrar('borion', `${r.status} ${r.statusText} em ${ms} ms\n` +
      `content-type: ${r.headers.get('content-type')}\n<title>: ${titulo}\n\n${html.slice(0, 300)}...`, 'ok');
  } catch (e) {
    mostrar('borion', descreverErro(e), 'erro');
  }
};

// --- 2. JSON -------------------------------------------------------------------------

$('github').onclick = async () => {
  mostrar('saida-github', '...');
  try {
    const repo = $('repo').value.trim();
    const r = await httpFetch(`https://api.github.com/repos/${repo}`, {
      headers: { Accept: 'application/vnd.github+json' },
    });
    const dados = await r.json();
    if (!r.ok) throw new Error(`${r.status}: ${dados.message}`);
    mostrar('saida-github', `${dados.full_name}\n${dados.description}\n` +
      `${dados.stargazers_count} estrelas, ${dados.open_issues_count} issues abertas\n` +
      `limite de requisições restante: ${r.headers.get('x-ratelimit-remaining')}`, 'ok');
  } catch (e) {
    mostrar('saida-github', descreverErro(e), 'erro');
  }
};

// --- 3. POST, timeout, cancelamento --------------------------------------------------

$('post').onclick = async () => {
  mostrar('saida-3', '...');
  try {
    const r = await httpFetch('https://httpbin.org/post', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nome: 'José', emoji: '😀' }),
    });
    const eco = await r.json();
    mostrar('saida-3', `${r.status}: o servidor recebeu\n${JSON.stringify(eco.json, null, 2)}`, 'ok');
  } catch (e) {
    mostrar('saida-3', descreverErro(e), 'erro');
  }
};

$('lento').onclick = async () => {
  mostrar('saida-3', 'esperando...');
  try {
    const [, ms] = await medir(() => httpFetch('https://httpbin.org/delay/5', { timeout: 2000 }));
    mostrar('saida-3', `respondeu em ${ms} ms (não devia)`);
  } catch (e) {
    mostrar('saida-3', descreverErro(e), e.code === 'TIMEOUT' ? 'ok' : 'erro');
  }
};

let controle = null;
$('cancelavel').onclick = async () => {
  controle = new AbortController();
  $('cancelar').disabled = false;
  mostrar('saida-3', 'requisição em andamento (10 s)... clique em Cancelar');
  try {
    const r = await httpFetch('https://httpbin.org/delay/10', { signal: controle.signal });
    mostrar('saida-3', `terminou: ${r.status}`);
  } catch (e) {
    mostrar('saida-3', descreverErro(e), e.name === 'AbortError' ? 'ok' : 'erro');
  } finally {
    $('cancelar').disabled = true;
  }
};
$('cancelar').onclick = () => controle && controle.abort();

// --- 4. escopo -----------------------------------------------------------------------

$('tentar').onclick = async () => {
  mostrar('saida-4', '...');
  try {
    const r = await httpFetch($('url-livre').value);
    mostrar('saida-4', `${r.status} ${r.statusText}`, 'ok');
  } catch (e) {
    mostrar('saida-4', descreverErro(e), 'erro');
  }
};

if (!isBorion()) mostrar('borion', 'fora do Borion: abra pelo HttpDemo.exe', 'erro');
