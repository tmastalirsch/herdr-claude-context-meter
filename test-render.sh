#!/usr/bin/env bash
# Tests für die reine Renderlogik. Keine herdr-Aufrufe, kein Dateisystem.
cd "$(dirname "$0")"; source ./render.sh
fail=0
ESC=$'\033'

t() { # t <beschreibung> <erwartet> <befehl...>
  local desc="$1" want="$2"; shift 2
  local got; got=$("$@")
  if [[ "$got" == "$want" ]]; then echo "ok   $desc"
  else echo "FAIL $desc"; echo "       want '$want'"; echo "        got '$got'"; fail=1; fi
}

echo "── compute_pct <remaining%> <total_tokens> [acw_tokens] -> '<nutzbar> <roh>'"
t "leeres Fenster"            "0 0"     compute_pct 100 1000000
t "roh 44 -> nutzbar 53"      "53 44"   compute_pct 56  1000000
t "roh 70 -> nutzbar 84"      "84 70"   compute_pct 30  1000000
t "Puffer erreicht -> 100"    "100 84"  compute_pct 16  1000000
t "unter Puffer bleibt 100"   "100 90"  compute_pct 10  1000000
t "ACW-Override 100k = 10%"   "49 44"   compute_pct 56  1000000 100000
t "200k-Fenster, roh 44"      "53 44"   compute_pct 56  200000

echo "── compute_pct lehnt Unsinn ab"
t "kein remaining"            ""        compute_pct ""   1000000
t "remaining ist Text"        ""        compute_pct abc  1000000
t "total ist 0"               ""        compute_pct 56   0

echo "── render_bar <nutzbar> [breite]"
t "0% leer"                   "░░░░░░░░░░"            render_bar 0
t "7% noch kein Segment"      "░░░░░░░░░░"            render_bar 7
t "53% -> 5 Segmente"         "█████░░░░░"            render_bar 53
t "100% voll"                 "██████████"            render_bar 100
t "Breite 20"                 "██████████░░░░░░░░░░"  render_bar 53 20
t "Breite 5"                  "██░░░"                 render_bar 53 5

echo "── render_label <nutzbar> <roh> [show_raw]"
t "mit Rohwert"               " 53% (44%)"  render_label 53 44 1
t "einstellig ausgerichtet"   "  7% ( 6%)"  render_label 7 6 1
t "dreistellig"               "100% (84%)"  render_label 100 84 1
t "ohne Rohwert"              " 53%"        render_label 53 44 0

echo "── color_for <nutzbar>  (GSD-Schwellen)"
t "0 gruen"                   "${ESC}[32m"        color_for 0
t "49 gruen"                  "${ESC}[32m"        color_for 49
t "50 gelb"                   "${ESC}[33m"        color_for 50
t "64 gelb"                   "${ESC}[33m"        color_for 64
t "65 orange"                 "${ESC}[38;5;208m"  color_for 65
t "79 orange"                 "${ESC}[38;5;208m"  color_for 79
t "80 rot blinkend"           "${ESC}[5;31m"      color_for 80
t "100 rot blinkend"          "${ESC}[5;31m"      color_for 100

echo "── glyph_for <nutzbar>"
t "unkritisch kein Glyph"     ""     glyph_for 79
t "kritisch Totenkopf"        "💀"   glyph_for 80

echo "── render_meter <nutzbar> <roh> <breite> <show_raw> <color>"
t "ohne Farbe"  "█████░░░░░  53% (44%)"                        render_meter 53 44 10 1 0
t "mit Farbe gruen"  "${ESC}[32m████░░░░░░  44% (37%)${ESC}[0m"  render_meter 44 37 10 1 1
t "mit Farbe gelb"   "${ESC}[33m█████░░░░░  53% (44%)${ESC}[0m"  render_meter 53 44 10 1 1
t "kritisch"    "████████░░  81% (68%) 💀"                     render_meter 81 68 10 1 0

echo "── fmt_tokens <tokens>"
t "unter 1k"      "820"    fmt_tokens 820
t "tausender"     "81k"    fmt_tokens 81400
t "gerundet"      "82k"    fmt_tokens 81600
t "Millionen"     "1.0M"   fmt_tokens 1000000
t "1,2 Mio"       "1.2M"   fmt_tokens 1234000
t "kein Wert"     ""       fmt_tokens ""

if (( fail )); then echo; echo "FEHLGESCHLAGEN"; else echo; echo "alle Tests grün"; fi
exit $fail
