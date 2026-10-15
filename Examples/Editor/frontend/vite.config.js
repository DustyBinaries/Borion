import { defineConfig, searchForWorkspaceRoot } from 'vite';
import { fileURLToPath } from 'node:url';

// @borion/api é instalado como link para Borion/js (fora desta pasta)
const borionJs = fileURLToPath(new URL('../../../js', import.meta.url));

export default defineConfig({
  server: {
    port: 5174,
    strictPort: true, // o dev.bat abre o app em http://localhost:5174
    fs: { allow: [searchForWorkspaceRoot(process.cwd()), borionJs] },
  },
  build: { outDir: 'dist', emptyOutDir: true },
});
