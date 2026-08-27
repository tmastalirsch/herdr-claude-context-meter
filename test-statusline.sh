#!/usr/bin/env bash
# Tests for meter-statusline.sh: JSON on stdin -> a line on stdout + a state file.
cd "$(dirname "$0")"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONTEXT_METER_DIR="$TMP"
export METER_COLOR=0
FX="$TMP/fixtures"; mkdir -p "$FX"

# The status line JSON carries absolute paths, and the meter abbreviates $HOME to "~".
# Generating the fixtures here keeps the suite portable across machines.
python3 - "$FX" <<'PY'
import json, os, sys
fx, home = sys.argv[1], os.path.expanduser("~")
def w(name, obj): json.dump(obj, open(os.path.join(fx, name), "w"))
w("statusline.json", {
    "cwd": os.path.join(home, "projects/demo-app"),
    "session_id": "test-session-0001",
    "model": {"id": "claude-opus-5", "display_name": "Opus"},
    "workspace": {"current_dir": os.path.join(home, "projects/demo-app")},
    "version": "2.1.90",
    "context_window": {
        "context_window_size": 200000, "used_percentage": 8, "remaining_percentage": 92,
        "current_usage": {"input_tokens": 8500, "output_tokens": 1200,
                          "cache_creation_input_tokens": 5000, "cache_read_input_tokens": 2000}}})
w("statusline-critical.json", {
    "session_id": "test-session-0002",
    "model": {"display_name": "Sonnet"},
    "workspace": {"current_dir": home},
    "context_window": {
        "context_window_size": 1000000, "used_percentage": 70, "remaining_percentage": 30,
        "current_usage": {"input_tokens": 700000, "output_tokens": 0,
                          "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}})
w("statusline-no-context.json", {
    "session_id": "test-session-0003",
    "model": {"display_name": "Haiku"},
    "workspace": {"current_dir": "/tmp"}})
PY

run() { # run <fixture> [args...]
  local fx="$1"; shift
  bash meter-statusline.sh "$@" < "$FX/$fx"
}

t() { # t <description> <expected> <actual>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"
  else echo "FAIL $1"; echo "       want '$2'"; echo "        got '$3'"; fail=1; fi
}

field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"; }

echo "── stdout"
t "model + directory + meter" \
  "Opus  ~/projects/demo-app  █░░░░░░░░░  10% ( 8%)  17k/200k" \
  "$(METER_SHOW_TOKENS=1 run statusline.json)"

t "without tokens" \
  "Opus  ~/projects/demo-app  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json)"

t "critical gets a skull" \
  "Sonnet  ~  ████████░░  84% (70%) 💀" \
  "$(run statusline-critical.json)"

t "no context_window -> model + path only" \
  "Haiku  /tmp" \
  "$(run statusline-no-context.json)"

echo "── chaining: upstream command in front, meter behind"
t "foreign output is prepended" \
  "main ✱  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json printf 'main ✱')"

t "foreign command receives the same JSON" \
  "test-session-0001  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json python3 -c 'import json,sys;print(json.load(sys.stdin)["session_id"],end="")')"

echo "── state file for the herdr pane"
run statusline.json > /dev/null
SF="$TMP/sessions/test-session-0001.json"
t "file created"          "yes"               "$( [[ -f "$SF" ]] && echo yes || echo no )"
t "session_id"            "test-session-0001" "$(field "$SF" session_id)"
t "usable"                "10"                "$(field "$SF" usable)"
t "raw"                   "8"                 "$(field "$SF" raw)"
t "used_tokens"           "16700"             "$(field "$SF" used_tokens)"
t "window"                "200000"            "$(field "$SF" window)"
t "model"                 "Opus"              "$(field "$SF" model)"
t "ts is a number"        "yes"               "$( [[ "$(field "$SF" ts)" =~ ^[0-9]{10}$ ]] && echo yes || echo no )"

echo "── robustness"
t "no context_window -> no state file" "no" \
  "$( run statusline-no-context.json >/dev/null; [[ -f "$TMP/sessions/test-session-0003.json" ]] && echo yes || echo no )"
t "garbage JSON: quiet, exit 0" "0" \
  "$( echo 'not json' | bash meter-statusline.sh >/dev/null 2>&1; echo $? )"
t "empty stdin: quiet, exit 0" "0" \
  "$( printf '' | bash meter-statusline.sh >/dev/null 2>&1; echo $? )"
t "path traversal in session_id is rejected" "no" \
  "$( printf '%s' '{"session_id":"../../evil","model":{"display_name":"X"},"context_window":{"context_window_size":200000,"remaining_percentage":92}}' \
     | bash meter-statusline.sh >/dev/null 2>&1; [[ -f "$TMP/../evil.json" || -f "$TMP/sessions/../../evil.json" ]] && echo yes || echo no )"

if (( fail )); then echo; echo "FAILED"; else echo; echo "all tests green"; fi
exit $fail
