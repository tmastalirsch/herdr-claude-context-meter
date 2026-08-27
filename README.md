# Claude Context Meter

A [herdr](https://herdr.dev) plugin that shows Claude Code's context usage as a bar —
per session in the status line, and for all sessions at once in a herdr pane.

```
Claude Context · 4 Agents · alle 5s

w1:p1  ◑ api refactor              ██████░░░░  68% (57%)  570k/1.0M
w2:p1  ◑ flaky test hunt           ██░░░░░░░░  20% (17%)  172k/1.0M
w2:p2  ✳ changelog for 2.4         █░░░░░░░░░  17% (14%)  143k/1.0M
w3:p1  ✳ docs cleanup              ░░░░░░░░░░   7% ( 6%)   62k/1.0M
```

In the status line:

```
Opus  ~/projects/my-app  █████░░░░░  53% (44%)
```

Bar and color conventions follow the [get-shit-done](https://github.com/gsd-build/get-shit-done)
status line: green below 50%, yellow below 65%, orange below 80%, blinking red with 💀
above that.

## The two percentages

| | Denominator | Meaning |
|---|---|---|
| **usable** (the bar) | window minus auto-compact buffer | 100% = `/compact` fires |
| **raw** (in parentheses) | the full window | identical to `/context` |

Claude Code reserves a buffer at the end of the window for auto-compaction — ~16.5% by
default, or exactly `CLAUDE_CODE_AUTO_COMPACT_WINDOW` tokens when that variable is set.
You never get to use that buffer, which is why *raw* never reaches 100%. As a rule of
thumb: `usable ≈ raw × 1.2`.

## Requirements

- herdr ≥ 0.8.2 with the Claude integration installed (`herdr integration status`)
- Claude Code with `statusLine` support (field names as in 2.1.x)
- `bash`, `python3`, `awk` — all present on macOS and Linux

## Installation

```bash
herdr plugin install tmastalirsch/herdr-claude-context-meter
```

Then point your status line at the plugin in `~/.claude/settings.json`. Run
`herdr plugin list` to get the installed path:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"/path/to/plugin/meter-statusline.sh\"",
  "padding": 0
}
```

Open the pane:

```bash
herdr plugin pane open --plugin tlv.claude-context-meter --entrypoint meter
# or: herdr plugin action invoke tlv.claude-context-meter.open
```

Optional key binding in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "tlv.claude-context-meter.open"
description = "open context meter"
```

To work on the plugin itself, link a clone instead of installing:

```bash
git clone https://github.com/tmastalirsch/herdr-claude-context-meter.git
herdr plugin link ./herdr-claude-context-meter
```

## How it works

```
~/.claude/settings.json  statusLine:
  bash meter-statusline.sh
         │
         ├─ derives usable + raw from the status line JSON
         ├─ writes ~/.local/state/claude-context-meter/sessions/<sid>.json
         └─ prints the bar → status line
                     │
   herdr agent list ─┤  pane_id and session_id join pane to session
                     ↓
          meter-pane.sh (herdr pane, loop)
```

Claude Code invokes the status line once per session; the plugin drops the measurement
into a small JSON file as it renders. The pane uses `herdr agent list` to join pane IDs
with session IDs and draws one row per agent.

### Combining with an existing status line

`meter-statusline.sh` is chainable: pass a command as an argument and it receives the
same JSON on stdin, with its output appearing **before** the bar.

```bash
bash meter-statusline.sh bash my-statusline.sh
# -> "main ✱ 3 files  █████░░░░░  53% (44%)"
```

It works the other way round too: any wrapper that forwards its stdin unchanged to
`"$@"` can sit in front of this plugin. That is how it runs behind an auto-compact
watchdog, for instance, which records the same measurement for its own purposes.

## Configuration

`$(herdr plugin config-dir tlv.claude-context-meter)/config` — see `config.example` for
a template. Changes take effect on the pane's next tick, no restart needed. The same
variables work as environment variables in the `statusLine` command.

| Variable | Default | Meaning |
|---|---|---|
| `METER_INTERVAL` | `5` | seconds between pane redraws |
| `METER_WIDTH` | `10` | bar segments |
| `METER_TITLE_WIDTH` | `24` | column width for the pane title (longer titles are cut with `…`) |
| `METER_SHOW_RAW` | `1` | show the raw percentage in parentheses |
| `METER_SHOW_TOKENS` | pane `1`, status line `0` | append `440k/1.0M` after the bar |
| `METER_SORT` | `used` | `used` = by usage descending, `pane` = by pane ID |
| `METER_STALE` | `180` | flag values older than N seconds with `⧗` |
| `METER_COLOR` | `1` | ANSI colors |

## Layout

| File | Purpose |
|---|---|
| `render.sh` | pure arithmetic and rendering, no IO — `compute_pct`, `render_bar`, `render_label`, `color_for`, `glyph_for`, `render_meter`, `fmt_tokens` |
| `meter-statusline.sh` | status line JSON on stdin → bar line + state file |
| `meter-pane.sh` | pane entry point; `--once` renders a single frame to stdout |
| `open-pane.sh` | herdr action, so a key binding can point at the pane |

The rendering logic deliberately lives IO-free in `render.sh` so it is testable without
herdr and without Claude Code. The status line and the pane are thin shells around it.

## Tests

```bash
bash test.sh              # every suite
bash test-render.sh       # arithmetic + rendering (no IO)
bash test-statusline.sh   # fixture JSON → line + state file
bash test-pane.sh         # fixture agent list + state → one frame
bash meter-pane.sh --once # one frame against the live herdr session
```

## Limitations

- Only Claude panes inside herdr with the Claude integration installed. Sessions outside
  herdr do not appear in the pane.
- Values come from the Claude status line and refresh whenever Claude Code re-renders it.
  Finished or paused sessions are flagged with `⧗` after `METER_STALE` seconds rather
  than removed.
- Sessions that have not rendered a status line yet show `— keine Daten`.
- The window size comes from `context_window.context_window_size`; without that field the
  row stays empty rather than guessing.
- The pane's own labels are still German (`4 Agents · alle 5s`, `— keine Daten`), as the
  sample output above shows. Only the surrounding docs are translated so far.

## License

MIT — see [LICENSE](LICENSE).
