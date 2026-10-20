extends Node
## Loads all content once at startup. Game code reads ContentDB.content.gems etc.

var content := ContentLoader.new()


func _init() -> void:
	var errors := content.load_all()
	if errors.is_empty() and OS.is_debug_build():
		errors = content.validate()
	for e in errors:
		push_error("ContentDB: " + e)
