// Shared data model for the claude-quota-guard dashboard + query interface.
//
// `HudState` is the single contract that the aggregation layer produces and
// that both `query` (JSON/text) and `watch` (TUI) consume. External callers
// (claude -p / SDK apps) depend on the JSON shape — see SCHEMA.md. Bump
// HUD_SCHEMA_VERSION on any breaking change to that shape.

export const HUD_SCHEMA_VERSION = 1;

export type ToolStatus = 'running' | 'completed' | 'error';
export type AgentStatus = 'running' | 'completed';
export type TodoStatus = 'pending' | 'in_progress' | 'completed';

export interface TodoItem {
  content: string;
  status: TodoStatus;
}

export interface AgentItem {
  type: string;
  model: string | null;
  description: string | null;
  status: AgentStatus;
  background: boolean;
  startedAt: string | null;
  endedAt: string | null;
}

export interface ToolItem {
  name: string;
  target: string | null;
  status: ToolStatus;
  startedAt: string | null;
  endedAt: string | null;
}

export interface ToolStat {
  name: string;
  count: number;
  errors: number;
}

export interface ErrorItem {
  tool: string;
  message: string;
  timestamp: string | null;
}

export interface ErrorSummary {
  totalErrors: number;
  totalWarnings: number; // reserved for future (transcript doesn't have warnings yet)
  recent: ErrorItem[]; // last 5-10 errors
}

export interface TrendSample {
  tokens: number; // cumulative tokens at this segment
  costUsd: number; // cumulative cost at this segment
}

export interface SessionTokenUsage {
  input: number;
  output: number;
  cacheCreation: number;
  cacheRead: number;
  total: number;
}

// Per-model token split. A session may mix models (main agent + subagents, or a
// plan-mode model) — costing the summed tokens at one blanket rate misprices
// such sessions, so we keep the tokens bucketed by the model that produced them.
export interface ModelTokenBucket {
  model: string;
  usage: SessionTokenUsage;
}

// A token bucket with its own cost estimate (null when the model is unpriceable).
export interface ModelCostBucket extends ModelTokenBucket {
  costUsd: number | null;
}

// Raw extract from a transcript JSONL — produced by transcript.ts, before
// aggregation merges in snapshot data.
export interface TranscriptData {
  sessionId: string | null;
  sessionName: string | null;
  cwd: string | null;
  gitBranch: string | null;
  version: string | null;
  model: string | null;
  startedAt: string | null;
  lastActivityAt: string | null;
  tools: ToolItem[];
  agents: AgentItem[];
  todos: TodoItem[];
  skills: string[];
  mcpServers: string[];
  sessionTokens: SessionTokenUsage;
  // Same tokens, split by producing model. Sums to sessionTokens for the
  // model-tagged turns (every assistant API response carries a model).
  tokensByModel: ModelTokenBucket[];
  // Best-effort current context occupancy, in tokens: the most recent
  // assistant turn's prompt size (input + cache_read + cache_creation).
  contextTokens: number | null;
  // Conversation turns count (assistant messages, deduplicated).
  turns: number;
  // API call statistics (approximate: turns = successful calls, tool errors ≈ failures).
  apiCalls: {
    total: number; // = turns (each assistant message = 1 API call)
    errors: number; // tool errors (not true API errors like rate limits)
  };
  // Tool usage statistics: top tools by call count.
  toolStats: ToolStat[];
  // Error summary: total count and recent errors.
  errorSummary: ErrorSummary;
  // Trend samples: 5-segment sampling of token/cost progression.
  trend: TrendSample[];
}

// Quota numbers sourced from the bash side's snapshot/export — may be absent
// (headless with no prior interactive session) or stale (flagged via age).
export interface QuotaState {
  source: 'snapshot' | 'export' | 'none';
  ageSeconds: number | null;
  stale: boolean;
  fiveHour: { usedPercent: number | null; resetsIn: string | null };
  sevenDay: { usedPercent: number | null; resetsIn: string | null };
  fiveHourProjectedPercent: number | null;
}

export interface ContextState {
  usedPercent: number | null;
  source: 'snapshot' | 'transcript' | 'none';
  tokens: number | null;
  windowSize: number | null;
}

export interface HudState {
  schemaVersion: number;
  generatedAt: string;
  session: {
    id: string | null;
    name: string | null;
    cwd: string | null;
    gitBranch: string | null;
    version: string | null;
    model: string | null;
    providerDomain: string | null; // extracted from .claude/settings.local.json ANTHROPIC_BASE_URL
    transcriptPath: string | null;
    startedAt: string | null;
    lastActivityAt: string | null;
    turns: number | null;
  };
  quota: QuotaState;
  context: ContextState;
  activity: {
    todos: {
      total: number;
      completed: number;
      inProgress: number;
      pending: number;
      items: TodoItem[];
    };
    agents: { running: number; total: number; items: AgentItem[] };
    recentTools: ToolItem[];
    toolStats: ToolStat[]; // Top 5 tools by call count
    errorSummary: ErrorSummary;
    skills: string[];
    mcpServers: string[];
  };
  usage: {
    sessionTokens: SessionTokenUsage;
    estimatedCostUsd: number | null;
    costSource: 'estimate' | 'none';
    // Per-model cost breakdown. estimatedCostUsd is the sum of these (null if any
    // token-bearing bucket is unpriceable). Empty when no tokens/models seen.
    tokensByModel: ModelCostBucket[];
    // API call statistics (approximate).
    apiCalls: {
      total: number; // = conversation turns (each assistant message = 1 API call)
      errors: number; // tool errors (proxy for failures; true API errors not in transcript)
    };
    // Cache savings: 0.9× input cost for cache_read tokens (read at 0.1× vs 1.0× fresh input).
    cacheSavingsUsd: number | null;
    // Trend: 5-segment sampling of cumulative token/cost progression.
    trend: TrendSample[];
  };
}
