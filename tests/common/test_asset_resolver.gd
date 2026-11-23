extends "res://tests/test_case.gd"
## AssetResolver contract (assets/README.md): override precedence, fallback
## when missing/invalid/unsupported, override-root selection.

const LOGICAL := "common/crosshair"
var _tmp := ""


func _setup() -> String:
	_tmp = OS.get_user_data_dir().path_join("resolver_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp.path_join("graphics/common"))
	AssetResolver.set_override_root(_tmp)
	return _tmp.path_join("graphics/common")


func _teardown() -> void:
	AssetResolver.set_override_root("")
	for f in DirAccess.get_files_at(_tmp.path_join("graphics/common")):
		DirAccess.remove_absolute(_tmp.path_join("graphics/common").path_join(f))


func test_default_override_root_is_project_custom_folder() -> void:
	AssetResolver.set_override_root("")
	check_eq(AssetResolver.override_root(), ProjectSettings.globalize_path("res://custom"), "editor/dev root")
	check_eq(AssetResolver.fallback_path(LOGICAL), "res://assets/graphics/common/template_crosshair.png", "fallback path")


func test_fallback_when_missing() -> void:
	_setup()
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex != null, "packaged template found")
	check(not (tex is ImageTexture), "uses the imported template")
	_teardown()


func test_override_takes_precedence() -> void:
	var dir := _setup()
	var img := Image.create_empty(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(dir.path_join("crosshair.png"))
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex is ImageTexture, "override loaded at runtime")
	check_eq(tex.get_size(), Vector2(8, 6), "override size")
	# cached for the session
	check(AssetResolver.get_texture(LOGICAL) == tex, "cached")
	_teardown()


func test_invalid_or_unsupported_override_falls_back() -> void:
	var dir := _setup()
	var f := FileAccess.open(dir.path_join("crosshair.png"), FileAccess.WRITE)
	f.store_string("definitely not a png")
	f.close()
	var tex := AssetResolver.get_texture(LOGICAL)
	check(tex != null and not (tex is ImageTexture), "invalid PNG -> template")
	_teardown()
	dir = _setup()
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.save_jpg(dir.path_join("crosshair.jpg"))
	tex = AssetResolver.get_texture(LOGICAL)
	check(tex != null and not (tex is ImageTexture), "JPG override ignored (PNG only)")
	_teardown()
