import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseByteRange } from '../byte-range.mjs';

test('byte ranges support full, bounded, open-ended, and suffix requests', () => {
  for (const [header, start, end] of [[undefined, 0, 99], ['bytes=10-20', 10, 20], ['bytes=90-', 90, 99], ['bytes=-10', 90, 99], ['bytes=90-200', 90, 99], ['bytes=-200', 0, 99]]) {
    assert.deepEqual(parseByteRange(header, 100), { start, end });
  }
});

test('invalid and unsatisfiable ranges are rejected', () => {
  for (const header of ['bytes=-', 'bytes=-0', 'bytes=100-', 'bytes=20-10', 'bytes=0-1,3-4', 'invalid']) {
    assert.equal(parseByteRange(header, 100), null);
  }
  assert.equal(parseByteRange('bytes=0-', 0), null);
});
