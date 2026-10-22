extends SceneTree
## Reference checks for content JSON (schemas/ covers shapes and types).
## Usage: godot --headless --script res://tools/content_lint.gd

const ContentLoader := preload("res://engine/content_loader.gd")


func _initialize() -> void:
	var loader := ContentLoader.new()
	var errors := loader.load_all()
	if errors.is_empty():
		errors = loader.validate()
	for e in errors:
		printerr("content_lint: " + e)
	if errors.is_empty():
		print("content_lint: ok (%d gems, %d spells, %d weapons, %d statuses, %d classes)" % [
			loader.gems.size(), loader.spells.size(), loader.weapons.size(), loader.statuses.size(), loader.classes.size()])
	quit(1 if errors else 0)
