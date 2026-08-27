#!/usr/bin/env bash
# Claude-Code-Statusline: rendert den Kontext-Balken und legt den Wert für das
# herdr-Pane ab. Verkettbar — mit Argumenten wird deren Ausgabe vorangestellt:
#   meter-statusline.sh                      -> "Opus  ~/projekt  ███░░░ 31% (26%)"
#   meter-statusline.sh my-statusline.sh     -> "<deren Ausgabe>  ███░░░ 31% (26%)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/render.sh" 2>/dev/null || exit 0

COLOR="${METER_COLOR:-1}"
WIDTH="${METER_WIDTH:-10}"
SHOW_RAW="${METER_SHOW_RAW:-1}"
SHOW_DIR="${METER_SHOW_DIR:-1}"
SHOW_TOKENS="${METER_SHOW_TOKENS:-0}"
STATE_DIR="${CLAUDE_CONTEXT_METER_DIR:-$HOME/.local/state/claude-context-meter}/sessions"

input="$(cat)"
[[ -n "$input" ]] || exit 0

# Ein einziger Python-Aufruf, sechs Zeilen: sid, modell, dir, remaining%, fenster, tokens
parsed="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict): raise ValueError
except Exception:
    sys.exit(1)
cw = d.get("context_window") or {}
cur = cw.get("current_usage") or {}
rem = cw.get("remaining_percentage")
if rem is None and cw.get("used_percentage") is not None:
    rem = 100 - cw["used_percentage"]
out = [
    d.get("session_id") or "",
    (d.get("model") or {}).get("display_name") or "Claude",
    (d.get("workspace") or {}).get("current_dir") or d.get("cwd") or "",
    "" if rem is None else rem,
    cw.get("context_window_size") or cw.get("total_tokens") or "",
    sum(int(cur.get(k) or 0) for k in
        ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")),
]
print("\n".join(str(v) for v in out))
' 2>/dev/null)" || exit 0
[[ -n "$parsed" ]] || exit 0
{ read -r SID; read -r MODEL; read -r DIRP; read -r REM; read -r WINDOW; read -r USED_TOK; } <<< "$parsed"

# Kopf: Fremdausgabe (verkettet) oder Modell + Verzeichnis
if (( $# > 0 )); then
  head="$(printf '%s' "$input" | "$@" 2>/dev/null)"
else
  head="$MODEL"
  tilde="~"
  if [[ "$SHOW_DIR" == 1 && -n "$DIRP" ]]; then head="$head  ${DIRP/#$HOME/$tilde}"; fi
fi

# JSON-Stringwerte entschärfen, damit die State-Datei gültig bleibt
sanitize() { printf '%s' "${1//[\"\\]/}" | tr -d '\000-\037'; }

meter=""
if pct="$(compute_pct "$REM" "$WINDOW" "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-0}")"; then
  read -r USABLE RAW <<< "$pct"
  meter="$(render_meter "$USABLE" "$RAW" "$WIDTH" "$SHOW_RAW" "$COLOR")"
  if [[ "$SHOW_TOKENS" == 1 && -n "$USED_TOK" && "$USED_TOK" != 0 ]]; then
    meter="$meter  $(fmt_tokens "$USED_TOK")/$(fmt_tokens "$WINDOW")"
  fi
  # State für das Pane — nur bei unbedenklicher Session-ID (kein Pfad-Traversal)
  if [[ "$SID" =~ ^[A-Za-z0-9._-]+$ && "$SID" != *..* ]] && mkdir -p "$STATE_DIR" 2>/dev/null; then
    f="$STATE_DIR/$SID.json"
    if printf '{"session_id":"%s","usable":%d,"raw":%d,"used_tokens":%d,"window":%d,"model":"%s","dir":"%s","ts":%d}\n' \
         "$SID" "$USABLE" "$RAW" "${USED_TOK:-0}" "$WINDOW" \
         "$(sanitize "$MODEL")" "$(sanitize "$DIRP")" "$(date +%s)" > "$f.tmp" 2>/dev/null
    then mv -f "$f.tmp" "$f" 2>/dev/null; else rm -f "$f.tmp" 2>/dev/null; fi
  fi
fi

out="$head"
[[ -n "$meter" ]] && out="$head  $meter"
printf '%s\n' "$out"
