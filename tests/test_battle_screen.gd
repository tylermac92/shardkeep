extends GutTest
## The battle screen, driven through the real scene with mouse events.

const BattleScene := preload("res://client/battle/battle.tscn")


func test_gems_are_distinct_in_grayscale() -> void:
	var gems := range(Board.Gem.RED, Board.Gem.UNKNOWN + 1)
	var shapes := {}
	for g in gems:
		shapes[GemStyle.SHAPES[g]] = true
	assert_eq(shapes.size(), gems.size(), "every gem type has its own shape")
	assert_eq(GemStyle.COLORS.size(), gems.size())
	for a in range(Board.Gem.RED, Board.Gem.GOLD + 1):
		for b in range(a + 1, Board.Gem.GOLD + 1):
			var gap := absf(GemStyle.luma(GemStyle.COLORS[a]) - GemStyle.luma(GemStyle.COLORS[b]))
			assert_gt(gap, 0.05, "%s and %s are too close in brightness" % [Board.SYMBOLS[a], Board.SYMBOLS[b]])


func test_full_battle_with_the_mouse_against_easy() -> void:
	await _play_full_battle(AI.Level.EASY, 11)


func test_full_battle_with_the_mouse_against_normal() -> void:
	await _play_full_battle(AI.Level.NORMAL, 12)


func test_difficulty_buttons_start_a_battle_and_show_the_seed() -> void:
	var b := await _screen()
	assert_true(b._overlay.visible)
	_click_button(_button(b, "Easy"))
	assert_not_null(b.state)
	assert_eq(b.level, AI.Level.EASY)
	assert_false(b._overlay.visible)
	b.start_battle(4242, AI.Level.NORMAL)
	assert_string_contains(b._seed_label.text, "4242")


func test_instant_shows_the_same_board_as_1x() -> void:
	var content := ContentDB.content
	var s := Rules.new_battle(5, content, ["loadout_a", "loadout_b"])
	var views: Array[Array] = [_player_for(s, EventPlayer.Speed.INSTANT), _player_for(s, EventPlayer.Speed.NORMAL)]
	Engine.time_scale = 10.0  # 1x animations, played faster
	for k in 14:
		var out := Rules.apply(s, AI.choose(s, AI.Level.EASY))
		s = out.state
		for v in views:
			await v[0].play(out.events)
		for v in views:
			var board: BoardView = v[1]
			assert_eq(board.shown_gems(), s.board.gems, "move %d" % k)
			assert_eq(board.shown_specials(), s.board.special, "move %d" % k)
			for side in 2:
				var panel: SidePanel = v[0].panels[side]
				assert_eq(panel.shown("hp"), s.sides[side].hp)
				assert_eq(panel.shown("ap"), s.sides[side].action_points)
				for color in 4:
					assert_eq(panel.shown(Rules.MANA_KINDS[color]), s.sides[side].mana[color])
		if s.result != BattleState.Result.ONGOING:
			break
	Engine.time_scale = 1.0


func test_clicks_during_playback_or_the_ai_turn_do_nothing() -> void:
	var b := await _screen()
	b.min_think_msec = 400
	var applied: Array[int] = []
	b.action_applied.connect(func(side: int, _a: Action) -> void: applied.append(side))
	b.start_battle(_seed_with_a_plain_first_move(), AI.Level.EASY)
	var first := AI.choose(b.state, AI.Level.EASY)
	_click(_center(b, first.a))
	_click(_center(b, first.b))
	assert_eq(applied, [0])
	assert_false(b.accepting_input(), "locked during playback")
	_try_everything(b)
	await wait_seconds(0.2)  # mid-animation or thinking
	_try_everything(b)
	# Through the AI's thinking and its move's playback (where the state is already the player's).
	var settled := [false]
	b.settled.connect(func() -> void: settled[0] = true)
	while not settled[0]:
		_try_everything(b)
		await get_tree().process_frame
	assert_eq(applied.count(0), 1, "no extra player action got in")
	assert_gt(applied.count(1), 0)


func test_illegal_swap_snaps_back() -> void:
	var b := await _screen()
	b.player.speed = EventPlayer.Speed.INSTANT
	b.start_battle(_seed_with_a_plain_first_move(), AI.Level.EASY)
	var legal := Rules.legal_actions(b.state)
	var illegal := -1
	for c in Board.CELLS - 1:
		if c % Board.SIZE != Board.SIZE - 1 and not legal.any(func(a: Action) -> bool: return a.a == c and a.b == c + 1):
			illegal = c
			break
	var before := b.board_view.shown_gems()
	_click(_center(b, illegal))
	_click(_center(b, illegal + 1))
	assert_true(b.accepting_input(), "still the player's turn")
	assert_eq(b.state.turn, 0)
	await wait_seconds(BoardView.SNAP_SECONDS * 2 + 0.1)
	assert_eq(b.board_view.shown_gems(), before)


func test_ui_stays_responsive_while_the_ai_thinks() -> void:
	var b := await _screen()
	b.min_think_msec = 0
	b.player.speed = EventPlayer.Speed.INSTANT
	b.start_battle(_seed_with_a_plain_first_move(), AI.Level.NORMAL)
	var a := AI.choose(b.state, AI.Level.EASY)
	_click(_center(b, a.a))
	_click(_center(b, a.b))
	assert_eq(b.state.active_side, 1)
	var frames := 0
	var worst := 0
	var last := Time.get_ticks_usec()
	while not b.accepting_input() and b.state.result == BattleState.Result.ONGOING:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
	assert_gt(frames, 5, "the AI should take a few frames")
	assert_lt(worst, 50000, "a frame took %.1f ms" % (worst / 1000.0))


# --- helpers ---

func _play_full_battle(level: AI.Level, battle_seed: int) -> void:
	var b := await _screen()
	b.min_think_msec = 0
	_click_button(_button(b, "Instant"))
	assert_eq(b.player.speed, EventPlayer.Speed.INSTANT)
	var applied := {0: 0, 1: 0}
	b.action_applied.connect(func(side: int, _a: Action) -> void: applied[side] += 1)
	b.start_battle(battle_seed, level)
	var tries := 0
	while b.state.result == BattleState.Result.ONGOING and tries < 400:
		await _settled(b)
		if b.state.result != BattleState.Result.ONGOING:
			break
		var a := AI.choose(b.state, AI.Level.EASY)
		var before: int = applied[0]
		match a.kind:
			Action.Kind.SWAP:
				if tries % 2 == 0:
					_click(_center(b, a.a))
					_click(_center(b, a.b))
				else:
					_drag(_center(b, a.a), _center(b, a.b))
			Action.Kind.CAST, Action.Kind.ATTACK:
				_click_button(b.spell_bar.button(a.spell))
		assert_eq(applied[0], before + 1, "the mouse input became an action")
		tries += 1
	assert_ne(b.state.result, BattleState.Result.ONGOING, "the battle should end")
	assert_true(b._overlay.visible, "win or loss screen")
	assert_gt(applied[1], 0)


func _screen() -> BattleController:
	get_tree().root.size = Vector2i(1152, 648)  # headless starts at 64x64; use the game's window size
	var b: BattleController = BattleScene.instantiate()
	add_child_autofree(b)
	await get_tree().process_frame
	await get_tree().process_frame  # let containers lay out
	return b


## A battle seed where the player moves first and Easy's first move is a swap that ends the
## turn, so the AI moves next.
func _seed_with_a_plain_first_move() -> int:
	for n in 100:
		var s := Rules.new_battle(n, ContentDB.content, BattleController.LOADOUTS)
		var a := AI.choose(s, AI.Level.EASY)
		if s.active_side == 0 and a.kind == Action.Kind.SWAP and Rules.apply(s, a).state.active_side == 1:
			return n
	return -1


## Waits until the player can act or the battle is over.
func _settled(b: BattleController) -> void:
	var start := Time.get_ticks_msec()
	while not b.accepting_input() and b.state.result == BattleState.Result.ONGOING and Time.get_ticks_msec() - start < 20000:
		await get_tree().process_frame


func _player_for(s: BattleState, speed: EventPlayer.Speed) -> Array:
	var p := EventPlayer.new()
	p.board = BoardView.new()
	p.content = s.content
	p.speed = speed
	p.panels = [SidePanel.new("0"), SidePanel.new("1")]
	add_child_autofree(p)
	add_child_autofree(p.board)
	for side in 2:
		add_child_autofree(p.panels[side])
		p.panels[side].show_side(s.sides[side], s.content)
	p.board.show_board(s.board)
	return [p, p.board]


## Clicks every cell pair and button the player might use; none of it should do anything.
func _try_everything(b: BattleController) -> void:
	for a in Rules.legal_actions(b.state):
		if a.kind == Action.Kind.SWAP:
			_click(_center(b, a.a))
			_click(_center(b, a.b))
	for id in b.state.sides[0].spells + [&""]:
		var button := b.spell_bar.button(id)
		if button:
			_click_button(button)


func _center(b: BattleController, c: int) -> Vector2:
	return b.board_view.global_position + b.board_view.cell_center(c)


func _button(b: BattleController, text: String) -> Button:
	for n in b.find_children("*", "Button", true, false):
		if n.text == text:
			return n
	return null


## Headless Godot never moves a real mouse into the window, so buttons never see a hover;
## tell the button the mouse entered, then click it like any other control.
func _click_button(button: Button) -> void:
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_click(button.get_global_rect().get_center())
	button.notification(Control.NOTIFICATION_MOUSE_EXIT)


func _click(at: Vector2) -> void:
	_mouse_button(at, true)
	_mouse_button(at, false)


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse_button(from, true)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion)
	_mouse_button(to, false)


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = at
	e.global_position = at
	get_viewport().push_input(e)


func test_f9_exports_a_replay_of_the_battle_so_far() -> void:
	var b := await _screen()
	b.min_think_msec = 0
	b.player.speed = EventPlayer.Speed.INSTANT
	b.start_battle(77, AI.Level.EASY)
	for i in 3:
		await _settled(b)
		var a := AI.choose(b.state, AI.Level.EASY)
		if a.kind == Action.Kind.SWAP:
			_click(_center(b, a.a))
			_click(_center(b, a.b))
		else:
			_click_button(b.spell_bar.button(a.spell))
	await _settled(b)
	var key := InputEventKey.new()
	key.keycode = KEY_F9
	key.pressed = true
	get_viewport().push_input(key)
	assert_string_contains(b._message.text, "Replay saved to")
	var path := "%s/battle_77_%d.json" % [BattleController.EXPORT_DIR, b._history.size()]
	var r := Replay.play(JSON.parse_string(FileAccess.get_file_as_string(path)), ContentDB.content)
	assert_eq(r.error, "")
	assert_eq(r.state.state_hash(), b.state.state_hash())


func test_loadout_pick_and_fun_check_notes() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BattleController.NOTES_PATH))
	var b := await _screen()
	b.min_think_msec = 0
	b.player.speed = EventPlayer.Speed.INSTANT
	b._loadout_pick.select(1)
	_click_button(_button(b, "Easy"))
	assert_eq(b.loadouts, ["loadout_b", "loadout_a"])
	assert_eq(b.state.sides[0].weapon, &"mace")
	assert_false(b._notes.visible, "notes only after a battle")
	while b.state.result == BattleState.Result.ONGOING:
		await _settled(b)
		if b.accepting_input():
			b._player_act(AI.choose(b.state, AI.Level.EASY))
	assert_true(b._notes.visible)
	b._good.text = "Big cascade, \"wow\""
	b._bad.text = "Too long, slow"
	_click_button(_button(b, "Save notes"))
	_click_button(_button(b, "Save notes"))
	var lines := FileAccess.get_file_as_string(BattleController.NOTES_PATH).strip_edges().split("\n")
	assert_eq(lines.size(), 2, "a header and one row, saved once")
	assert_eq(lines[0], ",".join(BattleController.NOTES_COLUMNS))
	assert_string_contains(lines[1], "\"loadout_b\",\"loadout_a\",\"easy\"")
	assert_string_contains(lines[1], "\"Big cascade, \"\"wow\"\"\",\"Too long, slow\"")
	assert_string_contains(b._notes_status.text, "battle 1 of 30")
