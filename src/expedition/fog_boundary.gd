class_name FogBoundary
extends Node3D
## The lot edge and its fog bank (SPEC §7.7). Owner: E.
##
## - Fog: a volumetric FogVolume (Forward+, shaped by a fog shader around the
##   LOT) plus stacked horizontal fog slices with drifting noise, so the bank
##   still reads under software rendering. Thicker and taller with distance,
##   soft where it meets geometry, tinted by `set_night_amount`.
## - Walls: invisible boxes on physics layer 6 (lot_boundary). Only the player
##   collides with them; enemies walk in out of the fog.
## - Interaction: `prompt_text()` is non-empty while the player stands within
##   PROMPT_DISTANCE of the edge; the game calls `request_exit()` on interact,
##   which emits `exit_requested`. Nothing happens just by walking up to it.

signal exit_requested(at: Vector3)

const LOT := Rect2(-4.5, -3.5, 23.0, 16.0)
const PROMPT_DISTANCE := 0.7
const PROMPT := "[E] Leave the property and head into the fog"
const WALL_LAYER := 1 << 5                ## physics layer 6
const WALL_THICKNESS := 1.0
const WALL_HEIGHT := 3.0
const RETURN_INSET := 1.6                 ## return_point: this far inside the edge
const RETURN_CLEARANCE := 0.4

const CARD_SHADER := preload("res://src/expedition/shaders/fog_card.gdshader")
const VOLUME_SHADER := preload("res://src/expedition/shaders/fog_volume.gdshader")
## Slice heights (m). The lowest one also becomes an opaque floor far out.
const LAYERS := [0.06, 0.4, 0.85, 1.4, 2.05, 2.8, 3.65, 4.6, 5.7, 7.0]
const LAYER_ALPHA := 0.27
const RING_INNER := -1.2                  ## slices start this far inside the edge
const RING_OUTER := 70.0                  ## ... and end this far out

## Volumetric fog settings written to the Environment given to setup().
const VOLUMETRIC := {
	"volumetric_fog_density": 0.0,         # no global fog: only the bank
	"volumetric_fog_albedo": Color(1, 1, 1),
	"volumetric_fog_emission": Color(0, 0, 0),
	"volumetric_fog_emission_energy": 1.0,
	"volumetric_fog_anisotropy": 0.35,
	"volumetric_fog_length": 72.0,
	"volumetric_fog_detail_spread": 1.4,
	"volumetric_fog_ambient_inject": 0.7,
	"volumetric_fog_sky_affect": 0.0,
	"volumetric_fog_gi_inject": 0.0,
	"volumetric_fog_temporal_reprojection_enabled": true,
	"volumetric_fog_temporal_reprojection_amount": 0.85,
}

static var _noise_tex: ImageTexture

var player: Node3D
var environment: Environment
var night_amount := 0.0
var use_volumetric := true                ## set before setup()/add_child to skip the FogVolume
var cards: Array[MeshInstance3D] = []
var card_materials: Array[ShaderMaterial] = []
var volume: FogVolume
var volume_material: ShaderMaterial
var walls: Array[StaticBody3D] = []
var _invite := 0.0


func setup(p: Node3D, env: Environment) -> void:
	player = p
	environment = env
	if environment != null and use_volumetric:
		_configure_environment()


func _ready() -> void:
	_build_walls()
	_build_cards()
	if use_volumetric:
		_build_volume()
	set_night_amount(night_amount)


# --- walls ---------------------------------------------------------------------------

func _build_walls() -> void:
	var t := WALL_THICKNESS
	for r in [Rect2(LOT.position.x - t, LOT.position.y - t, LOT.size.x + 2 * t, t),
			Rect2(LOT.position.x - t, LOT.end.y, LOT.size.x + 2 * t, t),
			Rect2(LOT.position.x - t, LOT.position.y, t, LOT.size.y),
			Rect2(LOT.end.x, LOT.position.y, t, LOT.size.y)]:
		var body := StaticBody3D.new()
		body.name = "LotWall"
		body.collision_layer = WALL_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, WALL_HEIGHT, r.size.y)
		cs.shape = box
		body.add_child(cs)
		body.position = Vector3(r.get_center().x, WALL_HEIGHT * 0.5, r.get_center().y)
		add_child(body)
		walls.append(body)


# --- fog -------------------------------------------------------------------------------

static func noise_texture() -> ImageTexture:
	if _noise_tex == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 1979
		fn.frequency = 0.012
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 4
		fn.fractal_gain = 0.55
		var img := fn.get_seamless_image(256, 256, false, false, 0.1, true)
		img.generate_mipmaps()
		_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


## Where the front path and the driveway run on into the fog (x0, z0, x1, z1).
static func lanes() -> Array:
	var out := []
	for id in ["front_path", "driveway"]:
		for p in HousePlan.PROPS:
			if p["id"] == id:
				var r: Rect2 = p["rect"]
				out.append(Vector4(r.position.x, LOT.end.y - 0.4, r.end.x, LOT.end.y + 4.5))
	while out.size() < 2:
		out.append(Vector4.ZERO)
	return out


func _ring_mesh() -> ArrayMesh:
	var inner := LOT.grow(RING_INNER)
	var outer := LOT.grow(RING_OUTER)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in [Rect2(outer.position.x, outer.position.y, outer.size.x, inner.position.y - outer.position.y),
			Rect2(outer.position.x, inner.end.y, outer.size.x, outer.end.y - inner.end.y),
			Rect2(outer.position.x, inner.position.y, inner.position.x - outer.position.x, inner.size.y),
			Rect2(inner.end.x, inner.position.y, outer.end.x - inner.end.x, inner.size.y)]:
		var a := Vector3(r.position.x, 0, r.position.y)
		var b := Vector3(r.end.x, 0, r.position.y)
		var c := Vector3(r.end.x, 0, r.end.y)
		var d := Vector3(r.position.x, 0, r.end.y)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	return st.commit()


func _build_cards() -> void:
	var mesh := _ring_mesh()
	var ln := lanes()
	var lot := Vector4(LOT.position.x, LOT.position.y, LOT.end.x, LOT.end.y)
	for i in LAYERS.size():
		var m := ShaderMaterial.new()
		m.shader = CARD_SHADER
		m.render_priority = i - LAYERS.size()          # bottom first, under other transparents
		m.set_shader_parameter("noise_tex", noise_texture())
		m.set_shader_parameter("lot_rect", lot)
		m.set_shader_parameter("layer_y", LAYERS[i])
		m.set_shader_parameter("layer_t", float(i) / float(LAYERS.size() - 1))
		m.set_shader_parameter("layer_alpha", LAYER_ALPHA * (1.15 if i == 0 else 1.0))
		m.set_shader_parameter("floor_alpha", 1.0 if i == 0 else 0.0)
		m.set_shader_parameter("seed_offset", 0.173 * i)
		m.set_shader_parameter("lane_a", ln[0])
		m.set_shader_parameter("lane_b", ln[1])
		var mi := MeshInstance3D.new()
		mi.name = "FogCard%d" % i
		mi.mesh = mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = LAYERS[i]
		mi.extra_cull_margin = 16.0
		add_child(mi)
		cards.append(mi)
		card_materials.append(m)


func _build_volume() -> void:
	volume = FogVolume.new()
	volume.name = "FogBank"
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_WORLD
	volume_material = ShaderMaterial.new()
	volume_material.shader = VOLUME_SHADER
	var ln := lanes()
	volume_material.set_shader_parameter("lot_rect", Vector4(LOT.position.x, LOT.position.y, LOT.end.x, LOT.end.y))
	volume_material.set_shader_parameter("lane_a", ln[0])
	volume_material.set_shader_parameter("lane_b", ln[1])
	volume.material = volume_material
	add_child(volume)


func _configure_environment() -> void:
	environment.volumetric_fog_enabled = true
	for k in VOLUMETRIC:
		environment.set(k, VOLUMETRIC[k])


## Turns the volumetric part on or off at runtime (the slices stay).
func set_volumetric(on: bool) -> void:
	use_volumetric = on
	if environment != null:
		if on:
			_configure_environment()
		else:
			environment.volumetric_fog_enabled = false
	if on and volume == null and is_inside_tree():
		_build_volume()
	if volume != null:
		volume.visible = on
	set_night_amount(night_amount)


func set_night_amount(t: float) -> void:
	night_amount = clampf(t, 0.0, 1.0)
	for m in card_materials:
		m.set_shader_parameter("night", night_amount)
	if volume_material != null:
		volume_material.set_shader_parameter("night", night_amount)
	if environment != null and use_volumetric:
		# Moonlight scatter: the bank takes up more ambient light at night.
		environment.volumetric_fog_ambient_inject = lerpf(VOLUMETRIC["volumetric_fog_ambient_inject"], 1.4, night_amount)


func _process(delta: float) -> void:
	var want := 0.0
	var at := Vector3(0, -100, 0)
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		at = player.global_position
		want = 1.0 - smoothstep(PROMPT_DISTANCE, 2.6, edge_distance(Vector2(at.x, at.z)))
	_invite = move_toward(_invite, want, delta * 2.5)
	for m in card_materials:
		m.set_shader_parameter("invite", _invite)
		m.set_shader_parameter("invite_pos", at)


# --- interaction --------------------------------------------------------------------------

## Distance from a plan point to the nearest lot edge (negative outside the lot).
static func edge_distance(p: Vector2) -> float:
	return minf(minf(p.x - LOT.position.x, LOT.end.x - p.x), minf(p.y - LOT.position.y, LOT.end.y - p.y))


func is_player_at_edge() -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	return edge_distance(Vector2(player.global_position.x, player.global_position.z)) < PROMPT_DISTANCE


func prompt_text() -> String:
	return PROMPT if is_player_at_edge() else ""


## Called by the game when interact is pressed; does nothing away from the edge.
func request_exit() -> void:
	if is_player_at_edge():
		exit_requested.emit(player.global_position)


## A free spot on the lot RETURN_INSET inside the edge nearest to `at`. When
## that spot is taken (the car, a tree, anything solid) it searches along the
## edge in both directions, then a little further in.
func return_point(at: Vector3) -> Vector3:
	var p := Vector2(at.x, at.z)
	for inset in [RETURN_INSET, RETURN_INSET + 1.0, RETURN_INSET + 2.0]:
		var r := LOT.grow(-inset)
		var per := 2.0 * (r.size.x + r.size.y)
		var s0 := _perimeter_s(r, _snap_to_perimeter(r, p))
		for k in int(per / 0.5):
			var off := 0.5 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
			var c := _perimeter_point(r, s0 + off)
			if _is_free(c):
				return Vector3(c.x, 0.0, c.y)
	return Vector3(HousePlan.PLAYER_START.x, 0.0, HousePlan.PLAYER_START.y)


static func _snap_to_perimeter(r: Rect2, p: Vector2) -> Vector2:
	p = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	var dl := p.x - r.position.x
	var dr := r.end.x - p.x
	var dt := p.y - r.position.y
	var db := r.end.y - p.y
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dl:
		p.x = r.position.x
	elif m == dr:
		p.x = r.end.x
	elif m == dt:
		p.y = r.position.y
	else:
		p.y = r.end.y
	return p


static func _perimeter_s(r: Rect2, p: Vector2) -> float:
	if is_equal_approx(p.y, r.position.y):
		return p.x - r.position.x
	if is_equal_approx(p.x, r.end.x):
		return r.size.x + (p.y - r.position.y)
	if is_equal_approx(p.y, r.end.y):
		return r.size.x + r.size.y + (r.end.x - p.x)
	return 2.0 * r.size.x + r.size.y + (r.end.y - p.y)


static func _perimeter_point(r: Rect2, s: float) -> Vector2:
	s = fposmod(s, 2.0 * (r.size.x + r.size.y))
	if s < r.size.x:
		return Vector2(r.position.x + s, r.position.y)
	s -= r.size.x
	if s < r.size.y:
		return Vector2(r.end.x, r.position.y + s)
	s -= r.size.y
	if s < r.size.x:
		return Vector2(r.end.x - s, r.end.y)
	s -= r.size.x
	return Vector2(r.position.x, r.end.y - s)


func _is_free(c: Vector2) -> bool:
	if HousePlan.FOOTPRINT.grow(0.5).has_point(c):
		return false
	for pr in HousePlan.PROPS:
		if pr["blocks"] and (pr["rect"] as Rect2).grow(RETURN_CLEARANCE).has_point(c):
			return false
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Tuning.PLAYER_RADIUS + 0.1
	cyl.height = 1.3
	q.shape = cyl
	q.transform = Transform3D(Basis(), Vector3(c.x, 0.85, c.y))
	q.collision_mask = 1 | 2 | 16
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	return space.intersect_shape(q, 1).is_empty()
