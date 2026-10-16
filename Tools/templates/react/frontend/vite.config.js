import { defineConfig, searchForWorkspaceRoot } from 'vite';
import react from '@vitejs/plugin-react';

// @borion/api é instalado como link para a pasta js do Borion (fora deste projeto):
// o servidor de desenvolvimento precisa poder servir arquivos de lá.
const borionJs = '{{BORION_JS}}';

export default defineConfig({
  plugins: [react()],
  server: {
    port: {{DEV_PORT}},
    strictPort: true, // o dev.bat abre o app em http://localhost:{{DEV_PORT}}
    fs: { allow: [searchForWorkspaceRoot(process.cwd()), borionJs] },
  },
  build: { outDir: 'dist', emptyOutDir: true },
});
