class_name AITask
extends RefCounted
## Runs one AI decision as a WorkerThreadPool task so the UI never stalls, and holds the
## answer back until MIN_THINK_MSEC have passed so the AI doesn't feel instant.

const MIN_THINK_MSEC := 500

var _result: Array[Action] = []
var _task_id := -1
var _started := 0


func _init(state: BattleState, level: AI.Level, weights := AI.DEFAULT_WEIGHTS) -> void:
	var root := state.clone()  # the caller may move on to new states while this runs
	var result := _result
	_started = Time.get_ticks_msec()
	_task_id = WorkerThreadPool.add_task(func() -> void: result.append(AI.choose(root, level, weights)))


## Whether poll() has an answer yet.
func is_ready() -> bool:
	return Time.get_ticks_msec() - _started >= MIN_THINK_MSEC and (_task_id < 0 or WorkerThreadPool.is_task_completed(_task_id))


## The chosen action (null if the side had none) once ready; call it after is_ready().
func poll() -> Action:
	assert(is_ready(), "AITask.poll() before is_ready()")
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	return _result[0]


func _notification(what: int) -> void:
	# A pool task must be waited on exactly once, even if nobody polled.
	if what == NOTIFICATION_PREDELETE and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
