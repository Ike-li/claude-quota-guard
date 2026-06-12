# `quota-guard query --json` — data contract (`HudState`)

External consumers (`claude -p` / SDK agents / other tools) should depend on this
shape. `schemaVersion` is bumped on any breaking change. Source of truth:
`cli/src/types.ts`.

```jsonc
{
  "schemaVersion": 1,
  "generatedAt": "2026-06-12T17:00:00.000Z",   // ISO, when the query ran

  "session": {
    "id":             "…",      // session id (null if unknown)
    "name":           "…",      // ai-title / custom title (null)
    "cwd":            "/path",  // project dir (null)
    "gitBranch":      "main",   // null
    "version":        "2.1.x",  // Claude Code version (null)
    "model":          "claude-opus-4-8",  // null
    "transcriptPath": "/…/<id>.jsonl",    // null if not found
    "startedAt":      "ISO|null",
    "lastActivityAt": "ISO|null"          // last assistant reply time
  },

  // Subscription rate limits. SOURCE = the bash snapshot only (statusLine hook).
  // Per-session strict (mirrors guard.sh): when a session id is known, ONLY that
  // session's snapshot file is read — never the shared global one, which any
  // concurrent session may have overwritten (cross-talk). No per-session file
  // (e.g. pure headless claude -p) → source "none", numbers null. Omit --session
  // (and run without a resolvable transcript session) to read the global
  // last-writer view instead. When present it may be stale (see age).
  "quota": {
    "source":   "snapshot" | "none",
    "ageSeconds": 3 | null,        // snapshot age; null when source is none
    "stale":    false,             // true once age > --stale (default 60s)
    "fiveHour": { "usedPercent": 42 | null, "resetsIn": "3h" | null },
    "sevenDay": { "usedPercent": 34 | null, "resetsIn": "5d" | null },
    "fiveHourProjectedPercent": 142 | null   // burn-rate projection at reset
  },

  // Context window occupancy.
  //  - source "snapshot":   % is Claude Code's authoritative figure (real window,
  //                         possibly 1M). windowSize is null (true size unknown);
  //                         tokens is the last turn's prompt size, best-effort.
  //  - source "transcript": % = tokens / windowSize, where windowSize is the
  //                         --window assumption (default 200000). May over-report
  //                         for 1M-context models — pass --window 1000000.
  //  - source "none":       no data.
  "context": {
    "usedPercent": 29 | null,
    "source":      "snapshot" | "transcript" | "none",
    "tokens":      287070 | null,
    "windowSize":  200000 | null
  },

  // Live session activity — always available from the transcript (incl. headless).
  "activity": {
    "todos": {
      "total": 3, "completed": 1, "inProgress": 1, "pending": 1,
      "items": [ { "content": "…", "status": "pending|in_progress|completed" } ]
    },
    "agents": {
      "running": 1, "total": 4,
      "items": [ {
        "type": "Explore", "model": null, "description": "…",
        "status": "running|completed", "background": true,
        "startedAt": "ISO|null", "endedAt": "ISO|null"
      } ]
    },
    "recentTools": [ {                  // last 20, oldest→newest
      "name": "Bash", "target": "npm run build…",
      "status": "running|completed|error",
      "startedAt": "ISO|null", "endedAt": "ISO|null"
    } ],
    "skills":     [ "deep-research" ],
    "mcpServers": [ "computer-use" ]
  },

  "usage": {
    "sessionTokens": {                  // cumulative, dual-logging deduped
      "input": 9100, "output": 167600,
      "cacheCreation": 0, "cacheRead": 16700000, "total": 16876700
    },
    "estimatedCostUsd": 47.03 | null,   // token-derived; null for unknown models
    "costSource": "estimate" | "none"
  }
}
```

## Usage from an external app

```bash
# shell out and parse (any language)
state=$(quota-guard query --json --session "$SESSION_ID")
echo "$state" | jq -r '.context.usedPercent'

# pick a specific project / transcript explicitly
quota-guard query --json --cwd /path/to/repo
quota-guard query --json --transcript /path/to/<id>.jsonl
```

Exit code is 0 on success; the object is always emitted (fields null when absent),
so consumers branch on `source` / null rather than on errors.
