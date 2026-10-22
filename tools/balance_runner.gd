extends SceneTree
## Plays AI-vs-AI battles headless and reports balance numbers per matchup (technical_design.md,
## Balance runner). Games are split across --jobs worker processes (default: one per CPU core;
## GDScript threads in one process slow each other down instead) and merged by game number, so
## the output doesn't depend on the job count.
##
## Usage: godot --headless --script res://tools/balance_runner.gd -- [--matchups m.json]
##        [--games 1000] [--seed 1] [--level easy] [--out user://balance] [--jobs N]
##
## --games is per matchup. A matchups file looks like DEFAULT_MATCHUPS: a default "level" and a
## list of matchups, each with a "name", two "loadouts" (classes.json ids or inline class
## entries) and optionally its own "level". In odd-numbered games the loadouts swap sides, so
## each moves first half the time.
##
## Writes <out>/summary.csv (one row per matchup), <out>/<name>.csv (one row per battle) and
## <out>/<name>_extreme.json (the most extreme battle, for tools/replay.gd).

const DEFAULT_MATCHUPS := {
	"level": "easy",
	"matchups": [
		{"name": "a_vs_b", "loadouts": ["loadout_a", "loadout_b"]},
		{"name": "a_vs_a", "loadouts": ["loadout_a", "loadout_a"]},
		{"name": "b_vs_b", "loadouts": ["loadout_b", "loadout_b"]},
	],
}
## A battle still going after this many actions counts as a draw.
const MAX_ACTIONS := 500

# Flag thresholds, from the design doc's table.
const MIRROR_WIN_RATE := [0.45, 0.55]
const MIRROR_FIRST_MOVER_MAX := 0.55
const TURNS := [15.0, 40.0]
const CHAIN_MAX := 6
const CAST_SHARE_MIN := 0.10
const RESHUFFLES_MAX := 1.0
## Not in the doc: the doc only bounds mirrors, and this catches a broken loadout in any matchup.
const WIN_RATE := [0.30, 0.70]

const SUMMARY_COLUMNS := ["matchup", "level", "games", "win_rate", "first_mover_win_rate", "draws", "avg_turns", "longest_chain", "cast_share", "reshuffles_per_battle", "extreme_seed", "extreme_first", "extreme_turns", "flags"]
const BATTLE_COLUMNS := ["game", "seed", "first", "winner", "turns", "actions", "longest_chain", "casts", "reshuffles"]


func _initialize() -> void:
	var spec: Dictionary = DEFAULT_MATCHUPS
	var path := _arg("--matchups", "")
	if path:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is not Dictionary or not parsed.has("matchups"):
			printerr("balance_runner: %s isn't a matchups file" % path)
			quit(1)
			return
		spec = parsed
	if _arg("--level", ""):
		spec = spec.duplicate(true)
		spec.level = _arg("--level", "")
		for m: Dictionary in spec.matchups:
			m.erase("level")
	var content := ContentLoader.new()
	var errors := content.load_all()
	if not errors.is_empty():
		printerr("balance_runner: ", errors)
		quit(1)
		return
	var games := int(_arg("--games", "1000"))
	var base_seed := int(_arg("--seed", "1"))
	var out_dir := _arg("--out", "user://balance")
	var jobs := int(_arg("--jobs", str(OS.get_processor_count())))
	if _arg("--worker", "") != "":
		# A worker plays its share of the games and writes the raw results for the parent.
		var played := play_games(content, spec, games, base_seed, int(_arg("--worker", "0")), jobs)
		_save(_arg("--result", ""), JSON.stringify(played))
		quit()
		return
	var start := Time.get_ticks_msec()
	var battles := play_games(content, spec, games, base_seed) if jobs <= 1 else _play_in_workers(spec, games, base_seed, jobs, out_dir)
	if battles.is_empty():
		quit(1)
		return
	var report := summarize_all(spec, battles)
	write(report, out_dir, content)
	print("balance_runner: %d battles in %.1f s, CSVs in %s" % [games * report.size(), (Time.get_ticks_msec() - start) / 1000.0, ProjectSettings.globalize_path(out_dir)])
	for m in report:
		print("  %-12s win %5.1f%%  first mover %5.1f%%  turns %5.1f  chain %d  casts %4.1f%%  reshuffles %.2f" % [
			m.matchup, m.win_rate * 100, m.first_mover_win_rate * 100, m.avg_turns, m.longest_chain, m.cast_share * 100, m.reshuffles_per_battle])
	var flagged := report.filter(func(m: Dictionary) -> bool: return not m.flags.is_empty())
	print("Flags:" if flagged else "Flags: none")
	for m in flagged:
		for f in m.flags:
			print("  %s: %s" % [m.matchup, f])
	quit()


## Plays every matchup in-process and returns one summary per matchup (with its battles under "battles").
static func run(content: ContentLoader, spec: Dictionary, games: int, base_seed: int) -> Array[Dictionary]:
	return summarize_all(spec, play_games(content, spec, games, base_seed))


## Plays the games numbered worker, worker + jobs, ... of every matchup. Returns
## {"<matchup index>": {"<game>": stats}} (string keys, so it survives JSON).
static func play_games(content: ContentLoader, spec: Dictionary, games: int, base_seed: int, worker := 0, jobs := 1) -> Dictionary:
	var out := {}
	for k in spec.matchups.size():
		var m: Dictionary = spec.matchups[k]
		var level := _level(m.get("level", spec.get("level", "easy")))
		var played := {}
		for i in range(worker, games, jobs):
			var order: Array = m.loadouts if i % 2 == 0 else [m.loadouts[1], m.loadouts[0]]
			var r := play_battle(content, Streams.mix(base_seed, k, i), order, [level, level])
			r["first"] = i % 2  # which of the matchup's loadouts moved first
			played[str(i)] = r
		out[str(k)] = played
	return out


static func summarize_all(spec: Dictionary, battles: Dictionary) -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for k in spec.matchups.size():
		var m: Dictionary = spec.matchups[k]
		var played: Dictionary = battles[str(k)]
		var ordered := []
		for i in played.size():
			ordered.append(played[str(i)])
		report.append(summarize(m, _level(m.get("level", spec.get("level", "easy"))), ordered))
	return report


## Runs jobs copies of this script, each on its share of the games, and merges what they write.
static func _play_in_workers(spec: Dictionary, games: int, base_seed: int, jobs: int, out_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var spec_path := ProjectSettings.globalize_path(out_dir.path_join("_matchups.json"))
	_save(spec_path, JSON.stringify(spec))
	var pids := []
	var results := []
	for j in jobs:
		var result := ProjectSettings.globalize_path(out_dir.path_join("_worker_%d.json" % j))
		DirAccess.remove_absolute(result)
		results.append(result)
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tools/balance_runner.gd", "--", "--matchups", spec_path, "--games", str(games), "--seed", str(base_seed),
			"--jobs", str(jobs), "--worker", str(j), "--result", result]))
	for pid in pids:
		while OS.is_process_running(pid):
			OS.delay_msec(200)
	var merged := {}
	for j in jobs:
		var part: Variant = JSON.parse_string(FileAccess.get_file_as_string(results[j]))
		DirAccess.remove_absolute(results[j])
		if part is not Dictionary:
			printerr("balance_runner: worker %d wrote no results (see its output above)" % j)
			return {}
		for k: String in part:
			if not merged.has(k):
				merged[k] = {}
			for i: String in part[k]:
				merged[k][i] = _ints(part[k][i])
	DirAccess.remove_absolute(spec_path)
	return merged


## JSON reads every number as a float; the stats are whole numbers.
static func _ints(stats: Dictionary) -> Dictionary:
	for key in stats:
		if stats[key] is float:
			stats[key] = int(stats[key])
	return stats


## One battle, AI against AI. levels and loadouts are by side; side 0 moves first.
## With record set, the result also holds the actions (for a replay file).
static func play_battle(content: ContentLoader, battle_seed: int, loadouts: Array, levels: Array, record := false) -> Dictionary:
	var s := Rules.new_battle(battle_seed, content, loadouts)
	var weights := []
	for l in loadouts:
		weights.append(AI.weights_for(l if l is Dictionary else content.classes[l]))
	var actions: Array[Action] = []
	var stats := {"seed": battle_seed, "loadouts": loadouts, "actions": 0, "casts": 0, "reshuffles": 0, "longest_chain": 0}
	var chain := 0
	while s.result == BattleState.Result.ONGOING and stats.actions < MAX_ACTIONS:
		var a := AI.choose(s, levels[s.active_side], weights[s.active_side])
		var out := Rules.apply(s, a)
		for e in out.events:
			match e.type:
				"extra_turn":
					chain += 1
					stats.longest_chain = maxi(stats.longest_chain, chain)
				"turn_passed":
					chain = 0
				"reshuffled":
					stats.reshuffles += 1
		stats.actions += 1
		stats.casts += int(a.kind == Action.Kind.CAST)
		if record:
			actions.append(a)
		s = out.state
	stats["turns"] = s.turn
	stats["winner"] = -1 if s.result == BattleState.Result.ONGOING else (0 if s.result == BattleState.Result.SIDE0_WON else 1)
	stats["hash"] = s.state_hash().hex_encode()
	if record:
		stats["action_list"] = actions
	return stats


## Aggregates a matchup's battles and checks them against the thresholds.
static func summarize(m: Dictionary, level: AI.Level, battles: Array) -> Dictionary:
	var n := battles.size()
	var first_wins := 0  # the matchup's first loadout won
	var mover_wins := 0  # side 0, the side that moved first, won
	var draws := 0
	var turns := 0
	var actions := 0
	var casts := 0
	var reshuffles := 0
	var chain := 0
	var extreme := 0
	for i in n:
		var b: Dictionary = battles[i]
		if b.winner < 0:
			draws += 1
		else:
			mover_wins += int(b.winner == 0)
			first_wins += int((b.winner == 0) == (b.first == 0))
		turns += b.turns
		actions += b.actions
		casts += b.casts
		reshuffles += b.reshuffles
		chain = maxi(chain, b.longest_chain)
		var e: Dictionary = battles[extreme]
		if b.turns > e.turns or (b.turns == e.turns and b.longest_chain > e.longest_chain):
			extreme = i  # the longest battle, then the longest extra-turn chain
	var s := {
		"matchup": m.name, "level": AI.Level.keys()[level].to_lower(), "games": n,
		"win_rate": float(first_wins) / n, "first_mover_win_rate": float(mover_wins) / n, "draws": draws,
		"avg_turns": float(turns) / n, "longest_chain": chain, "cast_share": float(casts) / maxi(actions, 1),
		"reshuffles_per_battle": float(reshuffles) / n,
		"extreme_seed": battles[extreme].seed, "extreme_first": battles[extreme].first, "extreme_turns": battles[extreme].turns,
		"extreme_loadouts": battles[extreme].loadouts, "battles": battles,
	}
	s["flags"] = flags(s, JSON.stringify(m.loadouts[0]) == JSON.stringify(m.loadouts[1]))
	return s


static func flags(s: Dictionary, mirror: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if mirror:
		if s.win_rate < MIRROR_WIN_RATE[0] or s.win_rate > MIRROR_WIN_RATE[1]:
			out.append("win rate %.1f%% in a mirror match (want 45-55%%)" % (s.win_rate * 100))
		if s.first_mover_win_rate > MIRROR_FIRST_MOVER_MAX:
			out.append("first mover wins %.1f%% of mirror matches (want at most 55%%)" % (s.first_mover_win_rate * 100))
	elif s.win_rate < WIN_RATE[0] or s.win_rate > WIN_RATE[1]:
		out.append("win rate %.1f%% (want 30-70%%)" % (s.win_rate * 100))
	if s.avg_turns < TURNS[0] or s.avg_turns > TURNS[1]:
		out.append("%.1f turns per battle (want 15-40)" % s.avg_turns)
	if s.longest_chain > CHAIN_MAX:
		out.append("extra-turn chain of %d (want at most 6)" % s.longest_chain)
	if s.cast_share < CAST_SHARE_MIN:
		out.append("spell casts are %.1f%% of actions (want at least 10%%)" % (s.cast_share * 100))
	if s.reshuffles_per_battle > RESHUFFLES_MAX:
		out.append("%.2f reshuffles per battle (want at most 1)" % s.reshuffles_per_battle)
	return out


## Writes the CSVs and each matchup's extreme battle as a replay file.
static func write(report: Array[Dictionary], out_dir: String, content: ContentLoader) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var rows := PackedStringArray([",".join(SUMMARY_COLUMNS)])
	for m in report:
		rows.append(",".join(SUMMARY_COLUMNS.map(func(c: String) -> String: return _cell(m[c]))))
		var battle_rows := PackedStringArray([",".join(BATTLE_COLUMNS)])
		for i in m.battles.size():
			var b: Dictionary = m.battles[i]
			b["game"] = i
			battle_rows.append(",".join(BATTLE_COLUMNS.map(func(c: String) -> String: return _cell(b[c]))))
		_save(out_dir.path_join("%s.csv" % m.matchup), "\n".join(battle_rows) + "\n")
		var levels := [_level(m.level), _level(m.level)]
		var extreme := play_battle(content, m.extreme_seed, m.extreme_loadouts, levels, true)
		var rec := Replay.record(m.extreme_seed, m.extreme_loadouts, extreme.action_list, content)
		rec["levels"] = [m.level, m.level]
		_save(out_dir.path_join("%s_extreme.json" % m.matchup), Replay.to_json(rec))
	_save(out_dir.path_join("summary.csv"), "\n".join(rows) + "\n")


static func _cell(v: Variant) -> String:
	if v is float:
		return "%.4f" % v
	if v is PackedStringArray:
		return "\"%s\"" % "; ".join(v)
	return str(v)


static func _save(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("balance_runner: can't write %s" % path)
		return
	f.store_string(text)


static func _level(name: Variant) -> AI.Level:
	return AI.Level.get(str(name).to_upper(), AI.Level.EASY)


func _arg(name: String, default: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else default
