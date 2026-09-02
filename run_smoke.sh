#!/usr/bin/env bash
# Boots the real game headlessly and plays a puzzle through the UI signals.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path . res://tests/Smoke.tscn
