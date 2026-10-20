class_name ContentLoader
extends RefCounted
## Reads and checks the JSON under res://content/. A plain class, so tools started
## with --script can load content without the autoload that wraps it.

const CONTENT_DIR := "res://content"
## The engine's gem type order; gem_weights is indexed by it.
const GEM_IDS := ["red", "blue", "green", "yellow", "skull", "action", "gold"]

## Entries of gems.json in file order: {id, spawn_weight, reward, amount}.
var gems: Array = []
## Default spawn weight per gem type, in GEM_IDS order.
var gem_weights := PackedInt32Array()


## Loads every content file. Returns an empty list on success, else one line per problem.
## Call validate() afterwards for the reference checks.
func load_all(dir: String = CONTENT_DIR) -> PackedStringArray:
	var errors := PackedStringArray()
	var data: Variant = _read_json(dir.path_join("gems.json"), errors)
	if data is Dictionary and data.get("gems") is Array:
		gems = data["gems"]
		gem_weights.resize(GEM_IDS.size())
		gem_weights.fill(0)
		for gem: Dictionary in gems:
			var i := GEM_IDS.find(gem.get("id"))
			if i >= 0:
				gem_weights[i] = int(gem.get("spawn_weight", 0))
	elif errors.is_empty():
		errors.append("gems.json: expected an object with a \"gems\" array")
	return errors


## Reference checks JSON Schema can't express. Run by content_lint.gd and at load in debug builds.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var total := 0
	for gem: Dictionary in gems:
		var id: String = gem.get("id", "")
		if seen.has(id):
			errors.append("gems.json: duplicate gem id \"%s\"" % id)
		seen[id] = true
		total += int(gem.get("spawn_weight", 0))
	if total <= 0:
		errors.append("gems.json: spawn weights must add up to more than 0")
	return errors


func _read_json(path: String, errors: PackedStringArray) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
