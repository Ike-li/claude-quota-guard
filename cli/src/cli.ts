#!/usr/bin/env node
// claude-quota-guard CLI — `query` (external interface) and `watch` (TUI).

import { aggregate, type AggregateOptions } from './aggregate';
import { renderQueryJson, renderQueryText } from './query';
import { runWatch } from './tui';
import { HUD_SCHEMA_VERSION } from './types';

interface ParsedArgs {
  command: string;
  json: boolean;
  sessionId?: string;
  cwd?: string;
  transcriptPath?: string;
  snapshotPath?: string;
  intervalMs?: number;
  windowSize?: number;
  staleSeconds?: number;
}

const USAGE = `claude-quota-guard — quota + session dashboard / query

Usage:
  quota-guard query [options]     Print current session state (JSON or text)
  quota-guard watch [options]     Live full-screen dashboard (TUI)

Options:
  --json                 query: emit JSON (default: human-readable text)
  --session <id>         target a specific session id (default: newest in cwd)
  --cwd <path>           project dir to resolve the transcript for (default: $PWD)
  --transcript <path>    use an explicit transcript .jsonl
  --snapshot <path>      quota snapshot base path (default: ~/.claude/.quota-now)
  --window <tokens>      context window size for % calc (default: 200000)
  --stale <seconds>      mark quota stale past this age (default: 60)
  --interval <ms>        watch: refresh interval (default: 1000, min 250)
  -h, --help             show this help
  -v, --version          show version

Notes:
  Subscription 5h/7d quota comes only from the bash-side snapshot, which is
  written by the statusLine hook. In pure headless (claude -p) runs with no
  recent interactive session, quota shows n/a; activity + context still work.`;

function parseArgs(argv: string[]): ParsedArgs {
  const out: ParsedArgs = { command: '', json: false };
  const rest = argv.slice(2);
  const positional: string[] = [];

  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    const next = (): string | undefined => rest[++i];
    switch (a) {
      case '--json':
        out.json = true;
        break;
      case '--session':
        out.sessionId = next();
        break;
      case '--cwd':
        out.cwd = next();
        break;
      case '--transcript':
        out.transcriptPath = next();
        break;
      case '--snapshot':
        out.snapshotPath = next();
        break;
      case '--interval': {
        const n = Number(next());
        if (Number.isFinite(n)) out.intervalMs = n;
        break;
      }
      case '--window': {
        const n = Number(next());
        if (Number.isFinite(n) && n > 0) out.windowSize = n;
        break;
      }
      case '--stale': {
        const n = Number(next());
        if (Number.isFinite(n) && n >= 0) out.staleSeconds = n;
        break;
      }
      case '-h':
      case '--help':
        out.command = 'help';
        return out;
      case '-v':
      case '--version':
        out.command = 'version';
        return out;
      default:
        if (a && !a.startsWith('-')) positional.push(a);
        break;
    }
  }
  if (!out.command) out.command = positional[0] ?? 'query';
  return out;
}

async function main(): Promise<number> {
  const args = parseArgs(process.argv);

  if (args.command === 'help') {
    process.stdout.write(USAGE + '\n');
    return 0;
  }
  if (args.command === 'version') {
    process.stdout.write(`quota-guard cli (schema v${HUD_SCHEMA_VERSION})\n`);
    return 0;
  }

  const opts: AggregateOptions = {
    cwd: args.cwd,
    sessionId: args.sessionId,
    transcriptPath: args.transcriptPath,
    snapshotPath: args.snapshotPath,
    windowSize: args.windowSize,
    staleSeconds: args.staleSeconds,
  };

  if (args.command === 'query') {
    const state = await aggregate(opts);
    process.stdout.write((args.json ? renderQueryJson(state) : renderQueryText(state)) + '\n');
    return 0;
  }

  if (args.command === 'watch') {
    if (!process.stdout.isTTY) {
      process.stderr.write('watch requires a TTY; use `query` for non-interactive output\n');
      return 1;
    }
    await runWatch({ ...opts, intervalMs: args.intervalMs });
    return 0;
  }

  // Internal command for collect.sh: emit running-agent + pending-todo counts
  // (tab-separated) to append to the snapshot. Not in USAGE; collect.sh calls it.
  if (args.command === '_activity') {
    const state = await aggregate(opts);
    const running = state.activity.agents.running;
    const pending = state.activity.todos.total - state.activity.todos.completed;
    process.stdout.write(`${running}\t${pending}\n`);
    return 0;
  }

  process.stderr.write(`unknown command: ${args.command}\n\n${USAGE}\n`);
  return 2;
}

main()
  .then((code) => process.exit(code))
  .catch((err) => {
    process.stderr.write(`error: ${err instanceof Error ? err.message : String(err)}\n`);
    process.exit(1);
  });
