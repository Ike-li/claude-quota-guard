// Unit tests for the pure presentation helpers in format.ts.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { fmtNum, fmtCost, fmtPercent, bar, fmtAge, fmtRelative } = require('../dist/format');

test('fmtNum abbreviates with k/m and handles missing input', () => {
  assert.equal(fmtNum(500), '500');
  assert.equal(fmtNum(1500), '1.5k');
  assert.equal(fmtNum(1000), '1k');
  assert.equal(fmtNum(2_000_000), '2m');
  assert.equal(fmtNum(null), '—');
  assert.equal(fmtNum(undefined), '—');
});

test('fmtCost uses wider precision for smaller amounts', () => {
  assert.equal(fmtCost(5), '$5.00');
  assert.equal(fmtCost(0.5), '$0.500');
  assert.equal(fmtCost(0.0023), '$0.0023');
  assert.equal(fmtCost(null), '—');
});

test('fmtPercent rounds and handles null', () => {
  assert.equal(fmtPercent(42.6), '43%');
  assert.equal(fmtPercent(0), '0%');
  assert.equal(fmtPercent(null), '—');
});

test('bar fills proportionally and clamps', () => {
  assert.equal(bar(0, 10), '[··········]');
  assert.equal(bar(100, 10), '[██████████]');
  assert.equal(bar(50, 10), '[█████·····]');
  assert.equal(bar(150, 10), '[██████████]'); // clamps over 100
  assert.equal(bar(null, 4), '[····]');
});

test('fmtAge renders compact units', () => {
  assert.equal(fmtAge(30), '30s');
  assert.equal(fmtAge(120), '2m');
  assert.equal(fmtAge(7200), '2h');
  assert.equal(fmtAge(172800), '2d');
  assert.equal(fmtAge(null), '—');
});

test('fmtRelative renders "ago" relative to now', () => {
  const now = 1_700_000_000_000;
  assert.equal(fmtRelative(new Date(now - 2000).toISOString(), now), 'just now');
  assert.equal(fmtRelative(new Date(now - 120_000).toISOString(), now), '2m ago');
  assert.equal(fmtRelative(new Date(now - 7_200_000).toISOString(), now), '2h ago');
  assert.equal(fmtRelative(null), '—');
});
