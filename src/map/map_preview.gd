extends Node
## Standalone preview of the region map with a sample run (for captures).
## Owner: M. User args (after --):
##   --select=<id>        select a place (camera flies there unless --focus)
##   --approach=<id>      pick a mission purpose for the selection
##   --plan               press "Plan expedition"
##   --focus=x,z,dist     camera focus (region cells) and distance
##   --cloud-time=s       start the cloud drift at s seconds
##   --cloud-rate=k       drift k times faster (preview only)
##   --no-clouds          hide the cloud layer (shadows stay)
##   --night=n            night amount 0..1
##   --hide-ui            hide the panels (map and pins only)
##   --all                every place discovered
##   --stats              print render monitors after a few frames

var screen: RegionMapScreen
var state: GameState


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	state = sample_state()
	var args := OS.get_cmdline_user_args()
	if "--all" in args:
		for id in RegionLocations.ids():
			state.region.discover(id)
	screen = RegionMapScreen.new()
	add_child(screen)
	screen.open(state)
	for a in args:
		if a == "--select=none":
			screen.select("", false)
		elif a == "--select=home":
			screen.find_home()
		elif a.begins_with("--select="):
			screen.select(a.trim_prefix("--select="), true)
	for a in args:
		if a.begins_with("--approach="):
			screen._set_approach(a.trim_prefix("--approach="), "")
		elif a == "--plan":
			screen.plan_selected()
		elif a.begins_with("--focus="):
			var v := a.trim_prefix("--focus=").split(",")
			screen.view.set_view(Vector3(float(v[0]), RegionMapView.GROUND_Y, float(v[1])), float(v[2]), true)
		elif a.begins_with("--cloud-time="):
			screen.view.cloud_time = float(a.trim_prefix("--cloud-time="))
		elif a.begins_with("--cloud-rate="):
			screen.view.cloud_rate = float(a.trim_prefix("--cloud-rate="))
		elif a == "--no-clouds":
			screen.view.cloud_amount = 0.0
		elif a.begins_with("--night="):
			screen.view.set_night(float(a.trim_prefix("--night=")))
		elif a == "--hide-ui":
			for c in screen.get_node("Root").get_children():
				if c != screen.markers and not (c is SubViewportContainer):
					c.visible = false
	print("map stats ", screen.view.stats)
	if "--stats" in args:
		for k in 20:
			await get_tree().process_frame
		print("render: draw calls %d, objects %d, primitives %d, fps %.1f" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.TIME_FPS)])


## A run a few days in: some places found, one picked over, one planned.
static func sample_state() -> GameState:
	var s := GameState.new_run(4242)
	s.total_minutes = 2 * 1440.0 + 10 * 60.0 + 20.0
	for id in ["quarry", "sawmill", "police", "scrapyard", "warehouse", "restaurant", "farmhouse", "hospital", "gun_shop", "drugstore"]:
		s.region.discover(id)
	MapInfo.set_stock(s, "grocery", 0.45)
	MapInfo.set_stock(s, "homes", 0.7)
	s.inventory.add("flashlight", 1)
	s.inventory.add("crowbar", 1)
	MapInfo.plan(s, "hardware", "general")
	return s
