extends SceneTree
## Screenshot helper for visual review (needs a display; see tools/capture.sh).
##   godot --path . -s res://tools/capture.gd -- --scene=res://src/launcher/launcher.tscn --out=/abs/shot.png [--at=4] [other args]
## Other user args (e.g. --night, --hide-help, version-specific --scenario=...)
## are visible to the scene through OS.get_cmdline_user_args().

func _initialize() -> void:
	var scene := "res://src/launcher/launcher.tscn"
	var out := "user://capture.png"
	var at := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.trim_prefix("--scene=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--at="):
			at = float(a.trim_prefix("--at="))
	change_scene_to_file(scene)
	_shoot(out, at)


func _shoot(out: String, at: float) -> void:
	await create_timer(at, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		push_error("capture: no image (headless?)")
		quit(1)
		return
	img.save_png(out)
	print("captured ", out)
	quit(0)
