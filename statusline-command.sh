#!/usr/bin/env bash
# Claude Code statusLine command
# Style: Starship + Catppuccin Mocha inspired. Human-friendly, responsive layout.

# Source shared snapshot logic and config
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib/snapshot.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib/load-config.sh"

# load-config.sh runs `set -euo pipefail`; sourcing it leaks those options into
# this script. This is a display renderer that must tolerate missing JSON
# fields, empty arrays (no effort/thinking → empty mode_parts), and failing
# subcommands (git/jq/tput). Relax errexit+nounset so one empty value can never
# blank the entire status line.
set +eu

input=$(cat)

# Terminal width detection
TERM_WIDTH="${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}"

# Apply preset if configured
case "${CQG_STATUSLINE_PRESET:-full}" in
  minimal)
    CQG_SHOW_GIT="false"
    CQG_SHOW_AGENTS="false"
    CQG_SHOW_TODOS="false"
    CQG_SHOW_TOKENS="false"
    ;;
  compact)
    # Single line mode - will be handled below
    ;;
  full|*)
    # Use element toggles from config
    ;;
esac

# Responsive layout: auto-downgrade on narrow terminals
if [ "${CQG_STATUSLINE_RESPONSIVE:-true}" = "true" ]; then
  if [ "$TERM_WIDTH" -lt 80 ]; then
    CQG_STATUSLINE_PRESET="minimal"
    CQG_SHOW_GIT="false"
    CQG_SHOW_AGENTS="false"
    CQG_SHOW_TODOS="false"
    CQG_SHOW_TOKENS="false"
  elif [ "$TERM_WIDTH" -lt 120 ]; then
    CQG_SHOW_TOKENS="false"
  fi
fi

# ── Theme colors ───────────────────────────────────────────────────────
# Themes (themes/*.sh, sourced by load-config.sh) define colors as readable
# #RRGGBB hex. The status line needs ANSI escapes, so convert here — honoring
# terminal color depth so a theme degrades gracefully on 256/16-color terminals
# instead of having its raw hex printed literally. Built-in defaults mirror the
# default catppuccin-mocha theme, so the look is identical when no theme loads.
case "$COLORTERM" in
  truecolor|24bit) COLOR_DEPTH=truecolor ;;
  *) case "$TERM" in
       *256color*) COLOR_DEPTH=256 ;;
       *)          COLOR_DEPTH=16 ;;
     esac ;;
esac

# hex_to_ansi "#RRGGBB" → literal `\033[...m` SGR foreground for $COLOR_DEPTH.
# Emits the literal backslash-033 form (not a raw ESC) so the existing
# `printf '%b'` call sites render it. Non-hex input is passed through unchanged.
hex_to_ansi() {
  local hex="${1#\#}"
  case "$hex" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
    *) printf '%s' "$1"; return ;;
  esac
  local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
  case "$COLOR_DEPTH" in
    truecolor)
      printf '\\033[38;2;%d;%d;%dm' "$r" "$g" "$b" ;;
    256)
      # 6×6×6 color cube + grayscale ramp (xterm-256 standard)
      local idx
      if [ "$r" -eq "$g" ] && [ "$g" -eq "$b" ]; then
        if   [ "$r" -lt 8 ];   then idx=16
        elif [ "$r" -gt 248 ]; then idx=231
        else idx=$(( 232 + (r - 8) * 24 / 247 )); fi
      else
        idx=$(( 16 + 36*(r*5/255) + 6*(g*5/255) + (b*5/255) ))
      fi
      printf '\\033[38;5;%dm' "$idx" ;;
    *)
      # nearest basic 16 ANSI: per-channel threshold, brighten if any channel high
      local mx=$r; [ "$g" -gt "$mx" ] && mx=$g; [ "$b" -gt "$mx" ] && mx=$b
      local base=0
      [ "$r" -ge 128 ] && base=$((base+1))
      [ "$g" -ge 128 ] && base=$((base+2))
      [ "$b" -ge 128 ] && base=$((base+4))
      if [ "$mx" -ge 192 ]; then printf '\\033[%dm' "$((90+base))"
      else                       printf '\\033[%dm' "$((30+base))"; fi ;;
  esac
}

RED=$(hex_to_ansi      "${CQG_THEME_RED:-#f38ba8}")
PEACH=$(hex_to_ansi    "${CQG_THEME_PEACH:-#fab387}")
YELLOW=$(hex_to_ansi   "${CQG_THEME_YELLOW:-#f9e2af}")
GREEN=$(hex_to_ansi    "${CQG_THEME_GREEN:-#a6e3a1}")
SAPPHIRE=$(hex_to_ansi "${CQG_THEME_SAPPHIRE:-#74c7ec}")
MAUVE=$(hex_to_ansi    "${CQG_THEME_MAUVE:-#cba6f7}")
SKY=$(hex_to_ansi      "${CQG_THEME_SKY:-#89dceb}")
ROSE=$(hex_to_ansi     "${CQG_THEME_PINK:-#f5c2e7}")
GOLD=$(hex_to_ansi     "${CQG_THEME_YELLOW:-#f9e2af}")
SUBTEXT=$(hex_to_ansi  "${CQG_THEME_SUBTEXT1:-#bac2de}")
DIM=$(hex_to_ansi      "${CQG_THEME_OVERLAY0:-#6c7086}")
RESET="\033[0m"

# Color a percentage by threshold.
#   $1 = int value, $2 = direction: high_bad (ctx/limits) | high_good (cache)
tier_color() {
  local v="$1" dir="$2"
  [ "$v" -eq "$v" ] 2>/dev/null || { printf '%b' "$SUBTEXT"; return; }
  if [ "$dir" = "high_good" ]; then
    if [ "$v" -lt 50 ]; then printf '%b' "$RED"
    elif [ "$v" -lt 80 ]; then printf '%b' "$YELLOW"
    else printf '%b' "$GREEN"; fi
  else
    if [ "$v" -ge 80 ]; then printf '%b' "$RED"
    elif [ "$v" -ge 50 ]; then printf '%b' "$YELLOW"
    else printf '%b' "$GREEN"; fi
  fi
}

jqr() {
  jq -r "$1" <<<"$input"
}

nonnull() {
  [ -n "$1" ] && [ "$1" != "null" ]
}

fmt_num() {
  awk -v n="$1" 'BEGIN {
    if (n == "" || n == "null") exit
    if (n >= 1000000) printf "%.1fm", n / 1000000
    else if (n >= 1000) printf "%.1fk", n / 1000
    else printf "%.0f", n
  }' | sed -E 's/\.0([km])$/\1/'
}

fmt_cost() {
  awk -v c="$1" 'BEGIN { if (c == "" || c == "null") exit; printf "$%.2f", c }'
}

fmt_duration_ms() {
  awk -v ms="$1" 'BEGIN {
    if (ms == "" || ms == "null" || ms <= 0) exit
    sec = int(ms / 1000)
    h = int(sec / 3600)
    m = int((sec % 3600) / 60)
    s = sec % 60
    if (h > 0) printf "%dh%02dm", h, m
    else if (m > 0) printf "%dm%02ds", m, s
    else printf "%ds", s
  }'
}


seg() {
  local color="$1"
  local text="$2"
  nonnull "$text" || return 0
  printf '%b%s%b' "$color" "$text" "$RESET"
}

join_segments() {
  local out="" part
  for part in "$@"; do
    nonnull "$part" || continue
    if [ -n "$out" ]; then
      out="${out}${DIM} · ${RESET}${part}"
    else
      out="$part"
    fi
  done
  printf '%b' "$out"
}

# ---- extract fields ----
cwd=$(jqr '.workspace.current_dir // .cwd // empty')
[ -n "$cwd" ] || cwd="$PWD"
model=$(jqr '.model.display_name // .model.id // empty')
session_id=$(jqr '.session_id // empty')
session_id=$(cqg_sanitize_session_id "$session_id")
session_name=$(jqr '.session_name // empty')
version=$(jqr '.version // empty')
output_style=$(jqr '.output_style.name // empty')
repo_owner=$(jqr '.workspace.repo.owner // empty')
repo_name=$(jqr '.workspace.repo.name // empty')

used=$(jqr '.context_window.used_percentage // empty')
window_size=$(jqr '.context_window.context_window_size // empty')
total_input=$(jqr '.context_window.total_input_tokens // empty')
input_tokens=$(jqr '.context_window.current_usage.input_tokens // empty')
cache_create=$(jqr '.context_window.current_usage.cache_creation_input_tokens // empty')
cache_read=$(jqr '.context_window.current_usage.cache_read_input_tokens // empty')
exceeds_200k=$(jqr '.exceeds_200k_tokens // empty')

five_h=$(jqr '.rate_limits.five_hour.used_percentage // empty')
five_h_reset=$(jqr '.rate_limits.five_hour.resets_at // empty')
seven_d=$(jqr '.rate_limits.seven_day.used_percentage // empty')
seven_d_reset=$(jqr '.rate_limits.seven_day.resets_at // empty')

effort=$(jqr '.effort.level // empty')
thinking=$(jqr '.thinking.enabled // empty')
fast_mode=$(jqr '.fast_mode // empty')
vim_mode=$(jqr '.vim.mode // empty')
agent_name=$(jqr '.agent.name // empty')
pr_number=$(jqr '.pr.number // empty')
pr_state=$(jqr '.pr.review_state // empty')
worktree_name=$(jqr '.worktree.name // .workspace.git_worktree // empty')

cost_usd=$(jqr '.cost.total_cost_usd // empty')
duration_ms=$(jqr '.cost.total_duration_ms // empty')
api_duration_ms=$(jqr '.cost.total_api_duration_ms // empty')
lines_added=$(jqr '.cost.total_lines_added // empty')
lines_removed=$(jqr '.cost.total_lines_removed // empty')

time_str=$(date "+%H:%M")

project_name="${cwd%/}"
project_name="${project_name##*/}"
[ -n "$project_name" ] || project_name="$cwd"

# ---- git ----
git_branch=""
git_changed=""
git_ahead=""
git_behind=""
git_stash=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>/dev/null; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  cache_key=$(printf '%s-%s' "${session_id:-statusline}" "$cwd" | tr -c 'A-Za-z0-9_.-' '_')
  git_cache="${TMPDIR:-/tmp}/claude-statusline-git-${cache_key}"
  cache_age=0
  if [ -f "$git_cache" ]; then
    cache_mtime=$(stat -f %m "$git_cache" 2>/dev/null || stat -c %Y "$git_cache" 2>/dev/null || echo 0)
    cache_age=$(($(date +%s) - cache_mtime))
  fi

  if [ ! -f "$git_cache" ] || [ "$cache_age" -gt 5 ]; then
    git_status=$(git -C "$cwd" status --short 2>/dev/null)
    changed=$(printf '%s\n' "$git_status" | sed '/^$/d' | wc -l | tr -d ' ')

    # ahead/behind vs upstream
    ahead=""
    behind=""
    upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{u} 2>/dev/null)
    if [ -n "$upstream" ]; then
      ahead=$(git -C "$cwd" rev-list --count HEAD...$upstream 2>/dev/null || echo 0)
      behind=$(git -C "$cwd" rev-list --count $upstream...HEAD 2>/dev/null || echo 0)
    fi

    # stash count
    stash=$(git -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')

    # write to cache: changed|ahead|behind|stash
    printf '%s|%s|%s|%s' "$changed" "$ahead" "$behind" "$stash" >"$git_cache"
  fi

  # read from cache
  cached=$(cat "$git_cache" 2>/dev/null)
  git_changed=$(printf '%s' "$cached" | cut -d'|' -f1)
  git_ahead=$(printf '%s' "$cached" | cut -d'|' -f2)
  git_behind=$(printf '%s' "$cached" | cut -d'|' -f3)
  git_stash=$(printf '%s' "$cached" | cut -d'|' -f4)
fi

git_str="$git_branch"
if nonnull "$git_str"; then
  git_str=" ${git_str}"
  nonnull "$git_changed" && git_str="${git_str} ✱${git_changed}"
  [ "$git_ahead" -gt 0 ] 2>/dev/null && git_str="${git_str} ↑${git_ahead}"
  [ "$git_behind" -gt 0 ] 2>/dev/null && git_str="${git_str} ↓${git_behind}"
  [ "$git_stash" -gt 0 ] 2>/dev/null && git_str="${git_str} ⚑${git_stash}"
fi

# ---- mode (effort / thinking / fast) ----
mode_parts=()
nonnull "$effort" && mode_parts+=("$effort")
[ "$thinking" = "true" ] && mode_parts+=("thinking")
[ "$fast_mode" = "true" ] && mode_parts+=("fast")
mode_str=""
for part in "${mode_parts[@]}"; do
  mode_str="${mode_str:+$mode_str · }$part"
done

# ---- context (color by usage) ----
ctx_render=""
if nonnull "$used"; then
  used_int=$(printf "%.0f" "$used")
  ctx_render="$(tier_color "$used_int" high_bad)ctx ${used_int}%${RESET}"
fi
[ "$exceeds_200k" = "true" ] && ctx_render="${ctx_render:+$ctx_render }${RED}⚠>200k${RESET}"

# ---- cache hit (color: higher is better) ----
cache_render=""
if nonnull "$cache_read"; then
  cache_total=$(awk -v i="${input_tokens:-0}" -v w="${cache_create:-0}" -v r="${cache_read:-0}" 'BEGIN { printf "%.0f", i + w + r }')
  if [ "$cache_total" -gt 0 ] 2>/dev/null; then
    hit_pct=$(awk -v r="$cache_read" -v t="$cache_total" 'BEGIN { printf "%.0f", (r / t) * 100 }')
    cache_render="$(tier_color "$hit_pct" high_good)cache ${hit_pct}%${RESET}"
  fi
fi

# ---- cache TTL countdown (5-min sliding window) ----
# The cache TTL refreshes on every API call. Track that via the session's cumulative
# api-duration: when it grows, a call just happened -> stamp "now" (reset to ~5m).
# While idle (no api calls) the stamp ages and the countdown ticks toward cold.
# Floored to 10s so it steps in sync with the 10s refreshInterval instead of jittering.
cache_ttl_render=""
if nonnull "$cache_read"; then
  act_key=$(printf '%s' "${session_id:-default}" | tr -c 'A-Za-z0-9_.-' '_')
  act_stamp="${TMPDIR:-/tmp}/claude-cache-active-${act_key}"
  cur_api="${api_duration_ms:-0}"
  prev_api=$(cat "$act_stamp" 2>/dev/null || echo "")
  [ "$cur_api" != "$prev_api" ] && printf '%s' "$cur_api" >"$act_stamp"   # api call -> bump mtime to now
  warm_mtime=$(cqg_stat_mtime "$act_stamp")
  if [ "$warm_mtime" -gt 0 ] 2>/dev/null; then
    ttl_remain=$(( 300 - ($(date +%s) - warm_mtime) ))
    if [ "$ttl_remain" -gt 0 ]; then
      ttl_disp=$(( ttl_remain / 10 * 10 ))
      if   [ "$ttl_disp" -ge 60 ]; then ttl_txt=$(printf '%dm%02ds' "$((ttl_disp / 60))" "$((ttl_disp % 60))")
      elif [ "$ttl_disp" -gt 0 ];  then ttl_txt="${ttl_disp}s"
      else ttl_txt="<10s"; fi
      if   [ "$ttl_remain" -gt 120 ]; then ttl_color="$GREEN"
      elif [ "$ttl_remain" -gt 30  ]; then ttl_color="$YELLOW"
      else ttl_color="$RED"; fi
      cache_ttl_render="${ttl_color}⏳${ttl_txt}${RESET}"
    else
      cache_ttl_render="${DIM}❄cold${RESET}"
    fi
  fi
fi

# ---- rate limits (each colored by usage) ----
rate_render=""
if nonnull "$five_h"; then
  five_int=$(printf "%.0f" "$five_h")
  five_reset=$(cqg_fmt_reset_delta "$five_h_reset")
  rate_render="$(tier_color "$five_int" high_bad)5h ${five_int}%${five_reset:+ ↻${five_reset}}${RESET}"
  # burn-rate projection: at current pace, what % we'll reach by window reset.
  if nonnull "$five_h_reset"; then
    five_proj=$(cqg_five_hour_projection "$five_h" "$five_h_reset")
    nonnull "$five_proj" && rate_render="${rate_render} $(tier_color "$five_proj" high_bad)→${five_proj}%${RESET}"
  fi
fi

# ---- usage history log (throttled to once / 5 min) ----
if nonnull "$five_h" || nonnull "$seven_d"; then
  usage_log="$HOME/.claude/usage-log.tsv"
  usage_stamp="${TMPDIR:-/tmp}/claude-usage-log-stamp"
  log_age=99999
  if [ -f "$usage_stamp" ]; then
    stamp_mtime=$(cqg_stat_mtime "$usage_stamp")
    log_age=$(($(date +%s) - stamp_mtime))
  fi
  if [ "$log_age" -ge 300 ]; then
    [ -f "$usage_log" ] || printf 'time\t5h%%\t7d%%\tproj%%\tmodel\n' >"$usage_log"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(date '+%Y-%m-%d %H:%M')" \
      "${five_h:-}" "${seven_d:-}" "${five_proj:-}" "${model:-}" >>"$usage_log"
    : >"$usage_stamp"
  fi
fi
if nonnull "$seven_d"; then
  seven_int=$(printf "%.0f" "$seven_d")
  seven_reset=$(cqg_fmt_reset_delta "$seven_d_reset")
  seven_render="$(tier_color "$seven_int" high_bad)7d ${seven_int}%${seven_reset:+ ↻${seven_reset}}${RESET}"
  rate_render="${rate_render:+$rate_render${DIM} · ${RESET}}${seven_render}"
fi

# ---- current quota snapshot (unthrottled, for the convergence hook) ----
# Delegates to shared lib/snapshot.sh to ensure consistency with collect.sh.
# statusline-command.sh has no transcript access, so agents/todos are always 0
# (the guard's activity-aware logic only kicks in when collect.sh writes the snapshot).
: "${CQG_SNAPSHOT:=$HOME/.claude/.quota-now}"
cqg_write_snapshot "${five_int:-}" "${seven_int:-}" "${five_proj:-}" "${five_reset:-}" "${seven_reset:-}" "${used_int:-}" \
  "0" "0" "$session_id" || {
  printf 'Warning: Failed to write quota snapshot\n' >&2
}

# ---- read agents/todos from snapshot for display ----
agents_running=0
todos_pending=0
snap_file="${CQG_SNAPSHOT}${session_id:+-$session_id}"
if [ -f "$snap_file" ]; then
  snap_data=$(cat "$snap_file" 2>/dev/null)
  agents_running=$(printf '%s' "$snap_data" | awk -F'\t' '{print $7+0}')
  todos_pending=$(printf '%s' "$snap_data" | awk -F'\t' '{print $8+0}')
fi

# ================= line 1: live status =================
# Conditional rendering based on config
loc_render=""
if [ "${CQG_SHOW_GIT:-true}" = "true" ]; then
  loc_render="${PEACH}📁 ${project_name}${RESET}"
  nonnull "$git_str" && loc_render="${loc_render}${YELLOW}${git_str}${RESET}"
else
  loc_render="${PEACH}📁 ${project_name}${RESET}"
fi

# group: model + mode + provider
model_render=""
nonnull "$model" && model_render="${SAPPHIRE}${model}${RESET}"
nonnull "$mode_str" && model_render="${model_render:+$model_render }${ROSE}${mode_str}${RESET}"

# Extract provider domain from .claude/settings.local.json if present
provider_domain=""
if nonnull "$cwd"; then
  # Walk up directory tree to find .claude/settings.local.json (max 10 levels)
  search_dir="$cwd"
  for i in {1..10}; do
    settings_local="${search_dir}/.claude/settings.local.json"
    if [[ -f "$settings_local" ]] && command -v jq >/dev/null 2>&1; then
      base_url="$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$settings_local" 2>/dev/null)"
      if [[ -n "$base_url" && "$base_url" != "https://api.anthropic.com"* ]]; then
        # Extract domain: https://muyuan.do/path → muyuan.do
        provider_domain="$(printf '%s' "$base_url" | sed -E 's|^https?://([^/:]+).*|\1|')"
      fi
      break
    fi
    parent="$(dirname "$search_dir")"
    [[ "$parent" == "$search_dir" ]] && break  # reached root
    search_dir="$parent"
  done
fi
nonnull "$provider_domain" && model_render="${model_render:+$model_render }${DIM}${provider_domain}${RESET}"

# group: context + cache
ctxcache_render=""
if [ "${CQG_SHOW_CONTEXT:-true}" = "true" ]; then
  ctxcache_render="$ctx_render"
  nonnull "$cache_render" && ctxcache_render="${ctxcache_render:+$ctxcache_render${DIM} · ${RESET}}${cache_render}"
  nonnull "$cache_ttl_render" && ctxcache_render="${ctxcache_render:+$ctxcache_render${DIM} · ${RESET}}${cache_ttl_render}"
fi

# group: activity (agents/todos)
activity_render=""
if [ "${CQG_SHOW_AGENTS:-true}" = "true" ]; then
  [ "$agents_running" -gt 0 ] 2>/dev/null && activity_render="${ROSE}🤖${agents_running}${RESET}"
fi
if [ "${CQG_SHOW_TODOS:-true}" = "true" ]; then
  [ "$todos_pending" -gt 0 ] 2>/dev/null && activity_render="${activity_render:+$activity_render }${MAUVE}✓${todos_pending}${RESET}"
fi

# group: quota
quota_render=""
if [ "${CQG_SHOW_QUOTA:-true}" = "true" ]; then
  quota_render="$rate_render"
fi

line1=$(
  join_segments \
    "$loc_render" \
    "$model_render" \
    "$ctxcache_render" \
    "$activity_render" \
    "$quota_render" \
    "${SUBTEXT}🕐 ${time_str}${RESET}"
)

# ================= line 2: session / cost detail =================
cost_str=$(fmt_cost "$cost_usd")
nonnull "$cost_str" && cost_str="💰 $cost_str"

duration_detail=""
wall=$(fmt_duration_ms "$duration_ms")
api=$(fmt_duration_ms "$api_duration_ms")
if nonnull "$wall" || nonnull "$api"; then
  duration_detail="⏱ ${wall:-0}${api:+ (API ${api})}"
fi

change_detail=""
if nonnull "$lines_added" || nonnull "$lines_removed"; then
  added=${lines_added:-0}
  removed=${lines_removed:-0}
  if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
    change_detail="+${added}/-${removed}"
  fi
fi

token_window_str=""
if nonnull "$total_input"; then
  token_window_str="🪟 $(fmt_num "$total_input")"
  nonnull "$window_size" && token_window_str="${token_window_str}/$(fmt_num "$window_size")"
fi

# Token breakdown (current turn: input/cache-create/cache-read)
token_detail=""
if [ "${CQG_SHOW_TOKENS:-true}" = "true" ]; then
  if nonnull "$input_tokens" || nonnull "$cache_create" || nonnull "$cache_read"; then
    parts=""
    nonnull "$input_tokens" && parts="in:$(fmt_num "$input_tokens")"
    nonnull "$cache_create" && parts="${parts:+$parts }w:$(fmt_num "$cache_create")"
    nonnull "$cache_read" && parts="${parts:+$parts }r:$(fmt_num "$cache_read")"
    token_detail="🔢 $parts"
  fi
fi

meta_str=""
nonnull "$version" && meta_str="v$version"
nonnull "$output_style" && [ "$output_style" != "default" ] && meta_str="${meta_str:+$meta_str · }🎨 $output_style"

repo_str=""
if nonnull "$repo_owner" && nonnull "$repo_name"; then
  repo_str="${repo_owner}/${repo_name}"
fi

# conditional extras
pr_detail=""
nonnull "$pr_number" && pr_detail="PR #${pr_number}${pr_state:+ ${pr_state}}"
worktree_detail=""
nonnull "$worktree_name" && worktree_detail="⌥ ${worktree_name}"
agent_detail=""
nonnull "$agent_name" && agent_detail="agent ${agent_name}"
vim_detail=""
nonnull "$vim_mode" && vim_detail="vim ${vim_mode}"
session_detail=""
nonnull "$session_name" && session_detail="${session_name}"

line2=$(
  join_segments \
    "$(seg "$GOLD" "$cost_str")" \
    "$(seg "$SKY" "$duration_detail")" \
    "$(seg "$GREEN" "$change_detail")" \
    "$(seg "$SUBTEXT" "$token_window_str")" \
    "$(seg "$DIM" "$token_detail")" \
    "$(seg "$YELLOW" "$pr_detail")" \
    "$(seg "$PEACH" "$worktree_detail")" \
    "$(seg "$ROSE" "$agent_detail")" \
    "$(seg "$MAUVE" "$vim_detail")" \
    "$(seg "$SUBTEXT" "${repo_str:+$repo_str · }$meta_str")" \
    "$(seg "$SUBTEXT" "$session_detail")"
)

# Output: single line for compact, dual line otherwise
printf '%b\n' "$line1"
if [ "${CQG_STATUSLINE_PRESET:-full}" != "compact" ]; then
  nonnull "$line2" && printf '%b' "$line2"
fi
