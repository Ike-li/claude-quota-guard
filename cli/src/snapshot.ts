// Reads the quota snapshot written by the bash side (collect.sh / statusline).
//
// Snapshot format is the 6-field tab-separated single line documented in the
// repo's CLAUDE.md:
//   5h%  7d%  5h_proj%  5h_reset  7d_reset  ctx%
// where the reset fields are human deltas ("3d", "4h", "now") — already
// formatted by cqg_fmt_reset_delta. Absent fields are empty strings.
//
// This is the ONLY source of subscription rate-limit data: it is not present in
// the transcript, so in pure headless runs the snapshot may be missing (none) or
// stale (flagged via ageSeconds). We never fabricate it.

import * as fs from 'node:fs';

export interface SnapshotData {
  source: 'snapshot' | 'none';
  path: string | null;
  ageSeconds: number | null;
  fiveHourPercent: number | null;
  sevenDayPercent: number | null;
  fiveHourProjectedPercent: number | null;
  fiveHourResetIn: string | null;
  sevenDayResetIn: string | null;
  ctxPercent: number | null;
}

function sanitizeSessionId(id: string): string {
  return id.replace(/[^A-Za-z0-9_.-]/g, '');
}

function toInt(field: string | undefined): number | null {
  if (field === undefined) return null;
  const s = field.trim();
  if (s === '') return null;
  const n = Number(s);
  return Number.isFinite(n) ? Math.round(n) : null;
}

function toLabel(field: string | undefined): string | null {
  if (field === undefined) return null;
  const s = field.trim();
  return s === '' ? null : s;
}

function emptySnapshot(): SnapshotData {
  return {
    source: 'none',
    path: null,
    ageSeconds: null,
    fiveHourPercent: null,
    sevenDayPercent: null,
    fiveHourProjectedPercent: null,
    fiveHourResetIn: null,
    sevenDayResetIn: null,
    ctxPercent: null,
  };
}

export function defaultSnapshotPath(homeDir: string): string {
  return `${homeDir}/.claude/.quota-now`;
}

// Resolve which snapshot file to read, mirroring guard.sh's precedence exactly:
// a session id reads ONLY its per-session file (`${base}-${id}`) — never the
// shared global one. Every session overwrites global, so falling back to it
// serves another session's numbers (e.g. a relay session's empty 5h, or a
// different session's ctx%) under the wrong identity. No per-session file →
// quota honestly reports "none". The global file is used only when no session
// id is known at all (query the account-wide view by omitting --session).
export function readSnapshot(
  basePath: string,
  opts: { sessionId?: string; now?: number } = {},
): SnapshotData {
  const now = opts.now ?? Date.now();
  const candidates: string[] = opts.sessionId
    ? [`${basePath}-${sanitizeSessionId(opts.sessionId)}`]
    : [basePath];

  for (const path of candidates) {
    let stat: fs.Stats;
    try {
      stat = fs.statSync(path);
      if (!stat.isFile() || stat.size === 0) continue;
    } catch {
      continue;
    }
    let line: string;
    try {
      line = fs.readFileSync(path, 'utf8').split('\n')[0] ?? '';
    } catch {
      continue;
    }
    const f = line.split('\t');
    return {
      source: 'snapshot',
      path,
      ageSeconds: Math.max(0, Math.round((now - stat.mtimeMs) / 1000)),
      fiveHourPercent: toInt(f[0]),
      sevenDayPercent: toInt(f[1]),
      fiveHourProjectedPercent: toInt(f[2]),
      fiveHourResetIn: toLabel(f[3]),
      sevenDayResetIn: toLabel(f[4]),
      ctxPercent: toInt(f[5]),
    };
  }
  return emptySnapshot();
}
