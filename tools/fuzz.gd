extends SceneTree
## AI-vs-AI fuzzing (technical_design.md, Fuzz tests): random loadouts, Easy AI on both sides,
## invariants checked before every action. A failure writes a replay file of the battle so far.
## Usage: godot --headless --script res://tools/fuzz.gd [-- --actions 10000 --seed 1 --out DIR]

const MAX_BATTLE_ACTIONS := 400


func _initialize() -> void:
	var actions := int(_arg("--actions", "10000"))
	var base_seed := int(_arg("--seed", "1"))
	var out_dir := _arg("--out", "user://fuzz_failures")
	var content := ContentLoader.new()
	var errors := content.load_all()
	if not errors.is_empty():
		printerr("fuzz: ", errors)
		quit(1)
		return
	var start := Time.get_ticks_msec()
	var r := run(content, actions, base_seed, out_dir)
	print("fuzz: %d actions in %d battles, %.1f s" % [r.actions, r.battles, (Time.get_ticks_msec() - start) / 1000.0])
	if r.error:
		printerr("fuzz: FAILED: %s" % r.error)
		printerr("fuzz: replay with: godot --headless --script res://tools/replay.gd -- %s" % ProjectSettings.globalize_path(r.path))
	quit(1 if r.error else 0)


## Plays battles until max_actions actions have been taken. extra_check(state) -> String can
## add an invariant (tests use it to force a failure). Returns {actions, battles, error, path}.
static func run(content: ContentLoader, max_actions: int, base_seed: int, out_dir: String, extra_check := Callable()) -> Dictionary:
	var total := 0
	var battle := 0
	while total < max_actions:
		var battle_seed := Streams.mix(base_seed, 0, battle)
		var loadouts := [random_loadout(content, base_seed, battle * 2), random_loadout(content, base_seed, battle * 2 + 1)]
		var s := Rules.new_battle(battle_seed, content, loadouts)
		var actions: Array[Action] = []
		var error := ""
		var failed: Action = null
		while total < max_actions and actions.size() < MAX_BATTLE_ACTIONS:
			error = check(s)
			if error == "" and extra_check.is_valid():
				error = extra_check.call(s)
			if error or s.result != BattleState.Result.ONGOING:
				break
			var a := AI.choose(s, AI.Level.EASY)
			var before := s.state_hash()
			var o := Rules.apply(s, a) if a else null
			if o == null:
				error = "the AI's action (%s) was rejected" % Replay.describe(a)
				failed = a
			elif s.state_hash() != before:
				error = "apply() changed the state it was given (%s)" % Replay.describe(a)
				failed = a
			if error:
				break
			actions.append(a)
			s = o.state
			total += 1
		if error == "":
			var replayed := Replay.play(Replay.record(battle_seed, loadouts, actions, content), content)
			if replayed.error or replayed.state.state_hash() != s.state_hash():
				error = "replaying the battle gave a different state %s" % replayed.error
		if error:
			error = "battle %d (seed %d), before action %d: %s" % [battle, battle_seed, actions.size(), error]
			return {"actions": total, "battles": battle + 1, "error": error, "path": _save_failure(out_dir, battle_seed, loadouts, actions, failed, error, content)}
		battle += 1
	return {"actions": total, "battles": battle, "error": "", "path": ""}


## Rules that must hold before every action. Returns what's wrong, or "".
static func check(s: BattleState) -> String:
	if not s.sim_draw_budget.is_empty():
		return "search fog is set on a real state"
	if s.board.gems.has(Board.Gem.UNKNOWN):
		return "UNKNOWN gem outside AI search"
	for i in 2:
		var side := s.sides[i]
		if side.hp < 0 or side.hp > side.hp_max:
			return "side %d HP %d outside 0..%d" % [i, side.hp, side.hp_max]
		for c in 4:
			if side.mana[c] < 0 or side.mana[c] > side.mana_cap[c]:
				return "side %d %s mana %d outside 0..%d" % [i, Rules.MANA_KINDS[c], side.mana[c], side.mana_cap[c]]
		if side.action_points < 0 or Array(side.cooldowns).any(func(cd: int) -> bool: return cd < 0):
			return "side %d has negative action points or cooldown" % i
	if s.result != BattleState.Result.ONGOING:
		return ""
	if s.board.gems.has(Board.Gem.EMPTY):
		return "board has an empty cell"
	if not Matcher.find_groups(s.board).is_empty():
		return "board has a ready-made match"
	if Rules._swaps(s.board, true).is_empty():
		return "board has no legal swap"
	return ""


## A random loadout from the real content: HP, mana caps, stats, any of the spells, maybe a weapon.
static func random_loadout(content: ContentLoader, base_seed: int, n: int) -> Dictionary:
	var rolls := PackedInt64Array()
	for k in 16:
		rolls.append(Streams.mix(base_seed, 1000 + n, k))
	var caps := {}
	for i in Rules.MANA_KINDS.size():
		caps[Rules.MANA_KINDS[i]] = 10 + rolls[i] % 16
	var spells := []
	var ids := content.spells.keys()
	for i in ids.size():
		if rolls[(4 + i) % rolls.size()] % 2 == 0:
			spells.append(str(ids[i]))
	var weapons := content.weapons.keys()
	var weapon := "" if rolls[13] % 4 == 0 else str(weapons[rolls[14] % weapons.size()])
	var mastery := {}
	for i in Rules.MANA_KINDS.size():
		mastery[Rules.MANA_KINDS[i]] = (rolls[i] >> 8) % 8
	var stats := {"might": (rolls[13] >> 8) % 5, "vitality": (rolls[14] >> 8) % 5, "cunning": (rolls[15] >> 8) % 6, "mastery": mastery}
	return {"hp": 20 + rolls[15] % 41, "mana_cap": caps, "spells": spells, "weapon": weapon, "stats": stats}


static func _save_failure(out_dir: String, battle_seed: int, loadouts: Array, actions: Array[Action], failed: Action, error: String, content: ContentLoader) -> String:
	var rec := Replay.record(battle_seed, loadouts, actions, content)
	rec["error"] = error
	if failed:
		rec["failed_action"] = Replay.to_dict(failed)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path := out_dir.path_join("fuzz_%d.json" % battle_seed)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(Replay.to_json(rec))
	return path


func _arg(name: String, default: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default
