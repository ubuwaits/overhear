class FragmentaryProcessor extends AudioWorkletProcessor {
  constructor({ processorOptions: { wasmBytes } }) {
    super();
    // Raw bytes also work in Safari versions that cannot clone a compiled
    // WebAssembly.Module into an AudioWorklet. Compile once during setup.
    const module = new WebAssembly.Module(wasmBytes);
    const instance = new WebAssembly.Instance(module, {
      wasi_snapshot_preview1: { proc_exit: () => { throw new Error('DSP exited'); } },
      env: { emscripten_notify_memory_growth: () => {} }
    });
    this.api = instance.exports;
    this.api._initialize?.();
    this.processor = this.api.FragmentaryDSPCreate(sampleRate);
    this.inputPointer = this.api.malloc(128 * 2 * 4);
    this.outputPointer = this.api.malloc(128 * 2 * 4);
    if (!this.processor || !this.inputPointer || !this.outputPointer) throw new Error('DSP allocation failed');
    this.input = new Float32Array(this.api.memory.buffer, this.inputPointer, 256);
    this.output = new Float32Array(this.api.memory.buffer, this.outputPointer, 256);
    this.bypass = true;
    this.disposed = false;
    this.port.onmessage = ({ data }) => {
      if (data.type === 'filter') {
        this.bypass = data.value === null;
        if (!this.bypass) this.api.FragmentaryDSPSetPlace(this.processor, data.value);
      } else if (data.type === 'presence') {
        this.api.FragmentaryDSPSetBlend(this.processor, data.value);
      } else if (data.type === 'dispose') {
        this.api.FragmentaryDSPDestroy(this.processor);
        this.api.free(this.inputPointer);
        this.api.free(this.outputPointer);
        this.disposed = true;
      }
    };
  }
  process(inputs, outputs) {
    if (this.disposed) return false;
    const output = outputs[0];
    const left = inputs[0]?.[0];
    const right = inputs[0]?.[1] || left;
    for (let offset = 0; offset < output[0].length; offset += 128) {
      const count = Math.min(128, output[0].length - offset);
      for (let i = 0; i < count; i++) {
        this.input[i * 2] = left?.[offset + i] || 0;
        this.input[i * 2 + 1] = right?.[offset + i] || 0;
      }
      this.api.FragmentaryDSPProcessInterleavedStereo(this.processor, this.inputPointer, this.outputPointer, count);
      for (let i = 0; i < count; i++) {
        output[0][offset + i] = this.bypass ? this.input[i * 2] : this.output[i * 2];
        output[1][offset + i] = this.bypass ? this.input[i * 2 + 1] : this.output[i * 2 + 1];
      }
    }
    return true;
  }
}
registerProcessor('fragmentary', FragmentaryProcessor);
