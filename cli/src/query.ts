// `quota-guard query` — one-shot snapshot of the current session for external
// consumers (claude -p / SDK apps shell out and parse --json; humans read text).

import type { HudState } from './types';
import { fmtNum, fmtCost, fmtPercent, fmtAge, bar, fmtRelative } from './format';

export function renderQueryJson(state: HudState): string {
  return JSON.stringify(state, null, 2);
}

export function renderQueryText(state: HudState): string {
  const lines: string[] = [];
  const s = state.session;

  lines.push(`session   ${s.name ?? s.id ?? '—'}${s.model ? `  (${s.model})` : ''}`);
  if (s.gitBranch || s.cwd) {
    lines.push(`project   ${s.cwd ?? '—'}${s.gitBranch ? `  @${s.gitBranch}` : ''}`);
  }
  if (s.lastActivityAt) lines.push(`activity  last reply ${fmtRelative(s.lastActivityAt)}`);

  // quota
  const q = state.quota;
  if (q.source === 'none') {
    lines.push(`quota     n/a (no snapshot — headless or statusLine never ran)`);
  } else {
    const staleTag = q.stale ? `  ⚠ stale ${fmtAge(q.ageSeconds)}` : ` (${fmtAge(q.ageSeconds)} old)`;
    const proj = q.fiveHourProjectedPercent !== null ? ` →${q.fiveHourProjectedPercent}%` : '';
    const r5 = q.fiveHour.resetsIn ? ` ↻${q.fiveHour.resetsIn}` : '';
    const r7 = q.sevenDay.resetsIn ? ` ↻${q.sevenDay.resetsIn}` : '';
    lines.push(
      `quota     5h ${fmtPercent(q.fiveHour.usedPercent)}${proj}${r5}  ·  7d ${fmtPercent(
        q.sevenDay.usedPercent,
      )}${r7}${staleTag}`,
    );
  }

  // context
  const c = state.context;
  const ctxTok =
    c.tokens !== null
      ? `  (${fmtNum(c.tokens)}${c.windowSize !== null ? '/' + fmtNum(c.windowSize) : ''} tok, ${c.source})`
      : `  (${c.source})`;
  lines.push(`context   ${bar(c.usedPercent)} ${fmtPercent(c.usedPercent)}${ctxTok}`);

  // tokens + cost
  const t = state.usage.sessionTokens;
  const cost = state.usage.estimatedCostUsd;
  lines.push(
    `tokens    in ${fmtNum(t.input)} · out ${fmtNum(t.output)} · cache ${fmtNum(
      t.cacheCreation + t.cacheRead,
    )} · total ${fmtNum(t.total)}` + (cost !== null ? `  ·  ~${fmtCost(cost)}` : ''),
  );

  // activity
  const td = state.activity.todos;
  if (td.total > 0) {
    lines.push(`todos     ${td.completed}/${td.total} done · ${td.inProgress} in-progress · ${td.pending} pending`);
  }
  const ag = state.activity.agents;
  if (ag.total > 0) {
    lines.push(`agents    ${ag.running} running / ${ag.total} total`);
  }
  if (state.activity.skills.length) lines.push(`skills    ${state.activity.skills.join(', ')}`);
  if (state.activity.mcpServers.length) lines.push(`mcp       ${state.activity.mcpServers.join(', ')}`);

  const tools = state.activity.recentTools.slice(-5);
  if (tools.length) {
    lines.push('recent');
    for (const tool of tools) {
      const mark = tool.status === 'running' ? '◐' : tool.status === 'error' ? '✗' : '✓';
      lines.push(`  ${mark} ${tool.name}${tool.target ? ` ${tool.target}` : ''}`);
    }
  }

  return lines.join('\n');
}
