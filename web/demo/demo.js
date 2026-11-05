import { OverhearPlayer, filters } from '../lib/player.js';
const audio = document.querySelector('audio');
const status = document.querySelector('#status');
const presence = document.querySelector('#presence');
const formatTime = value => {
  const seconds = Number.isFinite(value) ? Math.floor(value) : 0;
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
};
const paintRange = input => {
  const progress = Number(input.max) > 0 ? Number(input.value) / Number(input.max) * 100 : 0;
  input.style.setProperty('--progress', `${progress}%`);
};

function setupTransport(player) {
  const elapsed = document.querySelector('#elapsed');
  const durationLabel = document.querySelector('#duration');
  const playShape = document.querySelector('#play-shape');
  const play = document.querySelector('#play');
  const seek = document.querySelector('#seek');
  const volume = document.querySelector('#volume');
  const mute = document.querySelector('#mute');
  const syncTime = () => {
    const duration = Number.isFinite(audio.duration) ? audio.duration : 0;
    seek.max = duration;
    seek.value = audio.currentTime;
    seek.disabled = duration === 0;
    seek.setAttribute('aria-valuetext', `${formatTime(audio.currentTime)} of ${formatTime(duration)}`);
    elapsed.textContent = formatTime(audio.currentTime);
    durationLabel.textContent = formatTime(duration);
    paintRange(seek);
  };
  const syncPlayback = () => {
    play.setAttribute('aria-label', audio.paused ? 'Play' : 'Pause');
    playShape.setAttribute('d', audio.paused ? 'M8 5v14l11-7z' : 'M6 5h4v14H6zm8 0h4v14h-4z');
  };
  play.disabled = false;
  play.onclick = async () => {
    try {
      if (audio.paused) await player.play(); else player.pause();
      status.textContent = '';
    } catch { status.textContent = 'Playback could not start. Try again.'; }
  };
  seek.oninput = () => { audio.currentTime = Number(seek.value); syncTime(); };
  volume.oninput = () => { audio.volume = Number(volume.value); audio.muted = audio.volume === 0; };
  mute.onclick = () => { audio.muted = !audio.muted; };
  audio.addEventListener('volumechange', () => {
    volume.value = audio.muted ? 0 : audio.volume;
    const muted = audio.muted || audio.volume === 0;
    mute.setAttribute('aria-label', muted ? 'Unmute' : 'Mute');
    mute.setAttribute('aria-pressed', String(muted));
    paintRange(volume);
  });
  for (const event of ['loadedmetadata', 'durationchange', 'timeupdate', 'emptied']) audio.addEventListener(event, syncTime);
  for (const event of ['play', 'pause', 'ended']) audio.addEventListener(event, syncPlayback);
  paintRange(volume);
}

function setupFilters(player) {
  const container = document.querySelector("#filters");
  const buttons = filters.map(filter => {
    const button = document.createElement('button');
    button.textContent = filter.name;
    button.type = 'button';
    button.setAttribute('aria-pressed', String(filter.id === player.filter));
    button.onclick = () => {
      player.setFilter(filter.id);
      buttons.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      presence.disabled = filter.id === 'none';
    };
    container.append(button);
    return button;
  });
  document.querySelector('#places').disabled = false;
}

function setupPresence(player) {
  const amount = document.querySelector("#amount");
  presence.oninput = () => {
    player.setPresence(Number(presence.value));
    amount.textContent = `${Math.round(presence.value * 100)}%`;
    paintRange(presence);
  };
  paintRange(presence);
}

try {
  const player = await OverhearPlayer.create(audio);
  window.overhear = player;
  player.setFilter('open-window');
  presence.disabled = false;
  setupTransport(player);
  setupFilters(player);
  setupPresence(player);
  player.load(new URL('./audio/chopin-nocturne-op9-no2.mp3', import.meta.url));
  status.textContent = '';
  audio.addEventListener('error', () => { status.textContent = 'Could not load the demo audio. Please reload.'; });
  audio.addEventListener('overhearerror', event => { status.textContent = event.detail; });
} catch (error) { status.textContent = `Could not start: ${error.message}. Use a browser with AudioWorklet support on localhost or HTTPS.`; }
