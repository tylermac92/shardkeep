extends SceneTree
## Replays a battle export headless and prints its final state hash (technical_design.md,
## Replay tests). Exits 1, saying where it went differently, if it no longer matches.
## Usage: godot --headless --script res://tools/replay.gd -- <file.json> [--write]
## --write re-records the file's hashes with the current rules and content, for a change made on purpose.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var paths := Array(args).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if paths.is_empty():
		printerr("usage: godot --headless --script res://tools/replay.gd -- <file.json> [--write]")
		quit(2)
		return
	var path: String = paths[0]
	var text := FileAccess.get_file_as_string(path)
	var rec: Variant = JSON.parse_string(text)
	if rec is not Dictionary:
		printerr("%s: can't read a replay from this file" % path)
		quit(1)
		return
	var content := ContentLoader.new()
	var errors := content.load_all()
	if not errors.is_empty():
		printerr("replay: ", errors)
		quit(1)
		return
	if "--write" in args:
		var actions: Array[Action] = []
		for d in rec.actions:
			actions.append(Replay.from_dict(d))
		var fresh := Replay.record(int(rec.seed), rec.loadouts, actions, content)
		if fresh.is_empty():
			printerr("%s: an action is no longer legal, so it can't be re-recorded" % path)
			quit(1)
			return
		FileAccess.open(path, FileAccess.WRITE).store_string(Replay.to_json(fresh))
		print("%s: re-recorded, %s" % [path, fresh.hash])
		quit()
		return
	var r := Replay.play(rec, content)
	if not r.error:
		print("%s: %d actions, final state %s" % [path, rec.actions.size(), r.state.state_hash().hex_encode()])
	if r.error:
		printerr("%s: %s" % [path, r.error])
	quit(1 if r.error else 0)
