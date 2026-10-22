#!/usr/bin/env bash
# Proves the CI lints catch what they should: banned calls in engine/ and malformed content.
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

mutate() { # <file> <python statement on dict d>: writes a changed copy of content/ to $tmp
	rm -f "$tmp"/*.json
	cp content/*.json "$tmp"/
	python3 -c "import json; d=json.load(open('content/$1')); $2; json.dump(d, open('$tmp/$1','w'))"
}
mutate gems.json 'd["gems"][0]["spawn_weight"] = "16"'
expect_fail "gems.json with a wrong type" tools/validate_content.sh "$tmp"
mutate gems.json 'del d["gems"][0]["reward"]'
expect_fail "gems.json with a missing field" tools/validate_content.sh "$tmp"
mutate spells.json 'd["spells"][0]["effects"][0]["op"] = "teleport"'
expect_fail "spells.json with an unknown effect op" tools/validate_content.sh "$tmp"
mutate spells.json 'del d["spells"][0]["effects"][0]["per"]'
expect_fail "spells.json with an effect missing a parameter" tools/validate_content.sh "$tmp"

# Sanity: unmodified content passes, so the failures above come from the mutations.
mutate gems.json 'pass'
tools/validate_content.sh "$tmp" >/dev/null
echo "ok: unmodified content passes"
