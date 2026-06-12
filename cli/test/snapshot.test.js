// Tests for snapshot.ts (reading the bash-side .quota-now) and the aggregate
// branch that consumes it. Covers the per-session STRICT precedence — the
// cross-talk guard mirroring guard.sh — which was previously only manually
// verified.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { readSnapshot } = require('../dist/snapshot');
const { aggregate } = require('../dist/aggregate');

const FIXTURE = path.join(__dirname, 'fixtures', 'sample.jsonl'); // sessionId "FIX"

function tmpBase() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cqg-snap-'));
  return { dir, base: path.join(dir, '.quota-now') };
}
function writeSnap(p, fields) {
  fs.writeFileSync(p, fields.join('\t') + '\n');
}
function rm(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

test('per-session strict: reads own file, never the shared global (cross-talk guard)', () => {
  const { dir, base } = tmpBase();
  writeSnap(base, ['98', '10', '120', 'now', '5d', '9']); // global: another session's 98%
  writeSnap(`${base}-S1`, ['50', '35', '60', '3h', '5d', '24']); // S1's own
  const s = readSnapshot(base, { sessionId: 'S1', now: Date.now() });
  assert.equal(s.source, 'snapshot');
  assert.equal(s.fiveHourPercent, 50, 'must read S1, not global 98');
  assert.equal(s.ctxPercent, 24);
  rm(dir);
});

test('session id present but no per-session file → none (no global fallback)', () => {
  const { dir, base } = tmpBase();
  writeSnap(base, ['98', '10', '120', 'now', '5d', '9']); // global exists
  const s = readSnapshot(base, { sessionId: 'GHOST' });
  assert.equal(s.source, 'none');
  assert.equal(s.fiveHourPercent, null);
  rm(dir);
});

test('no session id → reads the global file', () => {
  const { dir, base } = tmpBase();
  writeSnap(base, ['98', '10', '120', 'now', '5d', '9']);
  const s = readSnapshot(base, {});
  assert.equal(s.source, 'snapshot');
  assert.equal(s.fiveHourPercent, 98);
  rm(dir);
});

test('session id is sanitized to match the on-disk file name', () => {
  const { dir, base } = tmpBase();
  writeSnap(`${base}-abc`, ['12', '3', '15', '1h', '4d', '7']); // sanitized "a/b c" → "abc"
  const s = readSnapshot(base, { sessionId: 'a/b c' });
  assert.equal(s.source, 'snapshot');
  assert.equal(s.fiveHourPercent, 12);
  rm(dir);
});

test('empty rate fields parse as null (relay-style frame)', () => {
  const { dir, base } = tmpBase();
  writeSnap(base, ['', '', '', '', '', '30']);
  const s = readSnapshot(base, {});
  assert.equal(s.fiveHourPercent, null);
  assert.equal(s.fiveHourResetIn, null);
  assert.equal(s.ctxPercent, 30);
  rm(dir);
});

test('age is computed from the snapshot mtime', () => {
  const { dir, base } = tmpBase();
  writeSnap(base, ['40', '9', '45', '2h', '5d', '30']);
  const now = 1_700_000_000_000;
  const mtimeSec = now / 1000 - 120;
  fs.utimesSync(base, mtimeSec, mtimeSec);
  const s = readSnapshot(base, { now });
  assert.equal(s.ageSeconds, 120);
  rm(dir);
});

test('aggregate uses the snapshot for quota + context when present and fresh', async () => {
  const { dir, base } = tmpBase();
  const now = 1_700_000_000_000;
  writeSnap(`${base}-FIX`, ['42', '34', '142', '3h', '5d', '29']);
  fs.utimesSync(`${base}-FIX`, now / 1000, now / 1000);
  const state = await aggregate({ transcriptPath: FIXTURE, snapshotPath: base, sessionId: 'FIX', now });
  assert.equal(state.quota.source, 'snapshot');
  assert.equal(state.quota.fiveHour.usedPercent, 42);
  assert.equal(state.quota.stale, false);
  assert.equal(state.context.source, 'snapshot');
  assert.equal(state.context.usedPercent, 29);
  assert.equal(state.context.windowSize, null, 'real window unknown when % is authoritative');
  rm(dir);
});

test('aggregate marks quota stale when the snapshot is older than --stale', async () => {
  const { dir, base } = tmpBase();
  const now = 1_700_000_000_000;
  writeSnap(`${base}-FIX`, ['42', '34', '142', '3h', '5d', '29']);
  fs.utimesSync(`${base}-FIX`, now / 1000 - 120, now / 1000 - 120); // 120s old, default stale=60
  const state = await aggregate({ transcriptPath: FIXTURE, snapshotPath: base, sessionId: 'FIX', now });
  assert.equal(state.quota.source, 'snapshot');
  assert.equal(state.quota.stale, true);
  assert.equal(state.quota.ageSeconds, 120);
  rm(dir);
});
