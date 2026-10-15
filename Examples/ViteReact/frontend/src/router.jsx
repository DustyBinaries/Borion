// Roteador mínimo com a History API (sem dependências), só para o exemplo.
// URLs como /clientes/2 são rotas do app, não arquivos: ao recarregar a página
// (F5), quem devolve o index.html é o fallback de SPA do TBorionAssets.
import { useEffect, useState } from 'react';

export function navigate(path) {
  if (path === location.pathname) return;
  history.pushState(null, '', path);
  window.dispatchEvent(new PopStateEvent('popstate'));
}

export function usePath() {
  const [path, setPath] = useState(location.pathname);
  useEffect(() => {
    const onPop = () => setPath(location.pathname);
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);
  return path;
}

export function Link({ to, children, className }) {
  const ativo = location.pathname === to || (to !== '/' && location.pathname.startsWith(to + '/'));
  return (
    <a
      href={to}
      className={(className || '') + (ativo ? ' ativo' : '')}
      onClick={(e) => {
        e.preventDefault();
        navigate(to);
      }}
    >
      {children}
    </a>
  );
}
