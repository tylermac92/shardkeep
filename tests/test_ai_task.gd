extends GutTest

const Benchmark := preload("res://tools/benchmark.gd")


func test_decides_off_thread_after_the_minimum_think_time() -> void:
	var content := ContentLoader.new()
	content.load_all()
	var s: BattleState = Benchmark.positions(content, 3)[2]
	var start := Time.get_ticks_msec()
	var task := AITask.new(s, AI.Level.EASY)
	assert_false(task.is_ready(), "never ready before the think time")
	while not task.is_ready() and Time.get_ticks_msec() - start < 10000:
		await wait_physics_frames(1)
	assert_gte(Time.get_ticks_msec() - start, AITask.MIN_THINK_MSEC)
	var a := task.poll()
	var direct := AI.choose(s, AI.Level.EASY)
	assert_eq([a.kind, a.a, a.b, a.spell], [direct.kind, direct.a, direct.b, direct.spell])


func test_freeing_a_running_task_never_blocks_and_is_joined_later() -> void:
	var content := ContentLoader.new()
	content.load_all()
	var task := AITask.new(Benchmark.positions(content, 1)[0], AI.Level.NORMAL)
	var start := Time.get_ticks_msec()
	task = null
	assert_lt(Time.get_ticks_msec() - start, 50, "freeing a running search doesn't wait for it")
	assert_eq(AITask._orphans.size(), 1)
	AITask.join_orphans()
	assert_eq(AITask._orphans.size(), 0)


func test_closing_the_battle_screen_mid_think() -> void:
	var seed := 0
	while Rules.new_battle(seed, ContentDB.content, BattleController.LOADOUTS).active_side != 1:
		seed += 1
	var b: BattleController = preload("res://client/battle/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	b.start_battle(seed, AI.Level.NORMAL)  # the AI moves first and starts thinking
	assert_false(b.accepting_input())
	b.free()  # used to deadlock: freeing the coroutine freed a running search that waited on itself
	assert_eq(AITask._orphans.size(), 0, "the screen joined its search on the way out")
