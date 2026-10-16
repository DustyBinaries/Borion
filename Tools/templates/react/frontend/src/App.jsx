// A interface do app. invoke chama os comandos registrados no .dpr
// (.Command('saudar', Saudar)); os plugins têm módulos próprios.
import { useState } from 'react';
import { invoke, isBorion, version } from '@borion/api';
import { open } from '@borion/api/dialog';

export default function App() {
  const [nome, setNome] = useState('');
  const [saudacao, setSaudacao] = useState({ texto: '', erro: false });
  const [arquivo, setArquivo] = useState('');

  async function saudar(e) {
    e.preventDefault();
    try {
      setSaudacao({ texto: await invoke('saudar', { nome }), erro: false });
    } catch (erro) {
      // exceções do Delphi chegam com o code (EBorionError) e a mensagem
      setSaudacao({ texto: `[${erro.code}] ${erro.message}`, erro: true });
    }
  }

  async function abrir() {
    const caminho = await open({ title: 'Escolha um arquivo' });
    setArquivo(caminho ?? '(cancelado)');
  }

  return (
    <>
      <main>
        <h1>{'{{TITLE_JS}}'}</h1>
        <p className="suave">
          Interface com React + Vite (<code>frontend\</code>), lógica nativa em Delphi
          (<code>{{PROGRAM}}.dpr</code>). Rode o <code>dev.bat</code> e edite{' '}
          <code>frontend\src\App.jsx</code>: a mudança aparece na hora.
        </p>

        <section>
          <h2>Um comando Delphi</h2>
          <form className="linha" onSubmit={saudar}>
            <input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="seu nome" autoFocus />
            <button>Saudar</button>
          </form>
          <p className={saudacao.erro ? 'saida erro' : 'saida'}>{saudacao.texto}</p>
        </section>

        <section>
          <h2>Um plugin</h2>
          <div className="linha">
            <button onClick={abrir}>Escolher um arquivo...</button>
          </div>
          <p className="saida">{arquivo}</p>
        </section>
      </main>
      <footer className="suave">
        {isBorion() ? `Borion ${version()}` : 'Fora do Borion: abra pelo exe (build.bat ou dev.bat).'}
      </footer>
    </>
  );
}
