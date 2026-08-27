#!/usr/bin/env bash
# Opens the meter pane. Exposed as a herdr action so a key binding can point at it.
exec "${HERDR_BIN_PATH:-herdr}" plugin pane open \
  --plugin "${HERDR_PLUGIN_ID:-tlv.claude-context-meter}" --entrypoint meter
