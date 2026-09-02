#!/usr/bin/env bash
# Runs the unit suites headlessly.
#
#   ./run_tests.sh            all suites
#   ./run_tests.sh rater      only suites whose filename contains "rater"
#
# Point GODOT at a different binary if yours lives elsewhere:
#   GODOT=/path/to/godot ./run_tests.sh
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "Godot not found at $GODOT. Set GODOT=/path/to/godot." >&2
    exit 1
fi
cd "$(dirname "$0")"

# Scripts declaring class_name are only visible once the project has been
# scanned, so import first. Cheap when nothing changed.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if [ $# -gt 0 ]; then
    exec "$GODOT" --headless --path . res://tests/TestRunner.tscn -- "$1"
fi
exec "$GODOT" --headless --path . res://tests/TestRunner.tscn
