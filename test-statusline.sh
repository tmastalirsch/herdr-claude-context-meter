#!/usr/bin/env bash
# Tests für meter-statusline.sh: JSON auf stdin -> Zeile auf stdout + State-Datei.
cd "$(dirname "$0")"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONTEXT_METER_DIR="$TMP"
export METER_COLOR=0

run() { # run <fixture> [args...]
  local fx="$1"; shift
  bash meter-statusline.sh "$@" < "fixtures/$fx"
}

t() { # t <beschreibung> <erwartet> <ist>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"
  else echo "FAIL $1"; echo "       want '$2'"; echo "        got '$3'"; fail=1; fi
}

field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"; }

echo "── stdout"
t "Modell + Verzeichnis + Meter" \
  "Opus  ~/workspaces/tlv/tlv-aem-agent  █░░░░░░░░░  10% ( 8%)  17k/200k" \
  "$(METER_SHOW_TOKENS=1 run statusline.json)"

t "ohne Tokens" \
  "Opus  ~/workspaces/tlv/tlv-aem-agent  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json)"

t "kritisch bekommt Totenkopf" \
  "Sonnet  ~  ████████░░  84% (70%) 💀" \
  "$(run statusline-critical.json)"

t "ohne context_window nur Modell + Pfad" \
  "Haiku  /tmp" \
  "$(run statusline-no-context.json)"

echo "── Verkettung: vorgeschaltetes Kommando davor, Meter dahinter"
t "Fremdausgabe wird vorangestellt" \
  "main ✱  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json printf 'main ✱')"

t "Fremdkommando bekommt dasselbe JSON" \
  "test-session-0001  █░░░░░░░░░  10% ( 8%)" \
  "$(run statusline.json python3 -c 'import json,sys;print(json.load(sys.stdin)["session_id"],end="")')"

echo "── State-Datei für das herdr-Pane"
run statusline.json > /dev/null
SF="$TMP/sessions/test-session-0001.json"
t "Datei angelegt"        "ja"                "$( [[ -f "$SF" ]] && echo ja || echo nein )"
t "session_id"            "test-session-0001" "$(field "$SF" session_id)"
t "usable"                "10"                "$(field "$SF" usable)"
t "raw"                   "8"                 "$(field "$SF" raw)"
t "used_tokens"           "16700"             "$(field "$SF" used_tokens)"
t "window"                "200000"            "$(field "$SF" window)"
t "model"                 "Opus"              "$(field "$SF" model)"
t "ts ist eine Zahl"      "ja"                "$( [[ "$(field "$SF" ts)" =~ ^[0-9]{10}$ ]] && echo ja || echo nein )"

echo "── Robustheit"
t "ohne context_window keine State-Datei" "nein" \
  "$( run statusline-no-context.json >/dev/null; [[ -f "$TMP/sessions/test-session-0003.json" ]] && echo ja || echo nein )"
t "Schrott-JSON: leise, Exit 0" "0" \
  "$( echo 'kein json' | bash meter-statusline.sh >/dev/null 2>&1; echo $? )"
t "leeres stdin: leise, Exit 0" "0" \
  "$( printf '' | bash meter-statusline.sh >/dev/null 2>&1; echo $? )"
t "Pfad-Traversal in session_id wird abgelehnt" "nein" \
  "$( printf '%s' '{"session_id":"../../evil","model":{"display_name":"X"},"context_window":{"context_window_size":200000,"remaining_percentage":92}}' \
     | bash meter-statusline.sh >/dev/null 2>&1; [[ -f "$TMP/../evil.json" || -f "$TMP/sessions/../../evil.json" ]] && echo ja || echo nein )"

if (( fail )); then echo; echo "FEHLGESCHLAGEN"; else echo; echo "alle Tests grün"; fi
exit $fail
