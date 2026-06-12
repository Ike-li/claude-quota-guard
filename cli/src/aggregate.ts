// Combines transcript activity + quota snapshot into the single HudState that
// both `query` and `watch` render. This is the one place data sources are merged,
// so the JSON contract and the TUI never drift apart.

import * as os from 'node:os';
import { parseTranscript, findTranscript } from './transcript';
import { readSnapshot, defaultSnapshotPath } from './snapshot';
import { estimateCostByModel } from './format';
import { HUD_SCHEMA_VERSION, type HudState, type ContextState, type QuotaState } from './types';

export interface AggregateOptions {
  homeDir?: string;
  cwd?: string;
  sessionId?: string;
  transcriptPath?: string;
  snapshotPath?: string;
  staleSeconds?: number;
  windowSize?: number;
  now?: number;
}

const DEFAULT_WINDOW = 200_000;
const DEFAULT_STALE_SECONDS = 60;

export async function aggregate(opts: AggregateOptions = {}): Promise<HudState> {
  const homeDir = opts.homeDir ?? os.homedir();
  const now = opts.now ?? Date.now();
  const staleSeconds = opts.staleSeconds ?? DEFAULT_STALE_SECONDS;
  const windowSize = opts.windowSize ?? DEFAULT_WINDOW;

  const transcriptPath = findTranscript(homeDir, {
    cwd: opts.cwd,
    sessionId: opts.sessionId,
    transcriptPath: opts.transcriptPath,
  });
  const tx = transcriptPath
    ? await parseTranscript(transcriptPath)
    : (await parseTranscript('')); // returns empty data

  const sessionId = opts.sessionId ?? tx.sessionId ?? undefined;
  const snap = readSnapshot(opts.snapshotPath ?? defaultSnapshotPath(homeDir), { sessionId, now });

  // ── quota (only source is the bash snapshot) ──
  const hasQuota =
    snap.source === 'snapshot' &&
    (snap.fiveHourPercent !== null || snap.sevenDayPercent !== null);
  const quota: QuotaState = {
    source: hasQuota ? 'snapshot' : 'none',
    ageSeconds: hasQuota ? snap.ageSeconds : null,
    stale: hasQuota && snap.ageSeconds !== null ? snap.ageSeconds > staleSeconds : false,
    fiveHour: { usedPercent: snap.fiveHourPercent, resetsIn: snap.fiveHourResetIn },
    sevenDay: { usedPercent: snap.sevenDayPercent, resetsIn: snap.sevenDayResetIn },
    fiveHourProjectedPercent: snap.fiveHourProjectedPercent,
  };

  // ── context (snapshot % preferred, else token-derived) ──
  let context: ContextState;
  if (snap.source === 'snapshot' && snap.ctxPercent !== null) {
    // The snapshot % comes from Claude Code with the REAL window (which may be
    // 1M, not our 200k default), so we don't know the true window here — expose
    // tokens but leave windowSize null rather than imply a wrong denominator.
    context = {
      usedPercent: snap.ctxPercent,
      source: 'snapshot',
      tokens: tx.contextTokens,
      windowSize: null,
    };
  } else if (tx.contextTokens !== null) {
    context = {
      usedPercent: Math.min(100, Math.round((tx.contextTokens / windowSize) * 100)),
      source: 'transcript',
      tokens: tx.contextTokens,
      windowSize,
    };
  } else {
    context = { usedPercent: null, source: 'none', tokens: null, windowSize };
  }

  // ── activity ──
  const todos = tx.todos;
  const completed = todos.filter((t) => t.status === 'completed').length;
  const inProgress = todos.filter((t) => t.status === 'in_progress').length;
  const pending = todos.filter((t) => t.status === 'pending').length;
  const runningAgents = tx.agents.filter((a) => a.status === 'running').length;

  // ── cost: price each model's tokens at its own rate, then sum. Mixed-model
  //    sessions (main agent + subagents) are no longer charged at one blanket
  //    rate. Total stays null if any token-bearing model is unpriceable.
  const { total: estimatedCostUsd, perModel: costByModel } = estimateCostByModel(tx.tokensByModel);

  return {
    schemaVersion: HUD_SCHEMA_VERSION,
    generatedAt: new Date(now).toISOString(),
    session: {
      id: sessionId ?? null,
      name: tx.sessionName,
      cwd: tx.cwd ?? opts.cwd ?? null,
      gitBranch: tx.gitBranch,
      version: tx.version,
      model: tx.model,
      transcriptPath,
      startedAt: tx.startedAt,
      lastActivityAt: tx.lastActivityAt,
    },
    quota,
    context,
    activity: {
      todos: { total: todos.length, completed, inProgress, pending, items: todos },
      agents: { running: runningAgents, total: tx.agents.length, items: tx.agents },
      recentTools: tx.tools,
      skills: tx.skills,
      mcpServers: tx.mcpServers,
    },
    usage: {
      sessionTokens: tx.sessionTokens,
      estimatedCostUsd,
      costSource: estimatedCostUsd !== null ? 'estimate' : 'none',
      tokensByModel: costByModel,
    },
  };
}
