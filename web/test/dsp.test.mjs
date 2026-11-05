import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { filters } from '../lib/player.js';
const module = await WebAssembly.compile(await readFile(new URL('../lib/fragmentary.wasm', import.meta.url)));
test('shared WASM engine renders every preset and preserves zero-Presence bypass', () => {
  const api = new WebAssembly.Instance(module).exports;
  api._initialize();
  for (const rate of [44100, 48000, 96000]) {
    const dsp = api.FragmentaryDSPCreate(rate);
    assert.ok(dsp);
    const inputPointer = api.malloc(1024);
    const outputPointer = api.malloc(1024);
    const input = new Float32Array(api.memory.buffer, inputPointer, 256);
    const output = new Float32Array(api.memory.buffer, outputPointer, 256);
    for (let i = 0; i < input.length; i++) input[i] = Math.sin(i * 0.13) * 0.2;
    for (const filter of filters.filter(f => f.preset !== null)) {
      api.FragmentaryDSPSetPlace(dsp, filter.preset);
      api.FragmentaryDSPSetBlend(dsp, 1);
      for (let block = 0; block < 400; block++) api.FragmentaryDSPProcessInterleavedStereo(dsp, inputPointer, outputPointer, 128);
      assert.ok(output.every(Number.isFinite));
      assert.ok(output.some((value, i) => Math.abs(value - input[i]) > 0.001));
    }
    api.FragmentaryDSPSetBlend(dsp, 0);
    api.FragmentaryDSPProcessInterleavedStereo(dsp, inputPointer, outputPointer, 128);
    assert.deepEqual(output, input);
    api.FragmentaryDSPDestroy(dsp);
    api.free(inputPointer);
    api.free(outputPointer);
  }
});
