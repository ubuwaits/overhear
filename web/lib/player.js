export const filters = Object.freeze([
  { id: 'empty-mall', name: 'Empty mall', preset: 0 },
  { id: 'movie-theater', name: 'Movie theater', preset: 4 },
  { id: 'open-window', name: 'Open window', preset: 1 },
  { id: 'thin-wall', name: 'Thin wall', preset: 2 },
  { id: 'hotel-corridor', name: 'Hotel corridor', preset: 3 },
  { id: 'parking-garage', name: 'Parking garage', preset: 5 },
  { id: 'kitchen-radio', name: 'Kitchen radio', preset: 6 },
  { id: 'none', name: 'No filter', preset: null }
].map(Object.freeze));

export class OverhearPlayer {
  static async create(audio, { assetBase = new URL('./', import.meta.url) } = {}) {
    if (!(audio instanceof HTMLAudioElement)) throw new TypeError('Expected an HTMLAudioElement');
    const context = new AudioContext();
    try {
      const response = await fetch(new URL('overhear.wasm', assetBase));
      if (!response.ok) throw new Error('Could not load the audio engine');
      const wasmBytes = await response.arrayBuffer();
      await context.audioWorklet.addModule(new URL('worklet.js', assetBase));
      const node = new AudioWorkletNode(context, 'overhear', {
        numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2], processorOptions: { wasmBytes }
      });
      audio.crossOrigin = 'anonymous';
      const source = context.createMediaElementSource(audio);
      source.connect(node).connect(context.destination);
      return new OverhearPlayer(audio, context, source, node);
    } catch (error) { await context.close(); throw error; }
  }
  constructor(audio, context, source, node) {
    Object.assign(this, { audio, context, source, node });
    this.filter = 'none';
    this.presence = 1;
    this.resume = () => { void context.resume(); };
    audio.addEventListener('play', this.resume);
    // Resume inside the trusted gesture, before the asynchronous media event.
    this.gestureTarget = audio.ownerDocument;
    for (const event of ['pointerdown', 'touchend', 'keydown']) {
      this.gestureTarget.addEventListener(event, this.resume, { capture: true, passive: true });
    }
    node.onprocessorerror = () => {
      audio.pause();
      audio.dispatchEvent(new CustomEvent('overhearerror', { detail: 'Audio processing failed. Reload the player.' }));
    };
  }
  load(fileOrURL) {
    this.audio.pause();
    if (this.objectURL) URL.revokeObjectURL(this.objectURL);
    this.objectURL = fileOrURL instanceof Blob ? URL.createObjectURL(fileOrURL) : null;
    this.audio.src = this.objectURL || String(fileOrURL);
    this.audio.load();
  }
  async play() { await this.context.resume(); await this.audio.play(); }
  pause() { this.audio.pause(); }
  setFilter(id) {
    const filter = filters.find(filter => filter.id === id);
    if (!filter) throw new RangeError(`Unknown filter: ${id}`);
    this.filter = id;
    this.node.port.postMessage({ type: 'filter', value: filter.preset });
  }
  setPresence(value) {
    if (!Number.isFinite(value) || value < 0 || value > 1) throw new RangeError('Presence must be between 0 and 1');
    this.presence = value;
    this.node.port.postMessage({ type: 'presence', value });
  }
  async dispose() {
    this.pause();
    this.audio.removeEventListener('play', this.resume);
    for (const event of ['pointerdown', 'touchend', 'keydown']) {
      this.gestureTarget.removeEventListener(event, this.resume, true);
    }
    this.node.port.postMessage({ type: 'dispose' });
    this.source.disconnect();
    this.node.disconnect();
    if (this.objectURL) URL.revokeObjectURL(this.objectURL);
    await this.context.close();
  }
}
