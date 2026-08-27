#!/usr/bin/env bash
# Tests für meter-pane.sh: agent-list-JSON + State-Dateien -> ein Frame auf stdout.
cd "$(dirname "$0")"
fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CONTEXT_METER_DIR="$TMP"
export METER_COLOR=0 METER_TITLE_WIDTH=20 METER_INTERVAL=5 METER_SHOW_TOKENS=1
export METER_AGENT_LIST_CMD="cat fixtures/agent-list.json"
mkdir -p "$TMP/sessions"

now=$(date +%s)
state() { # state <sid> <usable> <raw> <tokens> <alter_in_sekunden>
  printf '{"session_id":"%s","usable":%d,"raw":%d,"used_tokens":%d,"window":1000000,"model":"Opus","dir":"/x","ts":%d}\n' \
    "$1" "$2" "$3" "$4" "$(( now - $5 ))" > "$TMP/sessions/$1.json"
}
state sid-a 17 14 140000 5
state sid-b 53 44 440000 5
state sid-d 81 68 680000 9999      # veraltet
# sid-c bewusst ohne State-Datei

frame="$(bash meter-pane.sh --once)"

t() { if [[ "$3" == "$2" ]]; then echo "ok   $1"
      else echo "FAIL $1"; echo "       want '$2'"; echo "        got '$3'"; fail=1; fi; }
line() { sed -n "$1p" <<< "$frame"; }

echo "── Kopfzeile"
t "Kopf zählt nur Claude-Agents" "Claude Context · 4 Agents · alle 5s" "$(line 1)"
t "Leerzeile darunter"           ""                                   "$(line 2)"

echo "── Zeilen, sortiert nach Auslastung absteigend, ohne Daten zuletzt"
t "1. kritisch + veraltet" "w5:p2  ◑ Claude context Herd…  ████████░░  81% (68%) 💀  680k/1.0M ⧗" "$(line 3)"
t "2. mittel"              "w4:p1  ◑ AEM Agent pilot       █████░░░░░  53% (44%)  440k/1.0M"      "$(line 4)"
t "3. niedrig"             "w2:p1  ✳ herdr plugin session  █░░░░░░░░░  17% (14%)  140k/1.0M"      "$(line 5)"
t "4. ohne Daten"          "w5:p1  ✳ Slack-Status setzen   — keine Daten"                          "$(line 6)"
t "kein Codex-Agent"       ""                                                                      "$(grep -c codex <<< "$frame" | tr -d ' ' | sed 's/^0$//')"
t "genau 6 Zeilen"         "6"                                                                     "$(wc -l <<< "$frame" | tr -d ' ')"

echo "── Sortierung nach Pane-ID"
t "SORT=pane"  "w2:p1  ✳ herdr plugin session  █░░░░░░░░░  17% (14%)  140k/1.0M" \
               "$(METER_SORT=pane bash meter-pane.sh --once | sed -n 3p)"

echo "── ohne Tokenspalte"
t "METER_SHOW_TOKENS=0" "w4:p1  ◑ AEM Agent pilot       █████░░░░░  53% (44%)" \
               "$(METER_SHOW_TOKENS=0 bash meter-pane.sh --once | sed -n 4p)"

echo "── Tokenspalte ist rechtsbündig, damit /1.0M fluchtet"
state sid-e 7 6 67000 5
t "dreistelliger Wert wird gepolstert" "w9:p1  ✳ kurz                  ░░░░░░░░░░   7% ( 6%)   67k/1.0M" \
   "$(METER_AGENT_LIST_CMD='cat fixtures/agent-list-one.json' bash meter-pane.sh --once | sed -n 3p)"

echo "── Fehlerfälle"
t "herdr nicht erreichbar" "Claude Context · herdr nicht erreichbar" \
   "$(METER_AGENT_LIST_CMD='false' bash meter-pane.sh --once | sed -n 1p)"
t "Exit 0 trotz Fehler"    "0" \
   "$(METER_AGENT_LIST_CMD='false' bash meter-pane.sh --once >/dev/null 2>&1; echo $?)"
t "Schrott-JSON"           "Claude Context · herdr nicht erreichbar" \
   "$(METER_AGENT_LIST_CMD='echo kaputt' bash meter-pane.sh --once | sed -n 1p)"
t "keine Agents"           "Claude Context · keine Claude-Agents" \
   "$(METER_AGENT_LIST_CMD='cat fixtures/agent-list-empty.json' bash meter-pane.sh --once | sed -n 1p)"

if (( fail )); then echo; echo "FEHLGESCHLAGEN"; else echo; echo "alle Tests grün"; fi
exit $fail
