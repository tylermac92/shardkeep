#!/usr/bin/env bash
# Runs the GUT suite headless. Fails if any test script didn't load: GUT only warns
# about a script with a parse error and skips it, so a broken file would look green.
# Usage: tools/run_tests.sh [godot binary]   (default: godot on PATH)
set -uo pipefail
cd "$(dirname "$0")/.."
log=$(mktemp)
trap 'rm -f "$log"' EXIT
"${1:-godot}" --headless -s addons/gut/gut_cmdln.gd < /dev/null 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "Ignoring script|Parse Error" "$log"; then
	echo "run_tests: a test script failed to load (see above)" >&2
	exit 1
fi
exit "$status"
