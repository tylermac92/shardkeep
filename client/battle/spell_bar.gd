class_name SpellBar
extends VBoxContainer
## The player's spell buttons and weapon button. A button is enabled only when its action is legal.

signal cast_requested(spell: StringName)
signal attack_requested

var _buttons := {}  # spell id, or &"" for the weapon -> Button


## Builds one button per spell, plus the weapon.
func setup(side: SideState, content: ContentLoader) -> void:
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for id in side.spells:
		var def: Dictionary = content.spells[id]
		var cost := PackedStringArray()
		for color: String in def.cost:
			cost.append("%d %s" % [def.cost[color], color])
		_add(id, "%s  (%s)" % [def.name, ", ".join(cost)]).pressed.connect(func() -> void: cast_requested.emit(id))
	if side.weapon != &"":
		var def: Dictionary = content.weapons[side.weapon]
		_add(&"", "%s  (%d AP)" % [def.name, def.ap_cost]).pressed.connect(func() -> void: attack_requested.emit())


## Enables the buttons whose actions are in legal (pass an empty list to lock them all).
func update(legal: Array[Action]) -> void:
	for id: StringName in _buttons:
		var kind := Action.Kind.ATTACK if id == &"" else Action.Kind.CAST
		_buttons[id].disabled = not legal.any(func(a: Action) -> bool: return a.kind == kind and a.spell == id)


func button(id: StringName) -> Button:
	return _buttons.get(id)


func _add(id: StringName, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = true
	add_child(b)
	_buttons[id] = b
	return b
