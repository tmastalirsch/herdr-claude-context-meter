#!/usr/bin/env bash
# herdr pane: one bar row per Claude agent, refreshed live.
#   meter-pane.sh          endless loop with screen redraw (pane entry point)
#   meter-pane.sh --once   a single frame on stdout (testable)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/render.sh" || exit 1

load_conf() {
  local conf="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/claude-context-meter}/config"
  [[ -f "$conf" ]] && source "$conf"
  HERDR="${HERDR_BIN_PATH:-herdr}"
  AGENT_LIST_CMD="${METER_AGENT_LIST_CMD:-$HERDR agent list}"
  STATE_DIR="${CLAUDE_CONTEXT_METER_DIR:-$HOME/.local/state/claude-context-meter}/sessions"
  INTERVAL="${METER_INTERVAL:-5}"
  WIDTH="${METER_WIDTH:-10}"
  TITLE_WIDTH="${METER_TITLE_WIDTH:-24}"
  SHOW_RAW="${METER_SHOW_RAW:-1}"
  SHOW_TOKENS="${METER_SHOW_TOKENS:-1}"
  COLOR="${METER_COLOR:-1}"
  STALE="${METER_STALE:-180}"
  SORT="${METER_SORT:-used}"
}

# Joins agent list with the state files and sorts. Data plumbing, no presentation.
# One tab-separated line per agent: pane status title has_data usable raw tokens window stale
collect() {
  local json
  json="$($AGENT_LIST_CMD 2>/dev/null)" || return 1
  [[ -n "$json" ]] || return 1
  printf '%s' "$json" | STATE_DIR="$STATE_DIR" STALE="$STALE" \
    TITLE_WIDTH="$TITLE_WIDTH" SORT="$SORT" python3 -c '
import json, os, re, sys, time
try:
    d = json.load(sys.stdin)
    agents = (d.get("result") or {}).get("agents")
    if agents is None: raise ValueError
except Exception:
    sys.exit(1)

state_dir = os.environ["STATE_DIR"]
stale_after = int(os.environ["STALE"])
tw = int(os.environ["TITLE_WIDTH"])
now = int(time.time())
safe = re.compile(r"^[A-Za-z0-9._-]+$")

rows = []
for a in agents:
    if a.get("agent") != "claude":
        continue
    sid = (a.get("agent_session") or {}).get("value") or ""
    st = {}
    if sid and safe.match(sid) and ".." not in sid:
        try:
            with open(os.path.join(state_dir, sid + ".json")) as fh:
                st = json.load(fh)
        except Exception:
            st = {}
    has = 1 if ("usable" in st and "raw" in st) else 0
    title = a.get("terminal_title_stripped") or a.get("terminal_title") or sid or "?"
    title = title[: tw - 1] + "…" if len(title) > tw else title
    rows.append({
        "pane": a.get("pane_id") or "?",
        "status": a.get("agent_status") or "unknown",
        "title": title,
        "has": has,
        "usable": int(st.get("usable") or 0),
        "raw": int(st.get("raw") or 0),
        "tokens": int(st.get("used_tokens") or 0),
        "window": int(st.get("window") or 0),
        "stale": 1 if (has and now - int(st.get("ts") or 0) > stale_after) else 0,
    })

if os.environ["SORT"] == "pane":
    rows.sort(key=lambda r: r["pane"])
else:
    rows.sort(key=lambda r: (-r["has"], -r["usable"], r["pane"]))

pw = max((len(r["pane"]) for r in rows), default=0)
for r in rows:
    print("\t".join(str(v) for v in (
        r["pane"].ljust(pw), r["status"], r["title"].ljust(tw),
        r["has"], r["usable"], r["raw"], r["tokens"], r["window"], r["stale"])))
'
}

glyph_for_status() {
  case "$1" in
    idle)    printf '✳' ;;
    working) printf '◑' ;;
    done)    printf '✓' ;;
    blocked) printf '⚠' ;;
    *)       printf '·' ;;
  esac
}

render_frame() {
  local rows count=0
  if ! rows="$(collect)"; then
    printf 'Claude Context · herdr unreachable\n'
    return 0
  fi
  [[ -n "$rows" ]] && count="$(grep -c '' <<< "$rows")"
  if (( count == 0 )); then
    printf 'Claude Context · no Claude agents\n'
    return 0
  fi
  local noun="agents"; (( count == 1 )) && noun="agent"
  printf 'Claude Context · %d %s · every %ss\n\n' "$count" "$noun" "$INTERVAL"

  local pane status title has usable raw tokens window stale meter
  while IFS=$'\t' read -r pane status title has usable raw tokens window stale; do
    if (( has )); then
      meter="$(render_meter "$usable" "$raw" "$WIDTH" "$SHOW_RAW" "$COLOR")"
      if [[ "$SHOW_TOKENS" == 1 ]] && (( tokens > 0 && window > 0 )); then
        meter="$meter  $(printf '%4s' "$(fmt_tokens "$tokens")")/$(fmt_tokens "$window")"
      fi
      (( stale )) && meter="$meter ⧗"
    else
      meter="— no data"
    fi
    printf '%s  %s %s  %s\n' "$pane" "$(glyph_for_status "$status")" "$title" "$meter"
  done <<< "$rows"
}

load_conf
if [[ "${1:-}" == "--once" ]]; then render_frame; exit 0; fi

trap 'printf "\033[?25h"; exit 0' INT TERM
printf '\033[?25l'                        # hide the cursor while the pane runs
while :; do
  load_conf
  frame="$(render_frame)"
  printf '\033[H\033[2J%s' "$frame"       # home, clear, redraw
  sleep "$INTERVAL"
done
