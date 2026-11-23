class_name AssetResolver
extends RefCounted
## Single entry point for replaceable graphics (see assets/README.md).
##
## Logical name "illustrated/floor_wood" resolves, in order, to:
##   1. <override root>/graphics/illustrated/floor_wood.png   (user file, PNG)
##   2. res://assets/graphics/illustrated/template_floor_wood.png (packaged fallback)
## Override root: the project's custom/ folder when running from the editor
## binary, or custom/ next to the executable in an exported Windows/Linux game.
## A missing or undecodable override falls back with a warning. Results are
## cached for the session: override changes apply after a game restart.
## Audio is out of scope for Experiment 001, so only textures are resolved.

const FALLBACK_ROOT := "res://assets/graphics"
const TEMPLATE_PREFIX := "template_"

static var _root_override := ""
static var _cache := {}


## Where user overrides are looked up (computed in one place).
static func override_root() -> String:
	if _root_override != "":
		return _root_override
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://custom")
	return OS.get_executable_path().get_base_dir().path_join("custom")


## Tests (or tools) inject a temporary root; "" restores the default.
static func set_override_root(path: String) -> void:
	_root_override = path
	_cache.clear()


static func clear_cache() -> void:
	_cache.clear()


static func override_path(logical: String) -> String:
	return override_root().path_join("graphics").path_join(logical + ".png")


static func fallback_path(logical: String) -> String:
	var dir := logical.get_base_dir()
	var file := TEMPLATE_PREFIX + logical.get_file() + ".png"
	return FALLBACK_ROOT.path_join(dir).path_join(file) if dir != "" else FALLBACK_ROOT.path_join(file)


## Returns the texture for `logical`, or null if neither override nor fallback
## exists. `mipmaps` builds mipmaps for override images (use for 3D surfaces).
static func get_texture(logical: String, mipmaps := false) -> Texture2D:
	var key := logical + ("#mip" if mipmaps else "")
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var user_file := override_path(logical)
	if FileAccess.file_exists(user_file):
		var img := Image.load_from_file(user_file)
		if img != null and not img.is_empty():
			if mipmaps:
				img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
		else:
			push_warning("AssetResolver: invalid override %s, using template" % user_file)
	if tex == null:
		var packaged := fallback_path(logical)
		if ResourceLoader.exists(packaged):
			tex = load(packaged)
		else:
			push_warning("AssetResolver: no asset for '%s'" % logical)
	_cache[key] = tex
	return tex


## Convenience for code that needs pixels (e.g. palettes, masks).
static func get_image(logical: String) -> Image:
	var tex := get_texture(logical)
	return tex.get_image() if tex != null else null
