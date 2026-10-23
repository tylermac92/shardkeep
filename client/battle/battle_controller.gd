class_name BattleController
extends Control
## Owns the battle state and the turn flow (technical_design.md, Client): input becomes an
## action, Rules.apply() gives the new state at once, and EventPlayer animates the events.
## Side 0 is the player, side 1 the AI.

signal action_applied(side: int, action: Action)
## Emitted when the screen waits for the player, or the battle has ended.
signal settled

const LOADOUTS := ["loadout_a", "loadout_b"]
## Fun-check notes, one row per battle (docs/m0_task_list.md, T11).
const NOTES_PATH := "user://fun_check.csv"
const NOTES_COLUMNS := ["battle", "date", "seed", "you", "enemy", "difficulty", "result", "turns", "felt_good", "felt_bad"]
const EXPORT_KEY := KEY_F9
const EXPORT_DIR := "user://replays"

var state: BattleState
var level := AI.Level.NORMAL
## Minimum AI think time. Tests lower it.
var min_think_msec := AITask.MIN_THINK_MSEC
var content: ContentLoader = ContentDB.content

var board_view := BoardView.new()
var spell_bar := SpellBar.new()
var player := EventPlayer.new()
var panels: Array[SidePanel] = [SidePanel.new("You"), SidePanel.new("Enemy")]

var _busy := true  # playing back, or the AI's turn: input does nothing
var _battle := 0  # bumped per battle, so a restart drops the old battle's pending turn
var _ai_tasks: Array[AITask] = []  # searches still running, joined if the screen closes mid-think
var _seed_label := Label.new()
var _message := Label.new()
var _overlay := PanelContainer.new()
var _result := Label.new()
var _speed_buttons: Array[Button] = []
var _seed := 0
## [player's loadout, enemy's loadout]; the player moves first.
var loadouts: Array = LOADOUTS.duplicate()
var _loadout_pick := OptionButton.new()
var _notes := VBoxContainer.new()
var _good := LineEdit.new()
var _bad := LineEdit.new()
var _notes_status := Label.new()
var _notes_saved := true
var _history: Array[Action] = []  # every action this battle, both sides, for replay export


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.add_child(panels[0])
	left.add_child(spell_bar)
	row.add_child(left)

	var center := VBoxContainer.new()
	var top := HBoxContainer.new()
	top.add_child(_seed_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var group := ButtonGroup.new()
	for i in 3:
		var b := Button.new()
		b.text = ["1x", "2x", "Instant"][i]
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func() -> void: player.speed = i as EventPlayer.Speed)
		_speed_buttons.append(b)
		top.add_child(b)
	_speed_buttons[0].button_pressed = true
	center.add_child(top)
	_message.custom_minimum_size = Vector2(BoardView.CELL * Board.SIZE, 0)
	center.add_child(_message)
	center.add_child(board_view)
	row.add_child(center)
	row.add_child(panels[1])

	_build_overlay()
	add_child(player)
	player.board = board_view
	player.panels = panels
	player.content = content
	player.message.connect(func(text: String) -> void: _message.text = text)
	board_view.swap_requested.connect(func(a: int, b: int) -> void: _player_act(Action.swap(a, b)))
	spell_bar.cast_requested.connect(func(id: StringName) -> void: _player_act(Action.cast(id)))
	spell_bar.attack_requested.connect(func() -> void: _player_act(Action.attack()))
	_show_overlay("Shardkeep")


## Starts a battle against the AI at this level, the player using player_loadout (the enemy
## gets the other one; empty keeps the last choice). A negative seed picks one at random.
func start_battle(battle_seed: int, ai_level: AI.Level, player_loadout := "") -> void:
	if not _notes_saved and (_good.text or _bad.text):
		save_notes()
	_notes.hide()
	if player_loadout:
		loadouts = [player_loadout, LOADOUTS[1] if player_loadout == LOADOUTS[0] else LOADOUTS[0]]
	level = ai_level
	_battle += 1
	if battle_seed < 0:
		battle_seed = randi()
	_seed = battle_seed
	_history.clear()
	state = Rules.new_battle(battle_seed, content, loadouts)
	_seed_label.text = "Seed %d    %s    you: %s" % [battle_seed, AI.Level.keys()[level].capitalize(), content.classes[loadouts[0]].name]
	_overlay.hide()
	spell_bar.setup(state.sides[0], content)
	board_view.show_board(state.board)
	_refresh()
	_next()


## Writes this battle so far (seed, loadouts, actions, state hashes) to a JSON file that
## tools/replay.gd replays. Returns its path, or "" if it couldn't be written.
func export_replay() -> String:
	if state == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	var path := EXPORT_DIR.path_join("battle_%d_%d.json" % [_seed, _history.size()])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(Replay.to_json(Replay.record(_seed, loadouts, _history, content)))
	return path


func _exit_tree() -> void:
	# Wait here, in ordinary code: freeing the screen frees its coroutines, and with them any
	# search still running, which mustn't block (see AITask).
	for task in _ai_tasks:
		task.join()
	_ai_tasks.clear()
	AITask.join_orphans()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == EXPORT_KEY and OS.is_debug_build():
		var path := export_replay()
		_message.text = "Replay saved to " + ProjectSettings.globalize_path(path) if path else "Couldn't save the replay"
		get_viewport().set_input_as_handled()


## Whether a click or button press would be acted on right now.
func accepting_input() -> bool:
	return not _busy and state != null and state.result == BattleState.Result.ONGOING and state.active_side == 0


func _player_act(action: Action) -> void:
	if not accepting_input():
		return
	if Rules.apply(state, action) == null:
		if action.kind == Action.Kind.SWAP:
			board_view.snap_back(action.a, action.b)
		return
	_act(action)


func _act(action: Action) -> void:
	var out := Rules.apply(state, action)
	if out == null:
		push_error("BattleController: illegal action from side %d" % state.active_side)
		return
	_lock()
	var side := state.active_side
	var battle := _battle
	state = out.state
	_history.append(action)
	action_applied.emit(side, action)
	await player.play(out.events)
	if battle != _battle:
		return
	_refresh()
	_next()


func _next() -> void:
	if state.result != BattleState.Result.ONGOING:
		_show_overlay("Victory!" if state.result == BattleState.Result.SIDE0_WON else "Defeat")
		_good.text = ""
		_bad.text = ""
		_notes_saved = false
		_notes_status.text = ""
		_notes.show()
		settled.emit()
		return
	var legal := Rules.legal_actions(state)
	if legal.size() == 1 and legal[0].kind == Action.Kind.PASS:
		_message.text = ("You are" if state.active_side == 0 else "The enemy is") + " stunned"
		_act(legal[0])
	elif state.active_side == 1:
		_ai_turn()
	else:
		_busy = false
		board_view.input_enabled = true
		spell_bar.update(legal)
		settled.emit()


func _ai_turn() -> void:
	_lock()
	_message.text = "The enemy is thinking..."
	var battle := _battle
	var task := AITask.new(state, level, AI.weights_for(content.classes[loadouts[1]]), min_think_msec)
	_ai_tasks.append(task)
	while not task.is_ready():
		await get_tree().process_frame
	var action := task.poll()
	_ai_tasks.erase(task)
	if battle == _battle:
		_act(action)


func _lock() -> void:
	_busy = true
	board_view.input_enabled = false
	spell_bar.update([])


func _refresh() -> void:
	for i in 2:
		panels[i].show_side(state.sides[i], content)
	board_view.show_ghost_row(Rules.ghost_row(state))


func _build_overlay() -> void:
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.97)
	style.border_color = Color(1, 1, 1, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	_overlay.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_result.add_theme_font_size_override("font_size", 32)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result)
	_good.placeholder_text = "What felt good?"
	_bad.placeholder_text = "What felt bad?"
	var save := Button.new()
	save.text = "Save notes"
	save.pressed.connect(save_notes)
	for c in [_good, _bad, save, _notes_status]:
		_notes.add_child(c)
	_notes.hide()
	box.add_child(_notes)
	var pick := HBoxContainer.new()
	var you := Label.new()
	you.text = "You play"
	pick.add_child(you)
	for id: String in LOADOUTS:
		_loadout_pick.add_item(content.classes[id].name)
	_loadout_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_child(_loadout_pick)
	box.add_child(pick)
	var hint := Label.new()
	hint.text = "Choose a difficulty to start a battle"
	box.add_child(hint)
	for lv in [AI.Level.EASY, AI.Level.NORMAL]:
		var b := Button.new()
		b.text = AI.Level.keys()[lv].capitalize()
		b.pressed.connect(func() -> void: start_battle(-1, lv, LOADOUTS[_loadout_pick.selected]))
		box.add_child(b)
	_overlay.add_child(box)
	add_child(_overlay)


## Appends this battle's fun-check notes to NOTES_PATH. Returns the file's path, or "".
func save_notes() -> String:
	if state == null or state.result == BattleState.Result.ONGOING:
		return ""
	if _notes_saved:
		return NOTES_PATH  # already written; don't add the row twice
	var exists := FileAccess.file_exists(NOTES_PATH)
	var f := FileAccess.open(NOTES_PATH, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		_notes_status.text = "Couldn't save the notes"
		return ""
	var rows := 0
	if exists:
		rows = f.get_as_text().strip_edges().split("\n").size() - 1
		f.seek_end()
	else:
		f.store_line(",".join(NOTES_COLUMNS))
	var cells := [rows + 1, Time.get_datetime_string_from_system(), _seed, loadouts[0], loadouts[1],
		AI.Level.keys()[level].to_lower(), "win" if state.result == BattleState.Result.SIDE0_WON else "loss", state.turn, _good.text, _bad.text]
	f.store_line(",".join(cells.map(func(v: Variant) -> String: return "\"%s\"" % str(v).replace("\"", "\"\""))))
	_notes_saved = true
	_notes_status.text = "Saved battle %d of 30 to %s" % [rows + 1, ProjectSettings.globalize_path(NOTES_PATH)]
	return NOTES_PATH


func _show_overlay(title: String) -> void:
	_result.text = title
	_overlay.show()
