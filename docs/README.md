# Documentation Index

Complete guide to Claude Quota Guard.

---

## For New Users

Start here if this is your first time:

1. **[README](../README.md)** - What is this? (2 min read)
2. **[Getting Started](getting-started.md)** - Install and verify (5 min tutorial)
3. **[Troubleshooting](troubleshooting.md)** - Common issues (reference)

---

## Documentation Map

### User Documentation

| Document | Purpose | When to read |
|----------|---------|--------------|
| [README](../README.md) | Project overview, quick start | First visit |
| [Getting Started](getting-started.md) | Complete installation tutorial | Setting up |
| [Troubleshooting](troubleshooting.md) | Solutions to common issues | When stuck |
| [CHANGELOG](../CHANGELOG.md) | Version history | Before updating |

### Reference

| Document | Purpose |
|----------|---------|
| [Skill Documentation](../skill/SKILL.md) | Skill command reference |
| [CLI Schema](../cli/SCHEMA.md) | JSON output format (for external tools) |

### Planning

| Document | Purpose |
|----------|---------|
| [ROADMAP](ROADMAP.md) | Future features (Phase C/D/E) |

### Developer Documentation

Coming soon:
- `architecture.md` - How it works (technical deep-dive)
- `contributing.md` - Development setup and guidelines
- `user-guide.md` - Complete command and config reference

---

## Quick Links

**Installation**
```bash
git clone https://github.com/raylee/claude-quota-guard ~/.claude/skills/quota-guard
cd ~/.claude/skills/quota-guard
/quota-guard setup
```

**Diagnosis**
```bash
/quota-guard doctor
```

**Help**
```bash
/quota-guard help
```

**Issues**  
https://github.com/raylee/claude-quota-guard/issues

---

## Documentation Principles

Our docs follow these rules:

1. **Concise** - Get to the point in 30 seconds
2. **Verifiable** - Every claim includes a command to test it
3. **Honest** - If something doesn't work, we say so
4. **Layered** - Quick start → Tutorial → Reference → Deep dive

**Found an error?** Open an issue or PR.

---

## Document Status

| Document | Status | Last Updated |
|----------|--------|--------------|
| README | ✅ Stable | 2024-06-13 |
| Getting Started | ✅ Stable | 2024-06-13 |
| Troubleshooting | ✅ Stable | 2024-06-13 |
| CHANGELOG | ✅ Stable | 2024-06-13 |
| ROADMAP | ✅ Stable | 2024-06-13 |
| Architecture | 🚧 Planned | - |
| User Guide | 🚧 Planned | - |
| Contributing | 🚧 Planned | - |

**Legend**:
- ✅ Stable - Complete and reviewed
- 🚧 Planned - Will be added in future release
- ⚠️ Draft - Work in progress
