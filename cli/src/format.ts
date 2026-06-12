// Presentation helpers shared by the query (text) and watch (TUI) surfaces, plus
// a token-derived cost estimate adapted from jarrodwatts/claude-hud's cost.ts.
// Pure functions, no side effects.

import type { SessionTokenUsage } from './types';

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
const CACHE_WRITE_MULT = 1.25;
const CACHE_READ_MULT = 0.1;

// First match wins; more specific lines before broader fallbacks.
const PRICING: Array<{ re: RegExp; p: Pricing }> = [
  { re: /\bopus[\s-]?4/i, p: { inPerM: 15, outPerM: 75 } },
  { re: /\bopusplan\b/i, p: { inPerM: 15, outPerM: 75 } },
  { re: /\bsonnet[\s-]?(4|3[\s.-]?[57])/i, p: { inPerM: 3, outPerM: 15 } },
  { re: /\bsonnetplan\b/i, p: { inPerM: 3, outPerM: 15 } },
  { re: /\bhaiku[\s-]?4/i, p: { inPerM: 1, outPerM: 5 } },
  { re: /\bhaiku[\s-]?3[\s.-]?5/i, p: { inPerM: 0.8, outPerM: 4 } },
  { re: /\bhaikuplan\b/i, p: { inPerM: 0.8, outPerM: 4 } },
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
