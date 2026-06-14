// `quota-guard watch` — full-screen live dashboard.
//
// Raw ANSI (zero runtime deps) using the alternate screen buffer. Re-aggregates
// on an interval (transcript.ts caches by mtime, so unchanged files are cheap)
// and repaints. Restores the terminal cleanly on q / Ctrl-C / SIGTERM / resize.

import { aggregate, type AggregateOptions } from './aggregate';
import type { HudState } from './types';
import { fmtNum, fmtCost, fmtPercent, fmtAge, bar, fmtRelative, renderSparkline } from './format';

// Catppuccin Mocha (truecolor), matching statusline-command.sh.
const C = {
  red: (s: string) => `\x1b[38;2;243;139;168m${s}\x1b[0m`,
  peach: (s: string) => `\x1b[38;2;250;179;135m${s}\x1b[0m`,
  yellow: (s: string) => `\x1b[38;2;249;226;175m${s}\x1b[0m`,
  green: (s: string) => `\x1b[38;2;166;227;161m${s}\x1b[0m`,
  sapphire: (s: string) => `\x1b[38;2;116;199;236m${s}\x1b[0m`,
  mauve: (s: string) => `\x1b[38;2;203;166;247m${s}\x1b[0m`,
  sky: (s: string) => `\x1b[38;2;137;220;235m${s}\x1b[0m`,
  sub: (s: string) => `\x1b[38;2;166;173;200m${s}\x1b[0m`,
  dim: (s: string) => `\x1b[38;2;108;112;134m${s}\x1b[0m`,
  bold: (s: string) => `\x1b[1m${s}\x1b[0m`,
};

function tier(p: number | null, highBad = true): (s: string) => string {
  if (p === null) return C.sub;
  if (highBad) return p >= 80 ? C.red : p >= 50 ? C.yellow : C.green;
  return p >= 80 ? C.green : p >= 50 ? C.yellow : C.red;
}

function statusMark(status: string): string {
  if (status === 'running') return C.yellow('◐');
  if (status === 'error') return C.red('✗');
  if (status === 'in_progress') return C.yellow('◐');
  if (status === 'completed') return C.green('✓');
  return C.dim('·');
}

export function renderFrame(state: HudState, rows: number, showSparklines = true): string {
  const out: string[] = [];
  const s = state.session;

  // header
  const title = C.bold(C.mauve('▌ claude-quota-guard'));
  const name = s.name ?? s.id ?? '—';
  out.push(`${title} ${C.sub('·')} ${C.sapphire(name)}${s.model ? ' ' + C.dim(s.model) : ''}${s.providerDomain ? ' ' + C.dim(s.providerDomain) : ''}`);
  const loc = `${s.cwd ? '📁 ' + s.cwd.split('/').pop() : ''}${s.gitBranch ? C.yellow('  ' + s.gitBranch) : ''}`;
  if (loc.trim()) out.push(C.dim('  ' + loc));
  if (s.turns !== null && s.turns > 0) out.push(C.dim(`  ${s.turns} turns`));
  out.push('');

  // quota
  const q = state.quota;
  if (q.source === 'none') {
    out.push(C.sub('  quota   ') + C.dim('n/a — no snapshot (headless / statusLine never ran)'));
  } else {
    const c5 = tier(q.fiveHour.usedPercent);
    const c7 = tier(q.sevenDay.usedPercent);
    const proj = q.fiveHourProjectedPercent !== null ? C.dim(` →${q.fiveHourProjectedPercent}%`) : '';
    const r5 = q.fiveHour.resetsIn ? C.dim(` ↻${q.fiveHour.resetsIn}`) : '';
    const r7 = q.sevenDay.resetsIn ? C.dim(` ↻${q.sevenDay.resetsIn}`) : '';
    const stale = q.stale ? C.red(`  ⚠ stale ${fmtAge(q.ageSeconds)}`) : C.dim(`  (${fmtAge(q.ageSeconds)})`);
    out.push(
      C.sub('  quota   ') +
        c5(`5h ${tier(q.fiveHour.usedPercent)(bar(q.fiveHour.usedPercent, 12))} ${fmtPercent(q.fiveHour.usedPercent)}`) +
        proj +
        r5 +
        C.dim('   ') +
        c7(`7d ${fmtPercent(q.sevenDay.usedPercent)}`) +
        r7 +
        stale,
    );
  }

  // context
  const ctx = state.context;
  const ctxColor = tier(ctx.usedPercent);
  const ctxTok =
    ctx.tokens !== null
      ? `  ${fmtNum(ctx.tokens)}${ctx.windowSize !== null ? '/' + fmtNum(ctx.windowSize) : ''} tok`
      : '';
  out.push(
    C.sub('  context ') +
      ctxColor(`${bar(ctx.usedPercent, 18)} ${fmtPercent(ctx.usedPercent)}`) +
      C.dim(ctxTok) +
      C.dim(`  (${ctx.source})`),
  );

  // tokens + cost
  const t = state.usage.sessionTokens;
  const cost = state.usage.estimatedCostUsd;
  const cacheSavings = state.usage.cacheSavingsUsd;
  out.push(
    C.sub('  tokens  ') +
      C.dim(`in ${fmtNum(t.input)} · out ${fmtNum(t.output)} · cache ${fmtNum(t.cacheCreation + t.cacheRead)} · total `) +
      C.sky(fmtNum(t.total)) +
      (cost !== null ? C.dim('  ·  ') + C.green('~' + fmtCost(cost)) : ''),
  );
  if (cacheSavings !== null && cacheSavings > 0) {
    out.push(C.sub('          ') + C.green(`saved ${fmtCost(cacheSavings)} via cache`));
  }

  // api calls
  const api = state.usage.apiCalls;
  if (api.total > 0) {
    out.push(
      C.sub('  api     ') +
        C.dim(`${api.total} calls`) +
        (api.errors > 0 ? C.dim(' · ') + C.red(`${api.errors} errors`) : ''),
    );
  }

  // trend (sparkline)
  const trend = state.usage.trend;
  if (showSparklines && trend.length >= 2) {
    const tokenSparkline = renderSparkline(trend.map((s) => s.tokens));
    const costSparkline = renderSparkline(trend.map((s) => s.costUsd));
    const first = trend[0];
    const last = trend[trend.length - 1];
    if (first && last) {
      out.push(
        C.sub('  trend   ') +
          C.dim('tokens ') +
          C.sky(tokenSparkline) +
          C.dim(` (${trend.length} samples)`),
      );
      if (last.costUsd > 0) {
        out.push(
          C.sub('          ') +
            C.dim('cost   ') +
            C.green(costSparkline) +
            C.dim(` (${fmtCost(first.costUsd)} → ${fmtCost(last.costUsd)})`),
        );
      }
    }
  }
  out.push('');

  // todos
  const td = state.activity.todos;
  if (td.total > 0) {
    out.push(
      C.sub('  todos   ') +
        C.green(`${td.completed}`) +
        C.dim('/') +
        `${td.total} done` +
        C.dim(' · ') +
        C.yellow(`${td.inProgress} active`) +
        C.dim(` · ${td.pending} pending`),
    );
    for (const item of td.items.slice(0, 6)) {
      const text = item.content.length > 64 ? item.content.slice(0, 63) + '…' : item.content;
      out.push(`    ${statusMark(item.status)} ${item.status === 'completed' ? C.dim(text) : text}`);
    }
  }

  // agents
  const ag = state.activity.agents;
  if (ag.total > 0) {
    out.push(C.sub('  agents  ') + `${C.yellow(String(ag.running))} running / ${ag.total} total`);
    for (const a of ag.items.slice(-4)) {
      const desc = a.description ? ` ${a.description}` : '';
      out.push(`    ${statusMark(a.status)} ${C.mauve(a.type)}${a.background ? C.dim(' (bg)') : ''}${C.dim(desc)}`);
    }
  }

  // recent tools
  const tools = state.activity.recentTools.slice(-6);
  if (tools.length) {
    out.push(C.sub('  recent'));
    for (const tool of tools) {
      const target = tool.target ? C.dim(' ' + tool.target) : '';
      out.push(`    ${statusMark(tool.status)} ${tool.name}${target}`);
    }
  }

  // tool stats (top 5)
  const toolStats = state.activity.toolStats;
  if (toolStats.length > 0) {
    const formatted = toolStats
      .map((t) => `${t.count}× ${t.name}${t.errors > 0 ? ` ${C.red(`(${t.errors}✗)`)}` : ''}`)
      .join(C.dim(' · '));
    out.push(C.sub('  tools   ') + formatted);
  }

  // errors
  const errSum = state.activity.errorSummary;
  if (errSum.totalErrors > 0) {
    out.push(C.red(`  ✗ ${errSum.totalErrors} errors`));
    for (const err of errSum.recent.slice(-5)) {
      const msg = err.message.length > 60 ? err.message.substring(0, 59) + '…' : err.message;
      out.push(C.dim(`    ${err.tool}: `) + msg);
    }
  }

  // footer (pin to bottom if room)
  const footer =
    C.dim(`  updated ${fmtRelative(state.generatedAt)} · `) +
    C.sub('q') +
    C.dim(' quit');
  while (out.length < rows - 1) out.push('');
  out.push(footer);

  return out.slice(0, rows).join('\n');
}

export async function runWatch(opts: AggregateOptions & { intervalMs?: number; showSparklines?: boolean }): Promise<void> {
  const interval = Math.max(250, opts.intervalMs ?? 1000);
  const stdout = process.stdout;
  const stdin = process.stdin;

  let stopped = false;
  let timer: NodeJS.Timeout | undefined;
  const cleanup = (): void => {
    if (stopped) return;
    stopped = true;
    if (timer) clearInterval(timer);
    if (stdin.isTTY) stdin.setRawMode(false);
    stdin.pause();
    stdout.write('\x1b[?25h'); // show cursor
    stdout.write('\x1b[?1049l'); // leave alt screen
  };

  const draw = async (): Promise<void> => {
    if (stopped) return;
    let state: HudState;
    try {
      state = await aggregate(opts);
    } catch {
      return;
    }
    const rows = stdout.rows && stdout.rows > 4 ? stdout.rows : 24;
    const frame = renderFrame(state, rows, opts.showSparklines !== false);
    // Home cursor, repaint each line clearing to EOL, then clear below — low flicker.
    stdout.write('\x1b[H' + frame.split('\n').map((l) => l + '\x1b[K').join('\n') + '\x1b[J');
  };

  // enter alt screen, hide cursor
  stdout.write('\x1b[?1049h\x1b[?25l\x1b[H\x1b[2J');

  if (stdin.isTTY) {
    stdin.setRawMode(true);
    stdin.resume();
    stdin.on('data', (buf: Buffer) => {
      const k = buf.toString();
      if (k === 'q' || k === '\x03' || k === '\x1b') {
        cleanup();
        process.exit(0);
      }
    });
  }

  process.on('SIGINT', () => {
    cleanup();
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    cleanup();
    process.exit(0);
  });
  stdout.on('resize', () => {
    void draw();
  });

  await draw();
  timer = setInterval(() => void draw(), interval);
  // Keep the process alive until a quit signal arrives.
  await new Promise<void>(() => {
    /* never resolves; exits via cleanup/process.exit */
  });
}
