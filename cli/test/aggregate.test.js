// End-to-end-ish test: drives the real aggregation layer (compiled dist) against
// a fixture transcript. Run with `npm test` (builds first) or `node --test test/`.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { aggregate } = require('../dist/aggregate');

const FIXTURE = path.join(__dirname, 'fixtures', 'sample.jsonl');

test('parses todos, agents, tools, tokens, cost from a transcript', async () => {
  const state = await aggregate({
    transcriptPath: FIXTURE,
    snapshotPath: '/tmp/cqg-nonexistent-snapshot',
    windowSize: 200000,
  });

  // session metadata from top-level + ai-title
  assert.equal(state.session.name, 'fixture session');
  assert.equal(state.session.model, 'claude-sonnet-4-6');
  assert.equal(state.session.gitBranch, 'main');
  assert.equal(state.session.version, '2.1.0');

  // todos: 1 done / 1 in-progress / 1 pending
  assert.equal(state.activity.todos.total, 3);
  assert.equal(state.activity.todos.completed, 1);
  assert.equal(state.activity.todos.inProgress, 1);
  assert.equal(state.activity.todos.pending, 1);

  // a background Task with no completion stays running
  assert.equal(state.activity.agents.total, 1);
  assert.equal(state.activity.agents.running, 1);
  assert.equal(state.activity.agents.items[0].background, true);

  // Read got a tool_result (completed); Bash did not (running)
  const byName = Object.fromEntries(state.activity.recentTools.map((t) => [t.name, t.status]));
  assert.equal(byName.Read, 'completed');
  assert.equal(byName.Bash, 'running');

  // mcp/skills empty here; cost estimated for a known model
  assert.equal(state.usage.costSource, 'estimate');
  assert.ok(state.usage.estimatedCostUsd > 0);
  // single-model session → exactly one bucket, tagged with that model
  assert.equal(state.usage.tokensByModel.length, 1);
  assert.equal(state.usage.tokensByModel[0].model, 'claude-sonnet-4-6');

  // no snapshot → quota none, context falls back to transcript-derived
  assert.equal(state.quota.source, 'none');
  assert.equal(state.context.source, 'transcript');
  assert.ok(state.context.usedPercent >= 0 && state.context.usedPercent <= 100);
});

test('quota is none and not stale when there is no snapshot', async () => {
  const state = await aggregate({
    transcriptPath: FIXTURE,
    snapshotPath: '/tmp/cqg-nonexistent-snapshot',
  });
  assert.equal(state.quota.source, 'none');
  assert.equal(state.quota.stale, false);
  assert.equal(state.quota.fiveHour.usedPercent, null);
});

test('schema version is stamped', async () => {
  const state = await aggregate({ transcriptPath: FIXTURE, snapshotPath: '/tmp/none' });
  assert.equal(state.schemaVersion, 1);
});

test('pricing table matches published per-MTok rates', () => {
  const { estimateCostUsd } = require('../dist/format');
  // 1M input + 1M output, no cache → cost = inPerM + outPerM exactly.
  const t = { input: 1_000_000, output: 1_000_000, cacheCreation: 0, cacheRead: 0, total: 2_000_000 };
  assert.equal(estimateCostUsd('claude-fable-5', t), 60); // $10 + $50
  assert.equal(estimateCostUsd('claude-opus-4-8', t), 30); // $5 + $25 (NOT legacy $15/$75)
  assert.equal(estimateCostUsd('claude-opus-4-1', t), 90); // legacy $15 + $75
  assert.equal(estimateCostUsd('claude-sonnet-4-6', t), 18); // $3 + $15
  assert.equal(estimateCostUsd('claude-haiku-4-5-20251001', t), 6); // $1 + $5
  assert.equal(estimateCostUsd('totally-unknown-model', t), null); // no silent mispricing
  // Cache multipliers: 1M cache-read on opus 4.8 → 5 * 0.1 = $0.50
  const c = { input: 0, output: 0, cacheCreation: 0, cacheRead: 1_000_000, total: 1_000_000 };
  assert.equal(estimateCostUsd('claude-opus-4-8', c), 0.5);
});

test('estimateCostByModel sums per-model buckets at their own rates', () => {
  const { estimateCostByModel } = require('../dist/format');
  const mk = (i, o) => ({ input: i, output: o, cacheCreation: 0, cacheRead: 0, total: i + o });

  // two known models → total = sum of each bucket priced at its own rate
  const r1 = estimateCostByModel([
    { model: 'claude-opus-4-8', usage: mk(1_000_000, 1_000_000) }, // $5 + $25 = 30
    { model: 'claude-haiku-4-5', usage: mk(2_000_000, 2_000_000) }, // $2 + $10 = 12
  ]);
  assert.equal(r1.total, 42);
  assert.equal(r1.perModel[0].costUsd, 30);
  assert.equal(r1.perModel[1].costUsd, 12);

  // any token-bearing unpriceable model → total null (no silent under-pricing),
  // but the known bucket still carries its own costUsd in perModel
  const r2 = estimateCostByModel([
    { model: 'claude-opus-4-8', usage: mk(1_000_000, 1_000_000) }, // 30
    { model: 'bedrock-arn-xyz', usage: mk(10, 10) }, // unknown → null
  ]);
  assert.equal(r2.total, null);
  assert.equal(r2.perModel[0].costUsd, 30);
  assert.equal(r2.perModel[1].costUsd, null);

  // zero-token buckets are skipped — they neither contribute nor poison the total
  const r3 = estimateCostByModel([
    { model: 'claude-opus-4-8', usage: mk(1_000_000, 1_000_000) }, // 30
    { model: 'unknown-but-empty', usage: mk(0, 0) }, // skipped
  ]);
  assert.equal(r3.total, 30);

  // no buckets → null (nothing priceable)
  assert.equal(estimateCostByModel([]).total, null);
});

test('mixed-model session is priced per-model, not at one blanket rate', async () => {
  const FIXTURE_MIX = path.join(__dirname, 'fixtures', 'mixed-models.jsonl');
  const state = await aggregate({
    transcriptPath: FIXTURE_MIX,
    snapshotPath: '/tmp/cqg-nonexistent-snapshot',
  });

  // two distinct model buckets
  const buckets = state.usage.tokensByModel;
  assert.equal(buckets.length, 2);
  const byModel = Object.fromEntries(buckets.map((b) => [b.model, b]));
  assert.ok(byModel['claude-opus-4-8'], 'opus bucket present');
  assert.ok(byModel['claude-haiku-4-5'], 'haiku bucket present');

  // opus: 1M in @ $5 + 1M out @ $25 = $30 ; haiku: 2M in @ $1 + 2M out @ $5 = $12
  assert.equal(byModel['claude-opus-4-8'].costUsd, 30);
  assert.equal(byModel['claude-haiku-4-5'].costUsd, 12);

  // total = 30 + 12 = 42 — NOT the old blanket-rate bug, which would charge all
  // 6M tokens at the last model's rate (haiku → $18) or first (opus → $90).
  assert.equal(state.usage.estimatedCostUsd, 42);
  assert.equal(state.usage.costSource, 'estimate');

  // per-model buckets sum to the flat sessionTokens total (nothing dropped)
  const sumTokens = buckets.reduce((s, b) => s + b.usage.total, 0);
  assert.equal(sumTokens, state.usage.sessionTokens.total);
});
