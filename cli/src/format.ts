// Presentation helpers shared by the query (text) and watch (TUI) surfaces, plus
// a token-derived cost estimate adapted from jarrodwatts/claude-hud's cost.ts.
// Pure functions, no side effects.

import type { SessionTokenUsage, ModelTokenBucket, ModelCostBucket } from './types';

export function fmtNum(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n)) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}m`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace(/\.0$/, '')}k`;
  return `${Math.round(n)}`;
}

export function fmtCost(usd: number | null | undefined): string {
  if (usd === null || usd === undefined || !Number.isFinite(usd)) return '—';
  if (usd >= 1) return `$${usd.toFixed(2)}`;
  if (usd >= 0.1) return `$${usd.toFixed(3)}`;
  return `$${usd.toFixed(4)}`;
}

export function fmtPercent(p: number | null | undefined): string {
  return p === null || p === undefined ? '—' : `${Math.round(p)}%`;
}

// Compact horizontal bar, e.g. "[████████··········]".
export function bar(percent: number | null | undefined, width = 18): string {
  if (percent === null || percent === undefined || !Number.isFinite(percent)) {
    return `[${'·'.repeat(width)}]`;
  }
  const clamped = Math.max(0, Math.min(100, percent));
  const filled = Math.round((clamped / 100) * width);
  return `[${'█'.repeat(filled)}${'·'.repeat(width - filled)}]`;
}

export function fmtRelative(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return '—';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '—';
  const s = Math.max(0, Math.round((now - t) / 1000));
  if (s < 5) return 'just now';
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

export function fmtAge(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return '—';
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}

// ── token-derived cost estimate ────────────────────────────────────────
interface Pricing {
  inPerM: number;
  outPerM: number;
}
// Cache-write multiplier is the 5-minute-TTL rate (1.25×). Claude Code also
// uses 1h-TTL cache writes (2×) which we can't distinguish in the summed
// cache_creation_input_tokens — the estimate may understate those slightly.
const CACHE_WRITE_MULT = 1.25;
const CACHE_READ_MULT = 0.1;

// First match wins; more specific lines before broader fallbacks.
// Prices per 1M tokens, per platform.claude.com (cached 2026-06):
//   Fable 5 / Mythos 5: $10/$50 · Opus 4.5–4.8: $5/$25 (4.0/4.1 were $15/$75)
//   Sonnet 4.x: $3/$15 · Haiku 4.5: $1/$5 · Haiku 3.5: $0.8/$4
const PRICING: Array<{ re: RegExp; p: Pricing }> = [
  { re: /\bfable[\s-]?5/i, p: { inPerM: 10, outPerM: 50 } },
  { re: /\bmythos[\s-]?5/i, p: { inPerM: 10, outPerM: 50 } },
  { re: /\bopus[\s-]?4[\s.-]?[5678]/i, p: { inPerM: 5, outPerM: 25 } },
  { re: /\bopus[\s-]?4[\s.-]?[01]\b/i, p: { inPerM: 15, outPerM: 75 } },
  { re: /\bopus\b/i, p: { inPerM: 5, outPerM: 25 } }, // bare/unknown opus → current tier
  { re: /\bopusplan\b/i, p: { inPerM: 5, outPerM: 25 } },
  { re: /\bsonnet[\s-]?(4|3[\s.-]?[57])/i, p: { inPerM: 3, outPerM: 15 } },
  { re: /\bsonnetplan\b/i, p: { inPerM: 3, outPerM: 15 } },
  { re: /\bhaiku[\s-]?4/i, p: { inPerM: 1, outPerM: 5 } },
  { re: /\bhaiku[\s-]?3[\s.-]?5/i, p: { inPerM: 0.8, outPerM: 4 } },
  { re: /\bhaikuplan\b/i, p: { inPerM: 1, outPerM: 5 } },
];

function pricingFor(model: string | null): Pricing | null {
  if (!model) return null;
  for (const { re, p } of PRICING) {
    if (re.test(model)) return p;
  }
  return null;
}

// Returns null when the model is unknown (no silent under-pricing) or there are
// no tokens yet. Bedrock/Vertex are out of scope for the estimate.
export function estimateCostUsd(model: string | null, t: SessionTokenUsage): number | null {
  const p = pricingFor(model);
  if (!p) return null;
  if (t.total === 0) return null;
  const inputUsd = (t.input * p.inPerM) / 1_000_000;
  const cacheWriteUsd = (t.cacheCreation * p.inPerM * CACHE_WRITE_MULT) / 1_000_000;
  const cacheReadUsd = (t.cacheRead * p.inPerM * CACHE_READ_MULT) / 1_000_000;
  const outputUsd = (t.output * p.outPerM) / 1_000_000;
  return inputUsd + cacheWriteUsd + cacheReadUsd + outputUsd;
}

// Cost a session that may span several models, pricing each bucket at its own
// rate and summing. The total stays conservative — matching estimateCostUsd's
// "no silent under-pricing" contract: if ANY token-bearing bucket has an unknown
// model, the total is null (we can't honestly sum what we can't price), even
// though the known buckets still carry their own costUsd in perModel. Zero-token
// buckets are ignored so they neither contribute nor poison the total.
export function estimateCostByModel(
  buckets: ModelTokenBucket[],
): { total: number | null; perModel: ModelCostBucket[] } {
  const perModel: ModelCostBucket[] = buckets.map((b) => ({
    model: b.model,
    usage: b.usage,
    costUsd: estimateCostUsd(b.model, b.usage),
  }));
  let total = 0;
  let priceable = false;
  for (const b of perModel) {
    if (b.usage.total === 0) continue;
    if (b.costUsd === null) return { total: null, perModel };
    total += b.costUsd;
    priceable = true;
  }
  return { total: priceable ? total : null, perModel };
}
