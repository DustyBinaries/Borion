// @borion/api/clipboard — área de transferência do Windows (plugin "clipboard"
// do Delphi: TBorionClipboardPlugin). Unicode completo, inclusive emoji.
import { invoke } from './index.js';
import { asciiString } from './ascii-json.js';

const ok = () => undefined;

/** Copia texto. */
export function writeText(text) {
  return invoke('clipboard:writeText', { text: asciiString(text) }).then(ok);
}

/** Texto da área de transferência, ou null se não houver texto nela. */
export function readText() {
  return invoke('clipboard:readText').then((r) => (r === null ? null : JSON.parse(r)));
}

/**
 * Copia HTML (colar no Word, Outlook... mantém a formatação). altText é o
 * texto puro para quem não entende HTML (o Bloco de Notas, por exemplo).
 */
export function writeHtml(html, altText) {
  const args = { html: asciiString(html) };
  if (altText !== undefined && altText !== null) args.altText = asciiString(altText);
  return invoke('clipboard:writeHtml', args).then(ok);
}

/** Esvazia a área de transferência. */
export function clear() {
  return invoke('clipboard:clear').then(ok);
}
