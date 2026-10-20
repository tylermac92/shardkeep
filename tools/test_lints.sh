#!/usr/bin/env bash
# Proves the CI lints catch what they should: banned calls in engine/ and malformed gems.json.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

expect_fail() { # <label> <command...>
	local label=$1; shift
	if "$@" >/dev/null 2>&1; then echo "FAIL: $label was not caught" >&2; exit 1; fi
	echo "ok: $label caught"
}

for call in 'get_tree()' 'randi()'; do
	printf 'extends RefCounted\n\nfunc f():\n\treturn %s\n' "$call" > "$tmp/bad.gd"
	expect_fail "engine/ using $call" tools/lint_engine.sh "$tmp"
done
rm "$tmp/bad.gd"

mutate() { # <python statement on dict d>
	python3 -c "import json,sys; d=json.load(open('content/gems.json')); $1; json.dump(d, open('$tmp/gems.json','w'))"
}
mutate 'd["gems"][0]["spawn_weight"] = "16"'
expect_fail "gems.json with a wrong type" tools/validate_content.sh "$tmp"
mutate 'del d["gems"][0]["reward"]'
expect_fail "gems.json with a missing field" tools/validate_content.sh "$tmp"

# Sanity: the unmodified file passes, so the failures above come from the mutations.
mutate 'pass'
tools/validate_content.sh "$tmp" >/dev/null
echo "ok: unmodified gems.json passes"
