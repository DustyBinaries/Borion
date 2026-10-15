// @borion/api/http — requisições HTTP feitas pelo Delphi, sem CORS (plugin "http"
// do Delphi: TBorionHttpPlugin). Mesma interface do fetch do navegador:
//
//   import { fetch } from '@borion/api/http';
//   const r = await fetch('https://api.exemplo.com/itens', { headers: { Authorization: 'Bearer x' } });
//   const itens = await r.json();
//
// Só URLs liberadas no Delphi (Http.Allow) são aceitas; o resto rejeita com
// code = 'FORBIDDEN_URL'. Extras: timeout (ms) e maxRedirections no init.
import { invoke } from './index.js';
import { bytesParaBase64, base64ParaBytes } from './base64.js';

let sequencia = 0;

const SEM_CORPO = [101, 103, 204, 205, 304];

function abortError(signal) {
  const motivo = signal && signal.reason;
  if (motivo instanceof Error) return motivo;
  return new DOMException('A requisição foi cancelada.', 'AbortError');
}

async function corpoParaBytes(body, headers) {
  if (body === undefined || body === null) return null;
  const tipo = (t) => { if (!headers.has('content-type')) headers.set('content-type', t); };
  if (typeof body === 'string') {
    tipo('text/plain;charset=UTF-8');
    return new TextEncoder().encode(body);
  }
  if (body instanceof URLSearchParams) {
    tipo('application/x-www-form-urlencoded;charset=UTF-8');
    return new TextEncoder().encode(body.toString());
  }
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  if (typeof Blob !== 'undefined' && body instanceof Blob) {
    if (body.type) tipo(body.type);
    return new Uint8Array(await body.arrayBuffer());
  }
  throw new TypeError('corpo não suportado pelo @borion/api/http (use string, URLSearchParams, Blob, ArrayBuffer ou TypedArray)');
}

/**
 * fetch pelo Delphi. Devolve um Response de verdade (text(), json(), blob(),
 * headers...). Status de erro HTTP (404, 500) resolvem normalmente, como no fetch.
 */
export async function fetch(input, init = {}) {
  let url = input;
  let base = {};
  if (typeof Request !== 'undefined' && input instanceof Request) {
    url = input.url;
    base = {
      method: input.method,
      headers: input.headers,
      body: input.body === null ? undefined : await input.clone().arrayBuffer(),
      signal: input.signal,
      redirect: input.redirect,
    };
  }
  const opcoes = { ...base, ...init };
  const endereco = new URL(String(url), globalThis.location ? globalThis.location.href : undefined);
  endereco.hash = '';
  const method = String(opcoes.method || 'GET').toUpperCase();
  const headers = new Headers(opcoes.headers);
  const bytes = await corpoParaBytes(opcoes.body, headers);
  if (bytes && (method === 'GET' || method === 'HEAD')) {
    throw new TypeError(`requisição ${method} não pode ter corpo`);
  }

  const signal = opcoes.signal;
  if (signal && signal.aborted) throw abortError(signal);

  const rid = `${Date.now().toString(36)}-${++sequencia}`;
  const args = {
    rid,
    url: endereco.href,
    method,
    headers: [...headers],
    redirect: opcoes.redirect || 'follow',
  };
  if (bytes) args.body = bytesParaBase64(bytes);
  if (opcoes.timeout) args.timeout = Number(opcoes.timeout);
  if (opcoes.maxRedirections !== undefined) args.maxRedirections = Number(opcoes.maxRedirections);

  let aoAbortar;
  const resposta = invoke('http:fetch', args);
  resposta.catch(() => {});  // se abortar, a rejeição CANCELED que chega depois é esperada
  const cancelada = new Promise((_, rejeitar) => {
    if (!signal) return;
    aoAbortar = () => {
      invoke('http:cancel', { rid }).catch(() => {});
      rejeitar(abortError(signal));
    };
    signal.addEventListener('abort', aoAbortar, { once: true });
  });
  let r;
  try {
    r = await Promise.race([resposta, cancelada]);
  } finally {
    if (signal && aoAbortar) signal.removeEventListener('abort', aoAbortar);
  }

  const semCorpo = SEM_CORPO.includes(r.status) || method === 'HEAD';
  const response = new Response(semCorpo ? null : base64ParaBytes(r.body), {
    status: r.status,
    statusText: r.statusText,
    headers: r.headers,
  });
  Object.defineProperty(response, 'url', { value: r.url });
  Object.defineProperty(response, 'redirected', { value: r.redirected });
  return response;
}
