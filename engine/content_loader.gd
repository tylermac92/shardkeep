class_name ContentLoader
extends RefCounted
## Reads and checks the JSON under res://content/. A plain class, so tools started
## with --script can load content without the autoload that wraps it.

const CONTENT_DIR := "res://content"
## The engine's gem type order (Board.Gem); gem_weights and gem_defs are indexed by it.
const GEM_IDS := ["red", "blue", "green", "yellow", "skull", "action", "gold"]

## Entries of gems.json in file order: {id, spawn_weight, reward, amount}.
var gems: Array = []
## Default spawn weight per gem type, in GEM_IDS order.
var gem_weights := PackedInt32Array()
## gems.json entries by gem type; null where a type is missing.
var gem_defs: Array = []
## Bonus damage when a SKULL_BOMB goes off.
var skull_bomb_damage := 0


## Loads every content file. Returns an empty list on success, else one line per problem.
## Call validate() afterwards for the reference checks.
func load_all(dir: String = CONTENT_DIR) -> PackedStringArray:
	var errors := PackedStringArray()
	var data: Variant = _read_json(dir.path_join("gems.json"), errors)
	if data is Dictionary and data.get("gems") is Array:
		gems = data["gems"]
		skull_bomb_damage = int(data.get("skull_bomb_damage", 0))
		gem_weights.resize(GEM_IDS.size())
		gem_weights.fill(0)
		gem_defs.resize(GEM_IDS.size())
		gem_defs.fill(null)
		for gem: Dictionary in gems:
			var i := GEM_IDS.find(gem.get("id"))
			if i >= 0:
				gem_weights[i] = int(gem.get("spawn_weight", 0))
				gem_defs[i] = gem
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
		if gem.get("reward") == "mana" and GEM_IDS.find(id) > 3:
			errors.append("gems.json: \"%s\" can't pay mana; only red, blue, green and yellow can" % id)
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
