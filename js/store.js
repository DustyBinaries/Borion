// @borion/api/store — chave-valor persistido em JSON no %APPDATA% do app
// (plugin "store" do Delphi: TBorionStorePlugin). Inspirado no store do Tauri.
//
//   const prefs = await load('settings.json');
//   await prefs.set('tema', 'escuro');
//   const tema = await prefs.get('tema');     // undefined se não existir
//
// Valores: qualquer coisa que o JSON.stringify aceite. Unicode completo.
import { invoke, listen } from './index.js';
import { asciiJson, asciiString } from './ascii-json.js';

const ok = () => undefined;

// o mesmo nome que o Delphi usa no evento ('Settings' -> 'settings.json')
function normalizar(name) {
  const n = String(name).toLowerCase();
  return n.endsWith('.json') ? n : n + '.json';
}

function chave(key) {
  if (typeof key !== 'string') throw new TypeError('a chave do store deve ser string');
  return asciiString(key);
}

export class Store {
  /** Prefira load(name), que já abre o arquivo e valida o nome. */
  constructor(name) {
    this.name = String(name);
    this.file = normalizar(name);
  }

  #args(extra) {
    return { store: this.name, ...extra };
  }

  /** Valor da chave, ou undefined se ela não existir. */
  async get(key) {
    const r = await invoke('store:get', this.#args({ key: chave(key) }));
    return r === null ? undefined : JSON.parse(r);
  }

  async set(key, value) {
    const json = asciiJson(value);
    if (json === undefined) throw new TypeError(`valor de "${key}" não é serializável em JSON`);
    await invoke('store:set', this.#args({ key: chave(key), value: json }));
  }

  has(key) {
    return invoke('store:has', this.#args({ key: chave(key) }));
  }

  /** true se a chave existia. */
  delete(key) {
    return invoke('store:delete', this.#args({ key: chave(key) }));
  }

  clear() {
    return invoke('store:clear', this.#args()).then(ok);
  }

  /** [[chave, valor], ...] na ordem em que as chaves foram criadas. */
  async entries() {
    const lista = await invoke('store:entries', this.#args());
    return lista.map(([k, v]) => [JSON.parse(k), JSON.parse(v)]);
  }

  async keys() {
    return (await this.entries()).map(([k]) => k);
  }

  async values() {
    return (await this.entries()).map(([, v]) => v);
  }

  async length() {
    return (await this.entries()).length;
  }

  /** Grava agora. Só é preciso se o app desligou o AutoSave no Delphi. */
  save() {
    return invoke('store:save', this.#args()).then(ok);
  }

  /** Descarta o que não foi gravado e relê o arquivo. */
  reload() {
    return invoke('store:reload', this.#args()).then(ok);
  }

  /** Qualquer alteração (desta página, de outra ou do Delphi): handler(key, value); value undefined = apagada. */
  onChange(handler) {
    return listen('store:change', (p) => {
      if (p.store !== this.file) return;
      handler(JSON.parse(p.key), p.value === null ? undefined : JSON.parse(p.value));
    });
  }

  /** Alterações de uma chave: handler(value); undefined = apagada. */
  onKeyChange(key, handler) {
    return this.onChange((k, v) => {
      if (k === key) handler(v);
    });
  }
}

/** Abre o store (lê o arquivo, se existir). Rejeita com INVALID_STORE se o nome for inválido. */
export async function load(name) {
  await invoke('store:load', { store: String(name) });
  return new Store(name);
}
