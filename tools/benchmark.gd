extends SceneTree
## AI decision time per level over a fixed set of positions (technical_design.md, Performance budget).
## Usage: godot --headless --script res://tools/benchmark.gd [-- --positions 200]

const LOADOUTS := ["loadout_a", "loadout_b"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--positions")
	var count := int(args[i + 1]) if i >= 0 and i + 1 < args.size() else 200
	var content := ContentLoader.new()
	var errors := content.load_all()
	if not errors.is_empty():
		printerr("benchmark: ", errors)
		quit(1)
		return
	var states := positions(content, count)
	var weights := [AI.weights_for(content.classes[LOADOUTS[0]]), AI.weights_for(content.classes[LOADOUTS[1]])]
	print("benchmark: %d positions" % states.size())
	for level in AI.Level.size():
		var total := 0
		var worst := 0
		for s in states:
			var start := Time.get_ticks_usec()
			AI.choose(s, level, weights[s.active_side])
			var took := Time.get_ticks_usec() - start
			total += took
			worst = maxi(worst, took)
		print("%-6s average %7.1f ms   worst %7.1f ms" % [AI.Level.keys()[level].to_lower(), total / 1000.0 / states.size(), worst / 1000.0])
	quit()


## count battle positions: seed n, loadout_a vs loadout_b, after 0 to 23 seeded random actions.
## The tests use these too.
static func positions(content: ContentLoader, count: int) -> Array[BattleState]:
	var out: Array[BattleState] = []
	for n in count:
		var s := Rules.new_battle(n, content, LOADOUTS)
		for k in n % 24:
			var actions := Rules.legal_actions(s)
			if actions.is_empty():
				break
			var next := Rules.apply(s, actions[Streams.mix(n, 0, k) % actions.size()]).state
			if next.result != BattleState.Result.ONGOING:
				break
			s = next
		out.append(s)
	return out
