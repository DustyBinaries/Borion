// Exemplo de segurança da janela. A página não faz nada contra o navegador: os bloqueios vêm
// do app.json (contextMenu, browserKeys, allowNavigation). Aqui só ficam os dois botões que
// tentam sair do app por script e os sensores do que a página enxergou.
const $ = (id) => document.getElementById(id);

$('abrir').onclick = () => window.open('https://example.com/');
$('href').onclick = () => { location.href = 'https://example.com/'; };

// quantas vezes a página carregou: um F5 ou Ctrl+R que passasse faria subir
let carregamentos = 1;
try {
  carregamentos = (Number(sessionStorage.getItem('carregamentos')) || 0) + 1;
  sessionStorage.setItem('carregamentos', String(carregamentos));
} catch (e) { /* sem sessionStorage: fica em 1 */ }
$('loads').textContent = carregamentos;

let menus = 0;
document.addEventListener('contextmenu', () => { $('ctx').textContent = ++menus; });

const teclas = [];
document.addEventListener('keydown', (e) => {
  teclas.push((e.ctrlKey ? 'Ctrl+' : '') + e.key);
  $('keys').textContent = teclas.slice(-8).join('  ');
});
