// Streaming parser for Claude Code transcript JSONL.
//
// Adapted from jarrodwatts/claude-hud's transcript.ts, trimmed to the fields the
// dashboard needs and rewritten against the data model in types.ts. Works in ALL
// modes (interactive AND `claude -p` headless) because the transcript file exists
// regardless of whether a statusLine ever rendered.
//
// An in-memory cache keyed by (path, mtime, size) makes the `watch` loop cheap:
// the file is only re-parsed when it actually changes.

import * as fs from 'node:fs';
import * as readline from 'node:readline';
import type {
  AgentItem,
  ToolItem,
  TodoItem,
  TodoStatus,
  SessionTokenUsage,
  TranscriptData,
} from './types';

const ACTIVITY_NAME_MAX_LEN = 64;
const MCP_TOOL_NAME_PATTERN = /^mcp__(.+?)__(.+)$/;
// Strip ANSI/OSC escapes and bidi/control chars so a malformed transcript can't
// inject terminal control sequences into the TUI. Built from explicit unicode
// escapes rather than literal control characters.
const CONTROL_PATTERN = new RegExp(
  '[' +
    '\\u0000-\\u001F\\u007F-\\u009F' + // C0/C1 control
    '\\u061C\\u200E\\u200F' + // bidi marks
    '\\u202A-\\u202E\\u2066-\\u2069\\u206A-\\u206F' + // bidi embedding/isolates
    ']',
  'g',
);

interface ContentBlock {
  type: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  tool_use_id?: string;
  is_error?: boolean;
}

interface TranscriptLine {
  type?: string;
  subtype?: string;
  operation?: string;
  content?: string;
  timestamp?: string;
  sessionId?: string;
  cwd?: string;
  gitBranch?: string;
  version?: string;
  slug?: string;
  title?: string;
  customTitle?: string;
  message?: {
    model?: string;
    content?: ContentBlock[];
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
}

interface CacheEntry {
  mtimeMs: number;
  size: number;
  data: TranscriptData;
}
const cache = new Map<string, CacheEntry>();

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? Math.max(0, Math.trunc(v)) : 0;
}

function cleanName(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const s = value
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/g, '')
    .replace(CONTROL_PATTERN, '')
    .trim();
  if (!s) return undefined;
  return s.length <= ACTIVITY_NAME_MAX_LEN ? s : `${s.slice(0, ACTIVITY_NAME_MAX_LEN - 1)}…`;
}

function normalizeTaskStatus(status: unknown): TodoStatus | null {
  if (typeof status !== 'string') return null;
  switch (status) {
    case 'pending':
    case 'not_started':
      return 'pending';
    case 'in_progress':
    case 'running':
      return 'in_progress';
    case 'completed':
    case 'complete':
    case 'done':
      return 'completed';
    default:
      return null;
  }
}

function extractTarget(name: string, input?: Record<string, unknown>): string | null {
  if (!input) return null;
  switch (name) {
    case 'Read':
    case 'Write':
    case 'Edit':
      return (input.file_path as string) ?? (input.path as string) ?? null;
    case 'Glob':
    case 'Grep':
      return (input.pattern as string) ?? null;
    case 'Skill':
      return cleanName(input.skill) ?? null;
    case 'Bash': {
      if (typeof input.command !== 'string') return null;
      const cmd = input.command.replace(/\s+/g, ' ').trim();
      if (!cmd) return null;
      return cmd.length > 40 ? `${cmd.slice(0, 40).trimEnd()}…` : cmd;
    }
    default:
      return null;
  }
}

function emptyData(): TranscriptData {
  return {
    sessionId: null,
    sessionName: null,
    cwd: null,
    gitBranch: null,
    version: null,
    model: null,
    startedAt: null,
    lastActivityAt: null,
    tools: [],
    agents: [],
    todos: [],
    skills: [],
    mcpServers: [],
    sessionTokens: { input: 0, output: 0, cacheCreation: 0, cacheRead: 0, total: 0 },
    contextTokens: null,
  };
}

export async function parseTranscript(transcriptPath: string): Promise<TranscriptData> {
  let stat: fs.Stats;
  try {
    stat = fs.statSync(transcriptPath);
    if (!stat.isFile()) return emptyData();
  } catch {
    return emptyData();
  }

  const cached = cache.get(transcriptPath);
  if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size) {
    return cached.data;
  }

  const data = emptyData();
  const toolMap = new Map<string, ToolItem>();
  const agentMap = new Map<string, AgentItem>();
  const skillSet = new Set<string>();
  const mcpSet = new Set<string>();
  let todos: TodoItem[] = [];
  const tokens: SessionTokenUsage = { input: 0, output: 0, cacheCreation: 0, cacheRead: 0, total: 0 };
  const queueCompletion = new Map<string, string>();
  let lastUsageKey: string | undefined;

  try {
    const rl = readline.createInterface({
      input: fs.createReadStream(transcriptPath),
      crlfDelay: Infinity,
    });

    for await (const line of rl) {
      if (!line.trim()) {
        lastUsageKey = undefined;
        continue;
      }
      let entry: TranscriptLine;
      try {
        entry = JSON.parse(line) as TranscriptLine;
      } catch {
        lastUsageKey = undefined;
        continue;
      }

      // Session metadata (top-level on most records).
      if (typeof entry.sessionId === 'string' && entry.sessionId) data.sessionId = entry.sessionId;
      if (typeof entry.cwd === 'string' && entry.cwd) data.cwd = entry.cwd;
      if (typeof entry.gitBranch === 'string' && entry.gitBranch) data.gitBranch = entry.gitBranch;
      if (typeof entry.version === 'string' && entry.version) data.version = entry.version;

      // Session name — several record types carry it across Claude Code versions.
      const nameCandidate =
        entry.type === 'ai-title' || entry.type === 'custom-title'
          ? entry.title ?? entry.customTitle ?? entry.content
          : entry.customTitle ?? entry.slug;
      const cleanedName = cleanName(nameCandidate);
      if (cleanedName) data.sessionName = cleanedName;

      const ts = entry.timestamp;
      if (entry.type === 'assistant' && ts) {
        if (!data.startedAt) data.startedAt = ts;
        data.lastActivityAt = ts;
        if (entry.message?.model) data.model = entry.message.model;
      } else if (ts && !data.startedAt && entry.type === 'user') {
        data.startedAt = ts;
      }

      // Token accumulation with dual-logging dedup (Claude Code may write the
      // same API response 2-3x consecutively).
      if (entry.type === 'assistant' && entry.message?.usage) {
        const u = entry.message.usage;
        const key = `${u.input_tokens}|${u.output_tokens}|${u.cache_creation_input_tokens}|${u.cache_read_input_tokens}`;
        if (key !== lastUsageKey) {
          tokens.input += num(u.input_tokens);
          tokens.output += num(u.output_tokens);
          tokens.cacheCreation += num(u.cache_creation_input_tokens);
          tokens.cacheRead += num(u.cache_read_input_tokens);
          // Current context occupancy ≈ this turn's prompt size.
          data.contextTokens =
            num(u.input_tokens) + num(u.cache_read_input_tokens) + num(u.cache_creation_input_tokens);
        }
        lastUsageKey = key;
      } else {
        lastUsageKey = undefined;
      }

      // Background-agent accurate completion time (tool_result fires at launch).
      if (entry.type === 'queue-operation' && entry.operation === 'enqueue' && entry.content && ts) {
        const taskId = entry.content.match(/<task-id>([^<]+)<\/task-id>/);
        const toolUseId = entry.content.match(/<tool-use-id>([^<]+)<\/tool-use-id>/);
        if (taskId && toolUseId) queueCompletion.set(toolUseId[1] as string, ts);
      }

      const content = entry.message?.content;
      if (!Array.isArray(content)) continue;
      const when = ts ?? null;

      for (const block of content) {
        if (block.type === 'tool_use' && block.id && block.name) {
          if (block.name === 'Skill') {
            const s = cleanName(block.input?.skill);
            if (s) skillSet.add(s);
          }
          const mcp = MCP_TOOL_NAME_PATTERN.exec(block.name);
          if (mcp && mcp[1]) {
            const server = cleanName(mcp[1]);
            if (server) mcpSet.add(server);
          }

          if (block.name === 'Task' || block.name === 'Agent') {
            const input = (block.input ?? {}) as Record<string, unknown>;
            agentMap.set(block.id, {
              type: (input.subagent_type as string) ?? 'agent',
              model: (input.model as string) ?? null,
              description: (input.description as string) ?? null,
              status: 'running',
              background: input.run_in_background === true,
              startedAt: when,
              endedAt: null,
            });
          } else if (block.name === 'TodoWrite') {
            const input = block.input as { todos?: TodoItem[] } | undefined;
            if (input?.todos && Array.isArray(input.todos)) {
              todos = input.todos
                .map((t) => ({
                  content: cleanName(t.content) ?? '',
                  status: (normalizeTaskStatus(t.status) as TodoStatus) ?? 'pending',
                }))
                .filter((t) => t.content);
            }
          } else {
            toolMap.set(block.id, {
              name: block.name,
              target: extractTarget(block.name, block.input),
              status: 'running',
              startedAt: when,
              endedAt: null,
            });
          }
        }

        if (block.type === 'tool_result' && block.tool_use_id) {
          const tool = toolMap.get(block.tool_use_id);
          if (tool) {
            tool.status = block.is_error ? 'error' : 'completed';
            tool.endedAt = when;
          }
          const agent = agentMap.get(block.tool_use_id);
          if (agent && !agent.background) agent.endedAt = when;
        }
      }
    }
  } catch {
    // Return whatever we accumulated so far.
  }

  // Resolve agent completion: prefer queue-operation timestamps (background),
  // fall back to tool_result endedAt (inline).
  for (const [toolUseId, endedAt] of queueCompletion) {
    const agent = agentMap.get(toolUseId);
    if (agent?.background) {
      agent.endedAt = endedAt;
      agent.status = 'completed';
    }
  }
  for (const agent of agentMap.values()) {
    if (agent.status === 'running' && agent.endedAt) agent.status = 'completed';
  }

  tokens.total = tokens.input + tokens.output + tokens.cacheCreation + tokens.cacheRead;
  data.tools = Array.from(toolMap.values()).slice(-20);
  data.agents = Array.from(agentMap.values()).slice(-10);
  data.todos = todos;
  data.skills = Array.from(skillSet);
  data.mcpServers = Array.from(mcpSet);
  data.sessionTokens = tokens;

  cache.set(transcriptPath, { mtimeMs: stat.mtimeMs, size: stat.size, data });
  return data;
}

// Resolve the project transcript directory for a cwd. Claude Code stores
// transcripts under ~/.claude/projects/<slugified-cwd>/<session-id>.jsonl.
export function projectTranscriptDir(homeDir: string, cwd: string): string {
  const slug = cwd.replace(/[^A-Za-z0-9]/g, '-');
  return `${homeDir}/.claude/projects/${slug}`;
}

export function findTranscript(
  homeDir: string,
  opts: { cwd?: string; sessionId?: string; transcriptPath?: string },
): string | null {
  if (opts.transcriptPath && fs.existsSync(opts.transcriptPath)) return opts.transcriptPath;

  const cwd = opts.cwd ?? process.cwd();
  const dir = projectTranscriptDir(homeDir, cwd);
  let files: string[];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl'));
  } catch {
    return null;
  }
  if (opts.sessionId) {
    const match = files.find((f) => f === `${opts.sessionId}.jsonl`);
    return match ? `${dir}/${match}` : null;
  }
  // Newest by mtime.
  let newest: { path: string; mtimeMs: number } | null = null;
  for (const f of files) {
    const p = `${dir}/${f}`;
    try {
      const m = fs.statSync(p).mtimeMs;
      if (!newest || m > newest.mtimeMs) newest = { path: p, mtimeMs: m };
    } catch {
      /* skip */
    }
  }
  return newest?.path ?? null;
}
