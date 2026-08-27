# Claude Context Meter

Ein [herdr](https://herdr.dev)-Plugin, das die Kontextauslastung von Claude Code als
Balken zeigt — pro Session in der Statusline und für alle Sessions gemeinsam in einem
herdr-Pane.

*[English version](README.md)*

```
Claude Context · 4 Agents · alle 5s

w4:p1  ◑ AEM Agent pilot branch    ██████░░░░  68% (57%)  575k/1.0M
w5:p2  ◑ Claude context Herdr-Pl…  ██░░░░░░░░  20% (17%)  172k/1.0M
w2:p1  ✳ herdr plugin session re…  █░░░░░░░░░  17% (14%)  143k/1.0M
w5:p1  ✳ Slack-Status automatisc…  ░░░░░░░░░░   7% ( 6%)   67k/1.0M
```

In der Statusline:

```
Opus  ~/projekte/meine-app  █████░░░░░  53% (44%)
```

Balken- und Farbkonventionen folgen der [get-shit-done](https://github.com/gsd-build/get-shit-done)-Statusline:
grün <50 %, gelb <65 %, orange <80 %, darüber blinkend rot mit 💀.

## Die zwei Prozentzahlen

| | Nenner | Bedeutung |
|---|---|---|
| **nutzbar** (Balken) | Fenster minus Auto-Compact-Puffer | 100 % = `/compact` schlägt zu |
| **roh** (Klammern) | komplettes Fenster | identisch mit `/context` |

Claude Code reserviert am Fensterende einen Puffer für Auto-Compact — standardmäßig
~16,5 %, oder exakt `CLAUDE_CODE_AUTO_COMPACT_WINDOW` Tokens, wenn gesetzt. Dieser
Puffer ist nie nutzbar, deshalb erreicht *roh* nie 100 %. Grob: `nutzbar ≈ roh × 1,2`.

## Voraussetzungen

- herdr ≥ 0.8.2 mit installierter Claude-Integration (`herdr integration status`)
- Claude Code mit `statusLine`-Unterstützung (Feldnamen wie in 2.1.x)
- `bash`, `python3`, `awk` — alles auf macOS und Linux vorhanden

## Installation

```bash
herdr plugin install tmastalirsch/herdr-claude-context-meter
```

Dann die Statusline in `~/.claude/settings.json` eintragen. Den Plugin-Pfad liefert
`herdr plugin list`:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"/pfad/zum/plugin/meter-statusline.sh\"",
  "padding": 0
}
```

Pane öffnen:

```bash
herdr plugin pane open --plugin tlv.claude-context-meter --entrypoint meter
# oder: herdr plugin action invoke tlv.claude-context-meter.open
```

Optionales Keybinding in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+m"
type = "plugin_action"
command = "tlv.claude-context-meter.open"
description = "Kontext-Meter öffnen"
```

Für die Entwicklung am Plugin selbst statt `install`:

```bash
git clone https://github.com/tmastalirsch/herdr-claude-context-meter.git
herdr plugin link ./herdr-claude-context-meter
```

## Wie es funktioniert

```
~/.claude/settings.json  statusLine:
  bash meter-statusline.sh
         │
         ├─ rechnet nutzbar + roh aus dem Statusline-JSON
         ├─ schreibt ~/.local/state/claude-context-meter/sessions/<sid>.json
         └─ druckt den Balken → Statusline
                     │
   herdr agent list ─┤  pane_id + session_id verbinden Pane und Session
                     ↓
          meter-pane.sh (herdr-Pane, Loop)
```

Claude Code ruft die Statusline pro Session auf; das Plugin legt dabei den Messwert als
kleine JSON-Datei ab. Das Pane verbindet über `herdr agent list` die Pane-IDs mit den
Session-IDs und zeichnet daraus eine Zeile pro Agent.

### Mit einer bestehenden Statusline kombinieren

`meter-statusline.sh` ist verkettbar: gibt man ihm ein Kommando als Argument mit,
bekommt dieses dasselbe JSON auf stdin und seine Ausgabe erscheint **vor** dem Balken.

```bash
bash meter-statusline.sh bash meine-statusline.sh
# -> "main ✱ 3 Dateien  █████░░░░░  53% (44%)"
```

Umgekehrt funktioniert es auch: Wrapper, die ihr stdin unverändert an `"$@"`
weiterreichen, lassen sich davor hängen. So läuft dieses Plugin z. B. hinter einem
Auto-Compact-Wächter, der denselben Messwert für eigene Zwecke mitschreibt.

## Konfiguration

`$(herdr plugin config-dir tlv.claude-context-meter)/config` — Vorlage in
`config.example`. Änderungen greifen beim nächsten Tick des Panes, kein Neustart nötig.
Für die Statusline wirken dieselben Variablen als Umgebungsvariablen im
`statusLine`-Kommando.

| Variable | Standard | Bedeutung |
|---|---|---|
| `METER_INTERVAL` | `5` | Sekunden zwischen Neuaufbauten des Panes |
| `METER_WIDTH` | `10` | Segmente des Balkens |
| `METER_TITLE_WIDTH` | `24` | Spaltenbreite für den Pane-Titel (länger wird mit `…` gekürzt) |
| `METER_SHOW_RAW` | `1` | rohen Prozentwert in Klammern anzeigen |
| `METER_SHOW_TOKENS` | Pane `1`, Statusline `0` | `440k/1.0M` hinter dem Balken |
| `METER_SORT` | `used` | `used` = Auslastung absteigend, `pane` = nach Pane-ID |
| `METER_STALE` | `180` | Werte älter als N Sekunden mit `⧗` markieren |
| `METER_COLOR` | `1` | ANSI-Farben |

## Aufbau

| Datei | Zweck |
|---|---|
| `render.sh` | reine Rechen- und Renderlogik, keine IO — `compute_pct`, `render_bar`, `render_label`, `color_for`, `glyph_for`, `render_meter`, `fmt_tokens` |
| `meter-statusline.sh` | Statusline-JSON auf stdin → Balkenzeile + State-Datei |
| `meter-pane.sh` | Pane-Entrypoint; `--once` rendert einen einzelnen Frame auf stdout |
| `open-pane.sh` | herdr-Action, damit ein Keybinding auf das Pane zeigen kann |

Die Renderlogik liegt bewusst IO-frei in `render.sh`, damit sie ohne herdr und ohne
Claude Code testbar ist. Statusline und Pane sind dünne Hüllen darum.

## Test

```bash
bash test.sh              # alle Suiten
bash test-render.sh       # Rechnen + Rendern (ohne IO)
bash test-statusline.sh   # Fixture-JSON → Zeile + State-Datei
bash test-pane.sh         # Fixture-Agentliste + State → ein Frame
bash meter-pane.sh --once # ein Frame gegen die echte herdr-Session
```

## Grenzen

- Nur Claude-Panes innerhalb von herdr mit installierter Claude-Integration.
  Sessions außerhalb erscheinen nicht im Pane.
- Die Werte stammen aus der Claude-Statusline und aktualisieren sich, wenn Claude Code
  sie neu rendert. Beendete oder pausierte Sessions werden nach `METER_STALE` Sekunden
  mit `⧗` markiert, nicht entfernt.
- Sessions, die noch keine Statusline gerendert haben, zeigen `— keine Daten`.
- Die Fenstergröße kommt aus `context_window.context_window_size`; ohne dieses Feld
  bleibt die Zeile leer statt zu raten.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
