// Tests for the two human/external surfaces: query.ts (text + JSON) and the
// TUI's pure renderFrame(). Both consume a real HudState from the fixture.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { aggregate } = require('../dist/aggregate');
const { renderQueryJson, renderQueryText } = require('../dist/query');
const { renderFrame } = require('../dist/tui');

const FIXTURE = path.join(__dirname, 'fixtures', 'sample.jsonl');
const stateP = aggregate({ transcriptPath: FIXTURE, snapshotPath: '/tmp/cqg-none' });

test('renderQueryJson emits a parseable HudState matching the object', async () => {
  const state = await stateP;
  const parsed = JSON.parse(renderQueryJson(state));
  assert.equal(parsed.schemaVersion, 1);
  assert.equal(parsed.activity.todos.total, 3);
  assert.equal(parsed.quota.source, 'none');
  assert.deepEqual(parsed, JSON.parse(JSON.stringify(state)));
});

test('renderQueryText includes every populated section', async () => {
  const state = await stateP;
  const txt = renderQueryText(state);
  for (const needle of ['session', 'context', 'tokens', 'todos', 'agents']) {
    assert.ok(txt.includes(needle), `missing "${needle}" in:\n${txt}`);
  }
  assert.ok(txt.includes('n/a'), 'quota none should render n/a');
});

test('renderFrame fits the row budget and shows the key sections', async () => {
  const state = await stateP;
  const rows = 40;
  const frame = renderFrame(state, rows);
  assert.ok(frame.includes('claude-quota-guard'), 'header');
  assert.ok(frame.includes('todos'), 'todos section');
  assert.ok(frame.includes('quit'), 'footer hint');
  assert.ok(frame.includes('\x1b['), 'emits ANSI color');
  assert.ok(frame.split('\n').length <= rows, 'never exceeds the row budget');
});

test('renderFrame degrades to a tiny terminal without throwing', async () => {
  const state = await stateP;
  const frame = renderFrame(state, 5);
  assert.ok(frame.split('\n').length <= 5);
});
