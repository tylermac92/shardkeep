#!/usr/bin/env bash
# Engine purity lint: engine/ must stay deterministic and free of the scene tree,
# clocks, global RNG, autoloads and client code (technical_design.md, Project layout).
# Usage: tools/lint_engine.sh [dir]   (default: engine)
set -euo pipefail
cd "$(dirname "$0")/.."
dir="${1:-engine}"

autoloads=$(sed -n '/^\[autoload\]/,/^\[/s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' project.godot | paste -sd'|' -)
banned="Node|get_tree|Time|OS|RandomNumberGenerator|randi|randf|randi_range|randf_range|randfn|randomize${autoloads:+|$autoloads}"

# shortcut: skips whole-line comments only; a banned word in a trailing comment still fails.
if grep -rnE --include='*.gd' "\b($banned)\b|client/" "$dir" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; then
	echo "engine purity lint: banned use above (see technical_design.md, Project layout)" >&2
	exit 1
fi
echo "engine purity lint: ok"
