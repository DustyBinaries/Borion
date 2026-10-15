import { useEffect, useState } from 'react';
import { invoke, listen, isBorion, version } from '@borion/api';
import { Link, usePath } from './router.jsx';

export default function App() {
  const path = usePath();
  const cliente = path.match(/^\/clientes\/(\d+)$/);

  let pagina;
  if (path === '/') pagina = <Inicio />;
  else if (path === '/clientes') pagina = <Clientes />;
  else if (cliente) pagina = <Cliente id={Number(cliente[1])} />;
  else if (path === '/tarefa') pagina = <Tarefa />;
  else pagina = <NaoEncontrada path={path} />;

  return (
    <div className="app">
      <header>
        <div className="logo">B</div>
        <div>
          <h1>Borion + React</h1>
          <p className="sub">
            {isBorion() ? (
              <>ponte v{version()} &middot; <code>{location.origin}</code></>
            ) : (
              <span className="aviso">fora do Borion: abra pelo app (os comandos não funcionam aqui)</span>
            )}
          </p>
        </div>
        <nav>
          <Link to="/">Início</Link>
          <Link to="/clientes">Clientes</Link>
          <Link to="/tarefa">Tarefa</Link>
        </nav>
      </header>
      <main>{pagina}</main>
      <footer>
        Rota atual: <code>{path}</code> &middot; recarregue a página (F5) em qualquer rota: o fallback de
        SPA do <code>TBorionAssets</code> devolve o <code>index.html</code>.
      </footer>
    </div>
  );
}

// Hook simples para chamar um comando Delphi ao montar o componente.
function useInvoke(cmd, args, deps) {
  const [estado, setEstado] = useState({ carregando: true });
  useEffect(() => {
    let ativo = true;
    setEstado({ carregando: true });
    invoke(cmd, args)
      .then((dados) => ativo && setEstado({ dados }))
      .catch((erro) => ativo && setEstado({ erro }));
    return () => { ativo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return estado;
}

function Erro({ erro }) {
  return <p className="erro">[{erro.code}] {erro.message}</p>;
}

function Inicio() {
  const info = useInvoke('info', {}, []);
  const [nome, setNome] = useState('Maria');
  const [saudacao, setSaudacao] = useState(null);

  async function saudar(e) {
    e.preventDefault();
    try {
      setSaudacao({ texto: await invoke('saudacao', { nome }) });
    } catch (erro) {
      setSaudacao({ erro });
    }
  }

  return (
    <section>
      <h2>Comandos Delphi</h2>
      <div className="card">
        <h3><code>invoke('info')</code></h3>
        {info.carregando && <p>carregando...</p>}
        {info.erro && <Erro erro={info.erro} />}
        {info.dados && (
          <dl>
            {Object.entries(info.dados).map(([k, v]) => (
              <div key={k}><dt>{k}</dt><dd>{String(v)}</dd></div>
            ))}
          </dl>
        )}
      </div>
      <form className="card" onSubmit={saudar}>
        <h3><code>invoke('saudacao', {'{ nome }'})</code></h3>
        <input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="seu nome" />
        <button>saudar</button>
        {saudacao?.texto && <p className="resultado">{saudacao.texto}</p>}
        {saudacao?.erro && <Erro erro={saudacao.erro} />}
      </form>
    </section>
  );
}

function Clientes() {
  const lista = useInvoke('listarClientes', {}, []);
  return (
    <section>
      <h2>Clientes</h2>
      {lista.erro && <Erro erro={lista.erro} />}
      {lista.dados && (
        <ul className="lista">
          {lista.dados.map((c) => (
            <li key={c.id}>
              <Link to={'/clientes/' + c.id}>{c.nome}</Link> <span className="nota">{c.cidade}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Cliente({ id }) {
  const c = useInvoke('cliente', { id }, [id]);
  return (
    <section>
      <h2>Cliente {id}</h2>
      {c.carregando && <p>carregando...</p>}
      {c.erro && <Erro erro={c.erro} />}
      {c.dados && (
        <div className="card">
          <h3>{c.dados.nome}</h3>
          <p>{c.dados.cidade} &middot; desde {c.dados.desde}</p>
        </div>
      )}
      <Link to="/clientes">&larr; voltar</Link>
    </section>
  );
}

function Tarefa() {
  const [progresso, setProgresso] = useState(null);
  const [resultado, setResultado] = useState(null);
  const [rodando, setRodando] = useState(false);

  useEffect(() => {
    if (!isBorion()) return undefined;
    // listen devolve a função que para de escutar: ideal para o cleanup do React
    return listen('tarefa:progresso', setProgresso);
  }, []);

  async function iniciar() {
    setRodando(true);
    setResultado(null);
    setProgresso({ passo: 0, total: 10 });
    try {
      setResultado(await invoke('tarefaLonga', { passos: 10 }));
    } catch (erro) {
      setResultado({ erro: erro.code + ': ' + erro.message });
    } finally {
      setRodando(false);
    }
  }

  return (
    <section>
      <h2>Tarefa numa thread Delphi</h2>
      <div className="card">
        <button onClick={iniciar} disabled={rodando}>iniciar tarefaLonga</button>
        {progresso && (
          <p>
            <progress max={progresso.total} value={progresso.passo} /> {progresso.passo} / {progresso.total}
          </p>
        )}
        {resultado && <pre>{JSON.stringify(resultado, null, 2)}</pre>}
      </div>
    </section>
  );
}

function NaoEncontrada({ path }) {
  return (
    <section>
      <h2>Página não encontrada</h2>
      <p>Nenhuma rota do app para <code>{path}</code>.</p>
      <Link to="/">ir para o início</Link>
    </section>
  );
}
