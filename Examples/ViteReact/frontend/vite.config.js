import { defineConfig, searchForWorkspaceRoot } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// @borion/api é instalado como link para Borion/js (fora desta pasta):
// o servidor de desenvolvimento precisa poder servir arquivos de lá.
const borionJs = fileURLToPath(new URL('../../../js', import.meta.url));

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true, // o dev.bat abre o app em http://localhost:5173
    fs: { allow: [searchForWorkspaceRoot(process.cwd()), borionJs] },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
});
