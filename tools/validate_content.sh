#!/usr/bin/env bash
# Checks every content/<name>.json against schemas/<name>.schema.json.
# Usage: tools/validate_content.sh [content_dir]   (needs check-jsonschema)
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
for f in "${1:-content}"/*.json; do
	schema="schemas/$(basename "$f" .json).schema.json"
	if [[ ! -f $schema ]]; then
		echo "$f: no schema at $schema" >&2
		status=1
		continue
	fi
	check-jsonschema --schemafile "$schema" "$f" || status=1
done
exit $status
