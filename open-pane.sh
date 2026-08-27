#!/usr/bin/env bash
# Öffnet das Meter-Pane. Als herdr-Action verfügbar, damit ein Keybinding darauf zeigen kann.
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-tlv.claude-context-meter}" --entrypoint meter
