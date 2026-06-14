// Tests the CLI's settings.json reader (dashboard display defaults). Drives the
// compiled dist against temp config files. Run with `npm test` (builds first).
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { loadCliConfig } = require('../dist/config');

function tmpJson(obj) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cqg-cfg-'));
  const file = path.join(dir, 'settings.json');
  fs.writeFileSync(file, JSON.stringify(obj));
  return file;
}

test('loadCliConfig reads refreshInterval and showSparklines', () => {
  const file = tmpJson({ display: { tui: { refreshInterval: 2000, showSparklines: false } } });
  const cfg = loadCliConfig(file);
  assert.equal(cfg.intervalMs, 2000);
  assert.equal(cfg.showSparklines, false); // boolean false must survive (not dropped)
});

test('loadCliConfig ignores a too-small refreshInterval', () => {
  const file = tmpJson({ display: { tui: { refreshInterval: 50 } } });
  assert.equal(loadCliConfig(file).intervalMs, undefined);
});

test('loadCliConfig returns {} for a missing/invalid file', () => {
  assert.deepEqual(loadCliConfig('/no/such/file-xyz.json'), {});
});

test('loadCliConfig returns {} when the tui section is absent', () => {
  const file = tmpJson({ mode: 'auto', thresholds: { ctxHalt: 85 } });
  assert.deepEqual(loadCliConfig(file), {});
});
