extends GutTest


func test_loads_gems_json() -> void:
	var loader := ContentLoader.new()
	assert_eq(loader.load_all(), PackedStringArray())
	assert_eq(loader.validate(), PackedStringArray())
	assert_eq(loader.gems.size(), 7)
	var total := 0
	for gem: Dictionary in loader.gems:
		total += int(gem.spawn_weight)
	assert_eq(total, 100, "default spawn weights are percentages")


func test_duplicate_gem_id_fails_validation() -> void:
	var loader := ContentLoader.new()
	loader.load_all()
	loader.gems[1] = loader.gems[0]
	assert_eq(loader.validate().size(), 1)


func test_missing_content_dir_reports_error() -> void:
	assert_eq(ContentLoader.new().load_all("res://no_such_dir").size(), 1)


func test_content_db_autoload_has_gems() -> void:
	assert_eq(ContentDB.content.gems.size(), 7)
