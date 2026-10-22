class_name SidePanel
extends VBoxContainer
## One side's HP, four mana pools, action points, statuses and spells. During playback it
## follows resource_changed deltas; show_side() then sets it from the final state.

const KINDS := ["hp", "red", "blue", "green", "yellow"]

var _title := Label.new()
var _labels := {}
var _bars := {}
var _maxes := {"hp": 0, "red": 0, "blue": 0, "green": 0, "yellow": 0}
var _values := {"hp": 0, "red": 0, "blue": 0, "green": 0, "yellow": 0, "ap": 0, "gold": 0}
var _ap := Label.new()
var _statuses := Label.new()
var _spells := Label.new()


func _init(title: String) -> void:
	custom_minimum_size = Vector2(190, 0)
	_title.text = title
	_title.add_theme_font_size_override("font_size", 20)
	add_child(_title)
	for kind: String in KINDS:
		var label := Label.new()
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		var color: Color = Color8(220, 60, 60) if kind == "hp" else GemStyle.COLORS[Rules.MANA_KINDS.find(kind)]
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		bar.add_theme_stylebox_override("fill", fill)
		_labels[kind] = label
		_bars[kind] = bar
		add_child(label)
		add_child(bar)
	for label in [_ap, _statuses, _spells]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)


func show_side(side: SideState, content: ContentLoader) -> void:
	_maxes.hp = side.hp_max
	_values.hp = side.hp
	for color in Rules.MANA_KINDS.size():
		_maxes[Rules.MANA_KINDS[color]] = side.mana_cap[color]
		_values[Rules.MANA_KINDS[color]] = side.mana[color]
	_values.ap = side.action_points
	_values.gold = side.gold_gained
	var statuses := PackedStringArray()
	for st in side.statuses:
		statuses.append("%s (%d)" % [content.statuses[st.id].name, st.turns])
	_statuses.text = "Statuses: " + (", ".join(statuses) if statuses else "none")
	var spells := PackedStringArray()
	for i in side.spells.size():
		var def: Dictionary = content.spells[side.spells[i]]
		spells.append(def.name + (" (cooldown %d)" % side.cooldowns[i] if side.cooldowns[i] > 0 else ""))
	_spells.text = "Spells: " + ", ".join(spells)
	_refresh()


func apply_delta(kind: String, delta: int) -> void:
	if _values.has(kind):
		_values[kind] += delta
		_refresh()


## What the panel shows, by kind, for tests.
func shown(kind: String) -> int:
	return _values[kind]


func _refresh() -> void:
	for kind: String in KINDS:
		_labels[kind].text = "%s  %d / %d" % [kind.capitalize() if kind != "hp" else "HP", _values[kind], _maxes[kind]]
		_bars[kind].max_value = maxi(_maxes[kind], 1)
		_bars[kind].value = _values[kind]
	_ap.text = "Action points: %d    Gold: %d" % [_values.ap, _values.gold]
