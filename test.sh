#!/usr/bin/env bash
# Runs every suite.
cd "$(dirname "$0")"
fail=0
for s in test-render.sh test-statusline.sh test-pane.sh; do
  echo "═══ $s"
  bash "$s" || fail=1
  echo
done
if (( fail )); then echo "═══ FAILED"; else echo "═══ all green"; fi
exit $fail
