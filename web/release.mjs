import { mkdir, cp } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('./', import.meta.url);
// Only runtime files are shipped. Tests, compiler scripts and the local server
// remain development tools. The library also works without the demo directory.
await mkdir(new URL('dist/', root), { recursive: true });
for (const directory of ['lib', 'demo']) {
  await cp(new URL(directory, root), new URL(`dist/${directory}`, root), { recursive: true });
}
console.log(`Static release: ${fileURLToPath(new URL('dist/', root))}`);
