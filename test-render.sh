#!/usr/bin/env bash
# Tests for the pure rendering logic. No herdr calls, no filesystem.
cd "$(dirname "$0")"; source ./render.sh
fail=0
ESC=$'\033'

t() { # t <description> <expected> <command...>
  local desc="$1" want="$2"; shift 2
  local got; got=$("$@")
  if [[ "$got" == "$want" ]]; then echo "ok   $desc"
  else echo "FAIL $desc"; echo "       want '$want'"; echo "        got '$got'"; fail=1; fi
}

echo "── compute_pct <remaining%> <total_tokens> [acw_tokens] -> '<usable> <raw>'"
t "empty window"                  "0 0"     compute_pct 100 1000000
t "raw 44 -> usable 53"           "53 44"   compute_pct 56  1000000
t "raw 70 -> usable 84"           "84 70"   compute_pct 30  1000000
t "buffer reached -> 100"         "100 84"  compute_pct 16  1000000
t "below buffer stays 100"        "100 90"  compute_pct 10  1000000
t "ACW override 100k = 10%"       "49 44"   compute_pct 56  1000000 100000
t "200k window, raw 44"           "53 44"   compute_pct 56  200000

echo "── compute_pct rejects nonsense"
t "no remaining"                  ""        compute_pct ""   1000000
t "remaining is text"             ""        compute_pct abc  1000000
t "total is 0"                    ""        compute_pct 56   0

echo "── render_bar <usable> [width]"
t "0% empty"                      "░░░░░░░░░░"            render_bar 0
t "7% no segment yet"             "░░░░░░░░░░"            render_bar 7
t "53% -> 5 segments"             "█████░░░░░"            render_bar 53
t "100% full"                     "██████████"            render_bar 100
t "width 20"                      "██████████░░░░░░░░░░"  render_bar 53 20
t "width 5"                       "██░░░"                 render_bar 53 5

echo "── render_label <usable> <raw> [show_raw]"
t "with raw value"                " 53% (44%)"  render_label 53 44 1
t "single digit aligned"          "  7% ( 6%)"  render_label 7 6 1
t "three digits"                  "100% (84%)"  render_label 100 84 1
t "without raw value"             " 53%"        render_label 53 44 0

echo "── color_for <usable>  (get-shit-done thresholds)"
t "0 green"                       "${ESC}[32m"        color_for 0
t "49 green"                      "${ESC}[32m"        color_for 49
t "50 yellow"                     "${ESC}[33m"        color_for 50
t "64 yellow"                     "${ESC}[33m"        color_for 64
t "65 orange"                     "${ESC}[38;5;208m"  color_for 65
t "79 orange"                     "${ESC}[38;5;208m"  color_for 79
t "80 blinking red"               "${ESC}[5;31m"      color_for 80
t "100 blinking red"              "${ESC}[5;31m"      color_for 100

echo "── glyph_for <usable>"
t "uncritical, no glyph"          ""     glyph_for 79
t "critical, skull"               "💀"   glyph_for 80

echo "── render_meter <usable> <raw> <width> <show_raw> <color>"
t "without color"     "█████░░░░░  53% (44%)"                         render_meter 53 44 10 1 0
t "colored green"     "${ESC}[32m████░░░░░░  44% (37%)${ESC}[0m"      render_meter 44 37 10 1 1
t "colored yellow"    "${ESC}[33m█████░░░░░  53% (44%)${ESC}[0m"      render_meter 53 44 10 1 1
t "critical"          "████████░░  81% (68%) 💀"                      render_meter 81 68 10 1 0

echo "── fmt_tokens <tokens>"
t "below 1k"          "820"    fmt_tokens 820
t "thousands"         "81k"    fmt_tokens 81400
t "rounded"           "82k"    fmt_tokens 81600
t "millions"          "1.0M"   fmt_tokens 1000000
t "1.2 million"       "1.2M"   fmt_tokens 1234000
t "no value"          ""       fmt_tokens ""

if (( fail )); then echo; echo "FAILED"; else echo; echo "all tests green"; fi
exit $fail
