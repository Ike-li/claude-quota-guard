# Roadmap

Future enhancements planned for Claude Quota Guard.

## Phase C: Functionality Enhancement (1 month)

### Session History Analysis
**Status**: Planned

**Description**: Track and analyze quota/context usage across multiple sessions.

**Features**:
- `quota-guard history` - List past sessions with usage stats
- `quota-guard compare <id1> <id2>` - Compare two sessions
- `quota-guard stats` - Aggregate statistics (avg cost, peak usage, etc.)
- Session database in SQLite or JSON

**Why**: Understand usage patterns, identify expensive sessions, optimize workflows.

### Burn-Rate Projection
**Status**: Planned

**Description**: Predict when quota will be exhausted at current pace.

**Features**:
- Show "X minutes remaining at current pace"
- Alert earlier if burn rate is high
- Display in statusline: `5h 28% (→85% in 2h)`

**Why**: Proactive warning before hitting limits.

### Custom Convergence Templates
**Status**: Planned

**Description**: User-defined handoff templates for different scenarios.

**Features**:
- YAML template format
- Variables: `{task}`, `{progress}`, `{files}`, `{next_step}`
- Multiple templates: `refactor.yaml`, `bugfix.yaml`, `feature.yaml`
- Select template: `CQG_TEMPLATE=refactor` in config

**Why**: Different tasks need different handoff styles.

**Example**:
```yaml
# ~/.claude/quota-guard/templates/refactor.yaml
name: refactor
description: Multi-file refactoring handoff

prompt: |
  Continue refactoring {task}.
  
  Completed:
  {completed_files}
  
  Next:
  {next_files}
  
  Pattern: {refactor_pattern}
```

## Phase D: Ecosystem Expansion (Future)

### Web Dashboard
**Status**: Idea

**Description**: Browser-based dashboard for detailed analytics.

**Features**:
- Real-time session monitoring (WebSocket)
- Historical charts (Chart.js)
- Session comparison UI
- Export reports (CSV/PDF)

**Tech**: Node.js + Express + WebSocket, static HTML/CSS/JS

### VS Code Extension
**Status**: Idea

**Description**: Display quota/context in VS Code sidebar.

**Features**:
- Status bar item showing quota %
- Sidebar panel with detailed view
- Alerts when nearing limits
- One-click handoff generation

**Tech**: VS Code Extension API

### Slack/Discord Notifications
**Status**: Idea

**Description**: Send alerts to team chat when quota low.

**Features**:
- Webhook integration
- Configurable alert thresholds
- Include session link and handoff prompt
- Team-wide quota monitoring

**Config**:
```json
{
  "notifications": {
    "slack": {
      "enabled": true,
      "webhook": "https://hooks.slack.com/...",
      "threshold": 80
    }
  }
}
```

### Quota Pooling (Multi-User)
**Status**: Idea

**Description**: Share quota monitoring across team members.

**Features**:
- Central server tracks team quota usage
- Each user reports local usage
- Alert when team aggregate nears limit
- Fair-use policies (per-user caps)

**Why**: Enterprise teams sharing one API key.

### AI-Powered Convergence
**Status**: Idea

**Description**: Model predicts optimal convergence point based on task type.

**Features**:
- ML model trained on past handoffs
- Predicts "good stopping points" in code
- Suggests convergence before natural break points
- Adaptive thresholds per task type

**Tech**: Small ML model (scikit-learn or ONNX)

## Phase E: Performance & Scale

### Rust Rewrite (CLI)
**Status**: Idea

**Description**: Rewrite CLI in Rust for faster transcript parsing.

**Benefits**:
- 10-100× faster (like ndave92/claude-code-status-line)
- Single binary distribution
- Lower memory usage

**Trade-offs**:
- More complex build
- Harder to contribute for non-Rust devs

### Database Backend
**Status**: Idea

**Description**: Replace JSONL transcript parsing with SQLite index.

**Features**:
- One-time JSONL→SQLite import
- Incremental updates on each turn
- Fast queries (no full file scan)
- Historical session storage

**Why**: JSONL parsing becomes slow at 10MB+ transcripts.

## Completed Features

### ✅ Phase A: Distribution Optimization (Done)
- Plugin structure (`plugin.json`)
- Skill commands (`/quota-guard`)
- One-line install

### ✅ Phase B: Configuration Modernization (Done)
- JSON configuration (`settings.json`)
- Theme system (6 themes)
- Responsive layout
- Preset system (minimal/compact/full)

### ✅ Phase 2: Medium-Priority Features (Done)
- API statistics (call count, errors)
- Cache savings estimate
- Tool top-5 statistics

### ✅ Phase 3: Low-Priority Features (Done)
- Error summary aggregation
- Trend sparklines (ASCII)
- Git ahead/behind/stash

## Contributing Ideas

Have an idea? Open an issue or PR!

Categories:
- 🛡️ **Safety** - Better convergence, more robust detection
- 📊 **Analytics** - New metrics, visualizations
- 🎨 **UX** - Themes, layouts, customization
- 🔧 **Performance** - Faster parsing, lower overhead
- 🌐 **Integration** - IDE plugins, team tools

## Prioritization Criteria

Features are prioritized by:
1. **User impact** - How many users benefit?
2. **Complexity** - Implementation cost vs. value
3. **Maintenance** - Long-term support burden
4. **Uniqueness** - Does another tool already do this?

Phase A/B are high-priority (distribution & config). Phase C is medium (useful enhancements). Phase D/E are low (nice-to-have ecosystem).
