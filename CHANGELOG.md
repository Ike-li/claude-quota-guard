# Changelog

All notable changes to Claude Quota Guard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **`install.sh` aborted with a syntax error** — a stray `fi` left from the
  JSON-config migration broke `./install.sh` and `/quota-guard setup` for every
  user. Removed the orphan token; `bash -n install.sh` is now clean.
- **Theme colors printed as literal hex** (`#d08770`, `#5e81ac`, …) instead of
  rendering. Themes define colors as `#RRGGBB`, but `statusline-command.sh`
  treated those theme variables as ANSI escapes — so any loaded theme (including
  the default `catppuccin-mocha`) broke the status line. It now converts theme
  hex to ANSI, honoring terminal color depth; the truecolor → 256 → 16 fallback
  that previously covered only built-in defaults now applies to theme colors too.
- **Status line could blank out entirely** in sessions with no
  effort/thinking/fast indicator: `load-config.sh`'s `set -euo pipefail` leaked
  through `source` into `statusline-command.sh`, where an empty `mode_parts`
  array tripped `set -u`. The renderer now relaxes `errexit`/`nounset`, which it
  was always written to assume.
- **`lib/snapshot.sh` could abort a `set -e` caller when re-sourced** in one
  process: its top-level `readonly CQG_FIVE_HOUR_WINDOW` returns non-zero on the
  second source ("readonly variable"). Made idempotent so a growing source-chain
  can't trip `set -e`. Not currently triggered — hardening found while auditing
  the `set -e`/`source` boundary after the status-line fix.

### Added

- `test/test_statusline.sh` — isolated regression coverage for theme→ANSI
  conversion and color-depth downgrade.

### Documentation

- Removed stale duplicates (`README.md.backup`, `*.old.md`, the redundant
  `docs/README.md` index) and fixed dead cross-links to never-written docs
  (`user-guide.md`, `architecture.md`, `contributing.md`).
- Corrected the configuration story: convergence thresholds live in `config.sh`
  (read by `guard.sh`/`collect.sh`); `settings.json` drives statusline appearance.
- Theme count corrected to the three shipped themes (was listed as six).

---

## [1.0.0] - 2026-06-13

### Added

**Phase A: Distribution**
- Plugin structure (`plugin.json`) for Claude Code plugin system
- Skill entry point with 10 commands: `setup`, `watch`, `query`, `config`, `theme`, `preset`, `doctor`, `clean`, `uninstall`, `help`
- Skill documentation (`skill/SKILL.md`)

**Phase B: Configuration**
- JSON configuration system (`settings.json` + JSON Schema)
- Theme support: catppuccin-mocha (default), cyberpunk, nord
- Preset system: minimal, compact, full
- Responsive layout: auto-adjusts to terminal width (<80, 80-120, >120 cols)
- Element toggles: show/hide context, quota, git, agents, todos, tokens
- Config loader with backward compatibility (JSON takes precedence over `config.sh`)

**Statusline Features**
- Live display: project, git branch, model, context %, quota %, cost, duration
- Provider domain detection (shows third-party API base URLs)
- Catppuccin Mocha color scheme (24-bit truecolor)
- Git status: dirty count, ahead/behind, stash count
- Agent/todo indicators
- Cache usage and TTL display

**CLI Dashboard** (`quota-guard watch`)
- Token/cost stats with per-model breakdown
- API call count and error rate
- Cache savings estimate
- Trend sparklines (5-segment sampling)
- Recent tools (last 20)
- Tool top-5 by call count
- Running agents (live)
- Todo progress
- Error summary (last 10)

**Convergence Protocol**
- Signal injection: `[QUOTA-LOW]` when threshold crossed
- CLAUDE.md protocol: model writes handoff and stops gracefully
- Handoff template with resume prompt
- Language support: English and 中文

**Diagnostics**
- `/quota-guard doctor` with 11 checks:
  - Hook registration (statusLine + UserPromptSubmit)
  - CLI functionality test
  - Snapshot freshness
  - Config JSON validation
  - Terminal color tier detection (truecolor/256/16)
  - Live color rendering test
  - Dependency versions (jq, node, npm)

### Fixed

- Input validation for `theme` and `preset` commands (prevents invalid values in JSON)
- Terminal color compatibility: 3-tier fallback (truecolor → 256-color → 16-color)
- Doctor health check logic (now correctly reports "Installation looks healthy!")
- Suspicious-zero guard: skip snapshot write when context=0 but session is live
- Per-session snapshot isolation: prevent cross-talk between sessions

### Changed

- Install script now creates JSON config (backward compatible with `config.sh`)
- Statusline colors load from theme files (extensible)
- CLI pricing uses per-model rates (accurate for mixed-model sessions)

### Documentation

- Complete rewrite of README.md (concise, 30-second decision format)
- New: `docs/getting-started.md` (5-minute tutorial)
- New: `docs/troubleshooting.md` (consolidated common issues)
- New: `docs/ROADMAP.md` (future features: Phase C/D/E)

---

## [0.1.0] - 2026-06-12 (Initial Development)

### Added

**Core Monitoring**
- `collect.sh`: statusLine hook, extracts quota/context, writes snapshot every 10s
- `guard.sh`: UserPromptSubmit hook, reads snapshot, injects signal on threshold
- Snapshot format: tab-separated (5h%, 7d%, 5h_proj%, resets, ctx%, agents, todos)
- Per-session snapshots: prevent session cross-talk
- Snapshot sweep: auto-cleanup of abandoned sessions (1-in-100 writes, 7-day TTL)

**Architecture**
- Decoupled design: live data (collect) ← snapshot bridge → logic (guard) → static rules (CLAUDE.md)
- Mode detection: `auto` (detects subscription vs relay), `subscription`, `relay`
- Activity tracking: agents_running, todos_pending (via CLI `_activity` command)
- Burn-rate projection: predicts quota % at window reset

**Configuration**
- `config.sh`: thresholds (ctxNotice 50%, ctxHalt 85%, rateHalt 85%)
- Language support: en/zh signal text
- Wrap mode: forwards stdin to existing statusLine
- Export bridge: opt-in JSON export for external tools
- Logging: structured log with rotation (100 KB → .log.1)

**CLI** (`bin/quota-guard`)
- `query`: one-shot text/JSON output
- `watch`: live TUI dashboard (no dependencies beyond Node.js built-ins)
- Transcript parser: tools, agents, todos, skills, MCP servers, tokens
- Cost estimation: per-MTok pricing table
- In-memory cache: (path, mtime, size) key for fast watch loop

**Testing**
- `test/test_guard.sh`: isolated temp dir, synthetic snapshots, signal assertions
- No side effects on real `~/.claude/` files

### Technical

- Bash implementation: light weight, minimal dependencies
- Node.js CLI: for human-friendly dashboard
- jq: JSON parsing in hooks
- Git integration: branch, dirty count (5s cache)
- Platform support: macOS (BSD stat), Linux (GNU stat)

---

## Upcoming (See [ROADMAP.md](docs/ROADMAP.md))

### Phase C: Functionality Enhancement (1 month)
- Session history analysis
- Burn-rate prediction ("X minutes remaining")
- Custom convergence templates (YAML)

### Phase D: Ecosystem Expansion (Future)
- Web dashboard (browser-based)
- VS Code extension (sidebar panel)
- Slack/Discord notifications
- Team quota pooling

### Phase E: Performance & Scale (Future)
- Rust CLI rewrite (10-100× faster)
- SQLite backend (fast queries on large transcripts)

---

## Links

- **Repository**: https://github.com/Ike-li/claude-quota-guard
- **Issues**: https://github.com/Ike-li/claude-quota-guard/issues
- **Discussions**: https://github.com/Ike-li/claude-quota-guard/discussions

---

## Version Scheme

Given a version number MAJOR.MINOR.PATCH:

- **MAJOR**: Incompatible API/config changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

Pre-1.0.0 versions may break backward compatibility in MINOR releases.
