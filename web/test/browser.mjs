// Run with PLAYWRIGHT_MODULE pointing to an installed Playwright index.mjs.
import assert from 'node:assert/strict';
const { chromium, webkit } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = process.env.BROWSER === 'webkit'
  ? await webkit.launch({ headless: true })
  : await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('http://127.0.0.1:4173/');
  await page.waitForFunction(() => window.fragmentary);
  assert.equal(await page.evaluate(() => window.fragmentary.filter), 'empty-mall');
  assert.equal(await page.getByRole('button', { name: 'Empty mall', exact: true }).getAttribute('aria-pressed'), 'true');
  assert.ok(await page.locator('#presence').isEnabled());
  assert.equal(await page.locator('input[type=file]').count(), 0);
  await page.waitForFunction(() => document.querySelector('audio').readyState >= 2);
  await page.getByRole('button', { name: 'Empty mall', exact: true }).click();
  await page.getByRole('button', { name: 'Play', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('audio').currentTime > 0.1);
  await page.evaluate(() => {
    const p = window.fragmentary;
    window.outputMeter = p.context.createAnalyser();
    p.node.connect(window.outputMeter);
  });
  await page.waitForFunction(() => {
    const samples = new Float32Array(window.outputMeter.fftSize);
    window.outputMeter.getFloatTimeDomainData(samples);
    return samples.some(value => Math.abs(value) > 0.001);
  });
  const state = await page.evaluate(() => ({ context: window.fragmentary.context.state, filter: window.fragmentary.filter, error: document.querySelector('#status').textContent }));
  assert.equal(state.context, 'running'); assert.equal(state.filter, 'empty-mall');
  assert.ok(!state.error.includes('failed'));
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  assert.ok(await page.evaluate(() => document.querySelector('audio').paused));
  await page.locator('#seek').fill('30');
  await page.locator('#seek').dispatchEvent('input');
  assert.ok(await page.evaluate(() => Math.abs(document.querySelector('audio').currentTime - 30) < 1));
  await page.getByRole('button', { name: 'Mute', exact: true }).click();
  assert.ok(await page.evaluate(() => document.querySelector('audio').muted));
  await page.getByRole('button', { name: 'Unmute', exact: true }).click();
  await page.getByRole('button', { name: 'No filter', exact: true }).click();
  assert.ok(await page.locator('#presence').isDisabled());
  await page.setViewportSize({ width: 390, height: 844 });
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  assert.deepEqual(errors, []);
  await page.screenshot({ path: '/private/tmp/fragmentary-web.png', fullPage: true });
  console.log('Bundled audio playback, AudioWorklet, selection, bypass, no upload, and mobile layout passed.');
} finally { await browser.close(); }
