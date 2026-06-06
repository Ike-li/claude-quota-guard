#!/usr/bin/env bash
# Claude Code statusLine command
# Style: Starship + Catppuccin Mocha inspired. Human-friendly, two lines.

# Source shared snapshot logic
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SELF_DIR/lib/snapshot.sh"

input=$(cat)

# Catppuccin Mocha colors.
RED="\033[38;2;243;139;168m"
PEACH="\033[38;2;250;179;135m"
YELLOW="\033[38;2;249;226;175m"
GREEN="\033[38;2;166;227;161m"
SAPPHIRE="\033[38;2;116;199;236m"
MAUVE="\033[38;2;203;166;247m"
SKY="\033[38;2;137;220;235m"
ROSE="\033[38;2;245;194;231m"
GOLD="\033[38;2;249;226;175m"
SUBTEXT="\033[38;2;166;173;200m"
DIM="\033[38;2;108;112;134m"
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

fmt_reset_delta() {
  local epoch="$1"
  nonnull "$epoch" || return 0
  local now delta
  now=$(date +%s)
  delta=$(awk -v e="$epoch" -v n="$now" 'BEGIN { printf "%.0f", e - n }')
  [ "$delta" -gt 0 ] 2>/dev/null || {
    printf "now"
    return 0
  }
  awk -v sec="$delta" 'BEGIN {
    if (sec >= 86400) printf "%dd", int(sec / 86400)
    else if (sec >= 3600) printf "%dh", int(sec / 3600)
    else if (sec >= 60) printf "%dm", int(sec / 60)
    else printf "%ds", sec
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
    if [ "$changed" -gt 0 ] 2>/dev/null; then
      printf '%s' "$changed" >"$git_cache"
    else
      : >"$git_cache"
    fi
  fi
  git_changed=$(cat "$git_cache" 2>/dev/null)
fi

git_str="$git_branch"
if nonnull "$git_str"; then
  git_str=" ${git_str}"
  nonnull "$git_changed" && git_str="${git_str} ✱${git_changed}"
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
  # stat format differs: Linux uses -c, BSD/macOS uses -f
  if stat -c %Y "$act_stamp" >/dev/null 2>&1; then
    warm_mtime=$(stat -c %Y "$act_stamp" 2>/dev/null || echo 0)
  else
    warm_mtime=$(stat -f %m "$act_stamp" 2>/dev/null || echo 0)
  fi
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
  five_reset=$(fmt_reset_delta "$five_h_reset")
  rate_render="$(tier_color "$five_int" high_bad)5h ${five_int}%${five_reset:+ ↻${five_reset}}${RESET}"
  # burn-rate projection: at current pace, what % we'll reach by window reset.
  if nonnull "$five_h_reset"; then
    five_proj=$(awk -v used="$five_h" -v reset="$five_h_reset" -v now="$(date +%s)" -v win="$CQG_FIVE_HOUR_WINDOW" 'BEGIN {
      remain = reset - now; elapsed = win - remain;
      if (elapsed < 300 || used <= 0) exit;       # too early / nothing used yet
      p = used * win / elapsed;
      if (p > 999) p = 999;
      printf "%.0f", p;
    }')
    nonnull "$five_proj" && rate_render="${rate_render} $(tier_color "$five_proj" high_bad)→${five_proj}%${RESET}"
  fi
fi

# ---- usage history log (throttled to once / 5 min) ----
if nonnull "$five_h" || nonnull "$seven_d"; then
  usage_log="$HOME/.claude/usage-log.tsv"
  usage_stamp="${TMPDIR:-/tmp}/claude-usage-log-stamp"
  log_age=99999
  if [ -f "$usage_stamp" ]; then
    stamp_mtime=$(stat -f %m "$usage_stamp" 2>/dev/null || stat -c %Y "$usage_stamp" 2>/dev/null || echo 0)
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
  seven_reset=$(fmt_reset_delta "$seven_d_reset")
  seven_render="$(tier_color "$seven_int" high_bad)7d ${seven_int}%${seven_reset:+ ↻${seven_reset}}${RESET}"
  rate_render="${rate_render:+$rate_render${DIM} · ${RESET}}${seven_render}"
fi

# ---- current quota snapshot (unthrottled, for the convergence hook) ----
# Delegates to shared lib/snapshot.sh to ensure consistency with collect.sh.
CQG_SNAPSHOT="$HOME/.claude/.quota-now"
cqg_write_snapshot "${five_int:-}" "${seven_int:-}" "${five_proj:-}" "${five_reset:-}" "${seven_reset:-}" "${used_int:-}" "$session_id"

# ================= line 1: live status =================
# group: location (project + branch)
loc_render="${PEACH}📁 ${project_name}${RESET}"
nonnull "$git_str" && loc_render="${loc_render}${YELLOW}${git_str}${RESET}"

# group: model + mode
model_render=""
nonnull "$model" && model_render="${SAPPHIRE}${model}${RESET}"
nonnull "$mode_str" && model_render="${model_render:+$model_render }${ROSE}${mode_str}${RESET}"

# group: context + cache
ctxcache_render="$ctx_render"
nonnull "$cache_render" && ctxcache_render="${ctxcache_render:+$ctxcache_render${DIM} · ${RESET}}${cache_render}"
nonnull "$cache_ttl_render" && ctxcache_render="${ctxcache_render:+$ctxcache_render${DIM} · ${RESET}}${cache_ttl_render}"

line1=$(
  join_segments \
    "$loc_render" \
    "$model_render" \
    "$ctxcache_render" \
    "$rate_render" \
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
    "$(seg "$YELLOW" "$pr_detail")" \
    "$(seg "$PEACH" "$worktree_detail")" \
    "$(seg "$ROSE" "$agent_detail")" \
    "$(seg "$MAUVE" "$vim_detail")" \
    "$(seg "$SUBTEXT" "${repo_str:+$repo_str · }$meta_str")" \
    "$(seg "$SUBTEXT" "$session_detail")"
)

printf '%b\n' "$line1"
nonnull "$line2" && printf '%b' "$line2"
