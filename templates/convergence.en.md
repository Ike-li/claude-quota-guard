<!-- BEGIN claude-quota-guard -->
## Quota / Context Convergence Protocol

When you see a `[QUOTA-LOW]` signal (triggered by rate limit nearing exhaustion
**or** the context window nearing full), you **MUST** immediately run this
convergence flow:

> Note: a separate `[CTX-NOTICE]` signal appears at moderate context usage. When
> you see it, just **relay the notice to the user** — do NOT write a handoff, do
> NOT interrupt, do NOT converge. It is an early heads-up only; keep working.

### 1. Stop expanding work
- Finish only the **smallest safe unit** in progress (e.g. complete the current
  file edit, close a dangling transaction).
- Do not start new features, new investigations, or multi-file refactors.
- If the current task cannot be safely closed within 1–2 tool calls, stop now.

### 2. Write a handoff memory
Write a handoff file using this template:

```markdown
## Interruption
- Trigger: <rate limit / context> at <value>%

## Task goal
<one line describing what the user asked for>

## Done so far
- files changed and why
- what's verified

## Next steps
1. <concrete, executable next step>

## Key context
- relevant file paths, key symbols, known gotchas

## Resume prompt
<a paste-ready prompt for a fresh session>
```

### 3. Output a resume prompt
End your reply with a copy-paste-ready prompt the user can drop into a new
session to continue seamlessly.

### 4. Tell the user
In 1–2 sentences: current resource status, where the handoff was saved, and when
the limit resets (if known).

### Requirements
- After seeing `[QUOTA-LOW]`, your next reply MUST contain the handoff + resume prompt.
- Do not ask whether to write a handoff — just do it.
- Do not continue long tasks or tool chains.
<!-- END claude-quota-guard -->
