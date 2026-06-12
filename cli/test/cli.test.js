// Tests for cli.ts argument parsing + dispatch. cli.ts runs main() on import
// (and calls process.exit), so it is driven as a subprocess rather than required.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const CLI = path.join(__dirname, '..', 'dist', 'cli.js');
const FIXTURE = path.join(__dirname, 'fixtures', 'sample.jsonl');

function run(args) {
  try {
    const out = execFileSync('node', [CLI, ...args], { encoding: 'utf8' });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status, out: `${e.stdout || ''}${e.stderr || ''}` };
  }
}

test('query --json emits valid JSON and exits 0', () => {
  const { code, out } = run(['query', '--json', '--transcript', FIXTURE, '--snapshot', '/tmp/cqg-none']);
  assert.equal(code, 0);
  const o = JSON.parse(out);
  assert.equal(o.schemaVersion, 1);
  assert.equal(o.activity.todos.total, 3);
});

test('default command is query (text) when none is given', () => {
  const { code, out } = run(['--transcript', FIXTURE, '--snapshot', '/tmp/cqg-none']);
  assert.equal(code, 0);
  assert.ok(out.includes('context'));
});

test('unknown command exits 2 and names it', () => {
  const { code, out } = run(['frobnicate']);
  assert.equal(code, 2);
  assert.ok(out.includes('unknown command'));
});

test('--help prints usage and exits 0', () => {
  const { code, out } = run(['--help']);
  assert.equal(code, 0);
  assert.ok(out.includes('Usage:'));
  assert.ok(out.includes('quota-guard query'));
});

test('--version exits 0', () => {
  const { code, out } = run(['--version']);
  assert.equal(code, 0);
  assert.ok(out.toLowerCase().includes('schema'));
});

test('--window override is honored (1M context → not 100%)', () => {
  const { code, out } = run(['query', '--transcript', FIXTURE, '--snapshot', '/tmp/cqg-none', '--window', '1000000']);
  assert.equal(code, 0);
  assert.ok(out.includes('context'));
});

test('watch refuses non-TTY stdout cleanly', () => {
  // stdout is a pipe here (not a TTY) → guard message, non-zero exit, no hang.
  const { code, out } = run(['watch']);
  assert.equal(code, 1);
  assert.ok(out.includes('requires a TTY'));
});
