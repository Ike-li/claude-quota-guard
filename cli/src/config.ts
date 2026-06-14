// Reads the user's quota-guard settings.json for CLI dashboard display defaults.
// The bash side (lib/load-config.sh) is authoritative for hook behavior; this
// only supplies `watch` defaults (refresh interval, sparklines). CLI flags still
// override. Missing/invalid config is non-fatal — we return an empty object.

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

export interface CliConfig {
  intervalMs?: number;
  showSparklines?: boolean;
}

// Mirrors the bash side: ${CLAUDE_CONFIG_DIR:-~/.claude}/quota-guard/settings.json
export function configPath(): string {
  const dir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  return path.join(dir, 'quota-guard', 'settings.json');
}

export function loadCliConfig(file: string = configPath()): CliConfig {
  let raw: unknown;
  try {
    raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
  const tui = (raw as { display?: { tui?: Record<string, unknown> } })?.display?.tui ?? {};
  const cfg: CliConfig = {};
  if (typeof tui.refreshInterval === 'number' && tui.refreshInterval >= 250) {
    cfg.intervalMs = tui.refreshInterval;
  }
  if (typeof tui.showSparklines === 'boolean') {
    cfg.showSparklines = tui.showSparklines;
  }
  return cfg;
}
