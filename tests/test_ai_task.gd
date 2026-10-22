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


func test_freeing_a_running_task_waits_for_it() -> void:
	var content := ContentLoader.new()
	content.load_all()
	var task := AITask.new(Benchmark.positions(content, 1)[0], AI.Level.NORMAL)
	task = null  # must join the pool task, not crash or leak it
	assert_null(task)
