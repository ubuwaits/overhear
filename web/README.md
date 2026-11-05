# Fragmentary browser player

A demonstration using the **same C DSP** as the Mac app, compiled to WebAssembly and run in an AudioWorklet. The demo plays a bundled track and has no upload interface. The embedding API can still accept a URL or Blob. No backend or account is needed.

## Demo audio credit

J. S. Bach — Cello Suite No. 1 in G major, BWV 1007: Prelude. Recording credited to Philip Milman, funded by Ludwig and Schlatt (Lud and Schlatt’s Musical Emporium), 2022. Licensed under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
[Recording source and license](https://commons.wikimedia.org/wiki/File:Bach_-_Cello_Suite_no._1_in_G_major,_BWV_1007_-_I._Pr%C3%A9lude,_Lud_and_Schlatts_Musical_Emporium.ogg).
The bundled file is Wikimedia’s MP3 transcode of the Ogg recording. No excerpting or other file edits; selected effects modify playback.

## Run

From `web`, run `npm run dev`, then open http://127.0.0.1:4173/demo/. Serve over localhost or HTTPS; opening HTML directly from disk does not work.

## Layout and release

- `lib/`: reusable JavaScript player API, AudioWorklet, and compiled `fragmentary.wasm`. No UI or music dependencies.
- `demo/`: standalone dark player UI and licensed sample recording. Imports the library through `../lib/player.js`.
- `test/`: DSP and browser integration checks.
- `server.mjs`: development server with audio range support; serves only the demo and library.

`npm run build` assembles `dist/lib/` and `dist/demo/` for static hosting. Open `/demo/` on the deployed host. To embed the complete demo, use an iframe pointing at `/demo/`; a height of about 450px accommodates the card and attribution. To build your own UI, copy only `lib/`. No CSS framework, UI framework, or runtime npm dependencies are needed.

`npm test` checks the shared WASM engine. `npm run test:browser` uses an installed Playwright; set `BROWSER=webkit` to test WebKit and `PLAYWRIGHT_MODULE` to a module path if Playwright is installed outside this project.

To rebuild DSP changes, install Emscripten and run `sh web/build.sh` from the repository root. You can set `EMCC` to an absolute compiler path. Keep the wasm file with the matching C source revision.

## Embed

```html
<audio id="audio" controls></audio>
<script type="module">
import { FragmentaryPlayer, filters } from './lib/player.js';
const player = await FragmentaryPlayer.create(document.querySelector('#audio'));
player.load('/music/example.mp3'); // Or a File/Blob from an upload input.
player.setFilter('empty-mall');
player.setPresence(0.8);
// From a user click:
// await player.play();
// player.pause();
// await player.dispose();
</script>
```

`filters` lists stable IDs and display names; `none` bypasses processing. Presence accepts numbers from 0 to 1. Use the audio element's properties and standard events for seeking, volume and duration; `fragmentaryerror` reports a processing failure. The demo supplies custom controls; the library also works with native audio controls. Create one player per audio element. Dispose before discarding it. `create` accepts `{ assetBase: URL }` to relocate the worklet and wasm assets.

Playback must begin with a user gesture. Remote audio URLs need CORS permission. File formats depend on the browser's decoders. This version processes one clip, not system audio, and is an embedding JavaScript API rather than a server upload API. No filter switching fade or offline export is provided yet.
