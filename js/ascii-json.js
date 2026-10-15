// Uso interno do @borion/api: JSON só com ASCII (não-ASCII como \uXXXX).
// As strings do Delphi 7 são ANSI e perderiam emoji e caracteres fora da página
// de código; os plugins clipboard e store recebem e devolvem este formato e
// guardam/convertem o texto sem passar pela página de código.

const BARRA = String.fromCharCode(92);

/** JSON.stringify com tudo fora de ' '..'~' escapado; undefined se o valor não for serializável. */
export function asciiJson(value) {
  const json = JSON.stringify(value);
  if (json === undefined) return undefined;
  return json.replace(/[^ -~]/g, (c) => BARRA + 'u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
}

/** Literal de string (para chaves e textos). */
export function asciiString(text) {
  return asciiJson(String(text));
}
