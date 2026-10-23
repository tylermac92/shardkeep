class_name AITask
extends RefCounted
## Runs one AI decision as a WorkerThreadPool task so the UI never stalls, and holds the
## answer back until the minimum think time (MIN_THINK_MSEC by default) has passed so the AI
## doesn't feel instant.
##
## Every pool task must be waited on once before the game exits. Freeing an AITask never
## waits (that can deadlock when GDScript frees it while tearing down a coroutine); its task
## is left to the next AITask or to join_orphans(), which the battle screen calls on exit.

const MIN_THINK_MSEC := 500

## Tasks whose AITask was freed before they were waited on.
static var _orphans: Array[int] = []

var _result: Array[Action] = []
var _task_id := -1
var _started := 0
var _min_think_msec: int


func _init(state: BattleState, level: AI.Level, weights := AI.DEFAULT_WEIGHTS, min_think_msec := MIN_THINK_MSEC) -> void:
	_min_think_msec = min_think_msec
	_reap()
	var root := state.clone()  # the caller may move on to new states while this runs
	_started = Time.get_ticks_msec()
	# A static function, so the running search doesn't depend on this object staying alive.
	_task_id = WorkerThreadPool.add_task(Callable(AITask, "_search").bind(root, level, weights, _result))


## Whether poll() has an answer yet.
func is_ready() -> bool:
	return Time.get_ticks_msec() - _started >= _min_think_msec and (_task_id < 0 or WorkerThreadPool.is_task_completed(_task_id))


## The chosen action (null if the side had none) once ready; call it after is_ready().
func poll() -> Action:
	assert(is_ready(), "AITask.poll() before is_ready()")
	join()
	return _result[0]


## Blocks until the search is done. Safe from ordinary code, not from a destructor.
func join() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Blocks until every abandoned search is done. Call it before exiting.
static func join_orphans() -> void:
	for id in _orphans:
		WorkerThreadPool.wait_for_task_completion(id)
	_orphans.clear()


static func _search(root: BattleState, level: AI.Level, weights: Dictionary, result: Array[Action]) -> void:
	result.append(AI.choose(root, level, weights))


## Waits on abandoned tasks that have already finished, so it never blocks.
static func _reap() -> void:
	for id in _orphans.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_orphans.erase(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_id >= 0:
		_orphans.append(_task_id)
