import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, extname, sep } from 'node:path';
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
    const file = path === root.slice(0, -1) || path === root ? resolve(root, 'index.html') : path;
    const body = await readFile(file);
    const headers = { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes' };
    let start = 0, end = body.length - 1;
    if (req.headers.range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
      if (!match || (!match[1] && !match[2])) {
        res.writeHead(416, { 'Content-Range': `bytes */${body.length}` }); res.end(); return;
      }
      if (!match[1]) start = Math.max(0, body.length - Number(match[2]));
      else { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
      if (start > end || start >= body.length) {
        res.writeHead(416, { 'Content-Range': `bytes */${body.length}` }); res.end(); return;
      }
      headers['Content-Range'] = `bytes ${start}-${end}/${body.length}`;
    }
    headers['Content-Length'] = end - start + 1;
    res.writeHead(req.headers.range ? 206 : 200, headers);
    res.end(req.method === 'HEAD' ? undefined : body.subarray(start, end + 1));
  } catch { res.writeHead(404); res.end('Not found'); }
}).listen(4173, '127.0.0.1', () => console.log('Fragmentary: http://127.0.0.1:4173/demo/'));
