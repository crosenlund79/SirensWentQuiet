class_name Sfx
extends RefCounted
## Sound playback (SPEC §7.6). Owner: A. Foundation stub: silent.

static var _root: Node


static func attach(root: Node) -> void:
	_root = root


static func play(_name: String, _at: Variant = null, _volume_db := 0.0) -> void:
	pass


static func ui(_name: String) -> void:
	pass


static func music(_name: String) -> void:
	pass


static func names() -> PackedStringArray:
	return PackedStringArray()
