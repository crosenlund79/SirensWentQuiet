extends Node
## Standalone preview of the region map (captures). Owner: M.

func _ready() -> void:
	var view := RegionMapView.new()
	add_child(view)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--focus="):
			var v := a.trim_prefix("--focus=").split(",")
			view.set_view(Vector3(float(v[0]), RegionMapView.GROUND_Y, float(v[1])), float(v[2]), true)
		elif a.begins_with("--cloud-time="):
			view.cloud_time = float(a.trim_prefix("--cloud-time="))
		elif a == "--no-clouds":
			view.cloud_amount = 0.0
		elif a.begins_with("--night="):
			view.set_night(float(a.trim_prefix("--night=")))
	print("map stats ", view.stats)
