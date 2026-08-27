#!/usr/bin/env bash
# Pure rendering logic: no herdr, no filesystem, no side effects — hence testable.
# Bar and color conventions follow the get-shit-done status line.

# compute_pct <remaining_percentage> <total_tokens> [auto_compact_tokens]
# Prints "<usable> <raw>". Raw = 100 - remaining (what /context reports).
# Usable factors out the auto-compact buffer: 100% means /compact is about to fire.
compute_pct() {
  local remaining="$1" total="$2" acw="${3:-0}"
  [[ "$remaining" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  [[ "$total" =~ ^[0-9]+$ ]] && (( total > 0 )) || return 1
  [[ "$acw" =~ ^[0-9]+$ ]] || acw=0
  awk -v r="$remaining" -v t="$total" -v a="$acw" 'BEGIN {
    buf = (a > 0) ? (a / t) * 100 : 16.5
    if (buf > 100) buf = 100
    raw = 100 - r
    if (raw < 0) raw = 0
    if (raw > 100) raw = 100
    ur = (100 - buf > 0) ? ((r - buf) / (100 - buf)) * 100 : 0
    if (ur < 0) ur = 0
    if (ur > 100) ur = 100
    printf "%d %d\n", int((100 - ur) + 0.5), int(raw + 0.5)
  }'
}

# render_bar <usable> [width]
render_bar() {
  local pct="$1" width="${2:-10}" filled i out=""
  filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  for (( i = 0; i < width; i++ )); do
    (( i < filled )) && out+="█" || out+="░"
  done
  printf '%s' "$out"
}

# render_label <usable> <raw> [show_raw] — fixed width so columns line up
render_label() {
  local u="$1" raw="$2" show="${3:-1}"
  if [[ "$show" == 1 ]]; then printf '%3d%% (%2d%%)' "$u" "$raw"
  else printf '%3d%%' "$u"; fi
}

# color_for <usable> — thresholds: <50 green, <65 yellow, <80 orange, else blinking red
color_for() {
  local u="$1"
  if   (( u < 50 )); then printf '\033[32m'
  elif (( u < 65 )); then printf '\033[33m'
  elif (( u < 80 )); then printf '\033[38;5;208m'
  else                    printf '\033[5;31m'
  fi
}

# glyph_for <usable>
glyph_for() { (( ${1:-0} >= 80 )) && printf '💀'; return 0; }

# render_meter <usable> <raw> [width] [show_raw] [color]
render_meter() {
  local u="$1" raw="$2" width="${3:-10}" show="${4:-1}" color="${5:-1}" out g
  out="$(render_bar "$u" "$width") $(render_label "$u" "$raw" "$show")"
  g="$(glyph_for "$u")"
  [[ -n "$g" ]] && out="$out $g"
  if [[ "$color" == 1 ]]; then printf '%s%s\033[0m' "$(color_for "$u")" "$out"
  else printf '%s' "$out"; fi
}

# fmt_tokens <tokens> — 820 | 81k | 1.2M
fmt_tokens() {
  local n="$1"
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  awk -v n="$n" 'BEGIN {
    if      (n >= 1000000) printf "%.1fM", n / 1000000
    else if (n >= 1000)    printf "%dk", int(n / 1000 + 0.5)
    else                   printf "%d", n
  }'
}
