#!/usr/bin/env bash
# Tests for meter-pane.sh: agent-list JSON + state files -> one frame on stdout.
cd "$(dirname "$0")"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONTEXT_METER_DIR="$TMP"
export METER_COLOR=0 METER_TITLE_WIDTH=20 METER_INTERVAL=5 METER_SHOW_TOKENS=1
export METER_AGENT_LIST_CMD="cat fixtures/agent-list.json"
mkdir -p "$TMP/sessions"

now=$(date +%s)
state() { # state <sid> <usable> <raw> <tokens> <age_in_seconds>
  printf '{"session_id":"%s","usable":%d,"raw":%d,"used_tokens":%d,"window":1000000,"model":"Opus","dir":"/x","ts":%d}\n' \
    "$1" "$2" "$3" "$4" "$(( now - $5 ))" > "$TMP/sessions/$1.json"
}
state sid-a 17 14 140000 5
state sid-b 53 44 440000 5
state sid-d 81 68 680000 9999      # stale
# sid-c deliberately has no state file

frame="$(bash meter-pane.sh --once)"

t() { if [[ "$3" == "$2" ]]; then echo "ok   $1"
      else echo "FAIL $1"; echo "       want '$2'"; echo "        got '$3'"; fail=1; fi; }
line() { sed -n "$1p" <<< "$frame"; }

echo "── header"
t "header counts Claude agents only" "Claude Context · 4 agents · every 5s" "$(line 1)"
t "blank line below"                 ""                                     "$(line 2)"

echo "── rows, sorted by usage descending, missing data last"
t "1. critical + stale"  "w5:p2  ◑ context meter rewri…  ████████░░  81% (68%) 💀  680k/1.0M ⧗" "$(line 3)"
t "2. medium"            "w4:p1  ◑ release checklist     █████░░░░░  53% (44%)  440k/1.0M"      "$(line 4)"
t "3. low"               "w2:p1  ✳ herdr plugin session  █░░░░░░░░░  17% (14%)  140k/1.0M"      "$(line 5)"
t "4. no data"           "w5:p1  ✳ changelog for 2.4     — no data"                             "$(line 6)"
t "no codex agent"       ""                                                                     "$(grep -c codex <<< "$frame" | tr -d ' ' | sed 's/^0$//')"
t "exactly 6 lines"      "6"                                                                    "$(wc -l <<< "$frame" | tr -d ' ')"

echo "── sorting by pane ID"
t "METER_SORT=pane"  "w2:p1  ✳ herdr plugin session  █░░░░░░░░░  17% (14%)  140k/1.0M" \
               "$(METER_SORT=pane bash meter-pane.sh --once | sed -n 3p)"

echo "── without the token column"
t "METER_SHOW_TOKENS=0" "w4:p1  ◑ release checklist     █████░░░░░  53% (44%)" \
               "$(METER_SHOW_TOKENS=0 bash meter-pane.sh --once | sed -n 4p)"

echo "── token column is right-aligned so /1.0M lines up"
state sid-e 7 6 67000 5
t "three-digit value gets padded" "w9:p1  ✳ short                 ░░░░░░░░░░   7% ( 6%)   67k/1.0M" \
   "$(METER_AGENT_LIST_CMD='cat fixtures/agent-list-one.json' bash meter-pane.sh --once | sed -n 3p)"

echo "── failure modes"
t "herdr unreachable" "Claude Context · herdr unreachable" \
   "$(METER_AGENT_LIST_CMD='false' bash meter-pane.sh --once | sed -n 1p)"
t "exit 0 despite failure"    "0" \
   "$(METER_AGENT_LIST_CMD='false' bash meter-pane.sh --once >/dev/null 2>&1; echo $?)"
t "garbage JSON"           "Claude Context · herdr unreachable" \
   "$(METER_AGENT_LIST_CMD='echo broken' bash meter-pane.sh --once | sed -n 1p)"
t "no agents"              "Claude Context · no Claude agents" \
   "$(METER_AGENT_LIST_CMD='cat fixtures/agent-list-empty.json' bash meter-pane.sh --once | sed -n 1p)"

if (( fail )); then echo; echo "FAILED"; else echo; echo "all tests green"; fi
exit $fail
