extends Node3D
## Visual check for the fog boundary and the expedition screen (E's captures).
## Foundation world: HouseWorld + VoxelLighting + VoxelPlayer + VoxelCamera,
## plus FogBoundary and the HUD prompt. Not part of the game.
##
## User args (after --):
##   --night[=t]          night amount (default 1 when given)
##   --pos=x,y            player plan position (default: at the south edge on the path)
##   --zoom=d             camera distance (11-32)
##   --novol              slices only (no volumetric FogVolume)
##   --clock=HH:MM        GameState time of day (screen captures)
##   --screen=list|gear|confirm|event|outcome|report   open the expedition screen at that step
##   --dest=id            destination for the screen steps (default grocery)
##   --give=id:n,id:n     extra inventory for the screen captures
##   --pick=i             option picked for the outcome/report steps

var state: GameState
var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var boundary: FogBoundary
var hud: GameHud
var screen: ExpeditionScreen
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var night := 0.0
	if _args.has("night"):
		night = 1.0 if _args["night"] == "" else float(_args["night"])
	state = GameState.new_run(2026)
	if _args.has("clock"):
		var hm: PackedStringArray = str(_args["clock"]).split(":")
		state.total_minutes = 1440.0 + int(hm[0]) * 60.0 + (int(hm[1]) if hm.size() > 1 else 0)
	if _args.has("give"):
		for kv in str(_args["give"]).split(","):
			var p := kv.split(":")
			state.inventory.add(p[0], int(p[1]) if p.size() > 1 else 1)
	lighting = VoxelLighting.new()
	add_child(lighting)
	world = HouseWorld.new()
	world.setup(lighting)
	add_child(world)
	world.build_new()
	player = VoxelPlayer.new()
	add_child(player)
	var pos := Vector2(4.5, 12.15)
	if _args.has("pos"):
		var xy: PackedStringArray = str(_args["pos"]).split(",")
		pos = Vector2(float(xy[0]), float(xy[1]))
	player.global_position = Vector3(pos.x, 0, pos.y)
	player.aim_point = player.global_position + Vector3(0, 1.0, 3.0)
	player.input_enabled = false
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	if _args.has("zoom"):
		camera.set_distance(float(_args["zoom"]))
	add_child(camera)
	camera.make_current()
	camera.snap()
	boundary = FogBoundary.new()
	boundary.use_volumetric = not _args.has("novol")
	boundary.setup(player, lighting.environment)
	add_child(boundary)
	lighting.set_amount(night)
	player.set_night(night)
	boundary.set_night_amount(night)
	hud = GameHud.new()
	add_child(hud)
	hud.setup(state)
	Sfx.attach(self)
	if _args.has("screen"):
		screen = ExpeditionScreen.new()
		add_child(screen)
		screen.instant = true
		_drive_screen.call_deferred(str(_args["screen"]))


func _process(delta: float) -> void:
	world.update_view(player.global_position, camera, delta)
	hud.set_prompt(boundary.prompt_text() if screen == null else "")


func _drive_screen(target: String) -> void:
	screen.open(state)
	var dest := str(_args.get("dest", "grocery"))
	if target == "list":
		screen.select_destination(dest)
		return
	screen.select_destination(dest)
	screen.to_gear()
	if target == "gear":
		return
	screen.to_confirm()
	if target == "confirm":
		return
	screen.depart()
	if target == "event":
		return
	var pick := int(_args.get("pick", "-1"))
	while screen.step == "event":
		var i := pick if pick >= 0 and screen.run.option_state(pick)["ok"] else screen.run.first_available_option()
		screen.choose_option(i)
		if target == "outcome":
			return
		screen.continue_on()
