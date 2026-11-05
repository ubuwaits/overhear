// A single HTTP byte range, inclusive at both ends; null means unsatisfiable.
export function parseByteRange(header, length) {
  if (!header) return { start: 0, end: length - 1 };
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return null;
  const start = match[1] ? Number(match[1]) : Math.max(0, length - Number(match[2]));
  const end = match[1] && match[2] ? Math.min(length - 1, Number(match[2])) : length - 1;
  return start > end || start >= length ? null : { start, end };
}
