import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, extname, sep } from 'node:path';
import { parseByteRange } from './byte-range.mjs';
const root = fileURLToPath(new URL('.', import.meta.url));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.css': 'text/css', '.mp3': 'audio/mpeg', '.md': 'text/plain' };
createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (pathname === '/' || pathname === '/index.html') {
      res.writeHead(302, { Location: '/demo/' }); res.end(); return;
    }
    if (!pathname.startsWith('/demo/') && !pathname.startsWith('/lib/')) {
      res.writeHead(404); res.end('Not found'); return;
    }
    const path = resolve(root, '.' + (pathname === '/demo/' ? '/demo/index.html' : pathname));
    if (!path.startsWith(root) || path.includes(`${sep}.`)) throw new Error('Invalid path');
    const file = path;
    const body = await readFile(file);
    const headers = { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes' };
    const range = parseByteRange(req.headers.range, body.length);
    if (!range) {
      res.writeHead(416, { 'Content-Range': `bytes */${body.length}` }); res.end(); return;
    }
    const { start, end } = range;
    if (req.headers.range) {
      headers['Content-Range'] = `bytes ${start}-${end}/${body.length}`;
    }
    headers['Content-Length'] = end - start + 1;
    res.writeHead(req.headers.range ? 206 : 200, headers);
    res.end(req.method === 'HEAD' ? undefined : body.subarray(start, end + 1));
  } catch { res.writeHead(404); res.end('Not found'); }
}).listen(4173, '127.0.0.1', () => console.log('Overhear: http://127.0.0.1:4173/demo/'));
