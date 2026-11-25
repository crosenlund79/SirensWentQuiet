class_name SecurityObjects
extends RefCounted
## Exp 007 (S): the looks and prompts of the security WorldObject kinds
## ("motion_sensor", "turret_mount"; Security has the rules). WorldObject
## calls make_for() for the visual and prompt() for the interaction line.
## The canonical prop frame: the front (the eye, the gun's rest direction)
## faces -Z.
##   motion sensor  a dark steel post on a foot plate with a sensor head at
##                  about 1.85 m: a white housing, a dark lens facing out, a
##                  status LED
##   turret mount   a steel pedestal with an olive ammo box on its side and a
##                  yoke ("Head", turned by SecuritySystem) at about 1.05 m
##                  carrying the installed gun ("Gun": a handgun or the
##                  shotgun model, barrel along -Z) and a status LED
## LED colours: green = ready, amber = needs ammo or reloading, red = off,
## dark = no power.

const STEEL := Color(0.24, 0.25, 0.27)
const HOUSING := Color(0.86, 0.86, 0.82)
const OLIVE := Color(0.33, 0.36, 0.22)
const LED := {"ready": Color(0.25, 1.0, 0.35), "warn": Color(1.0, 0.7, 0.15), "off": Color(1.0, 0.18, 0.12), "dark": Color(0.06, 0.06, 0.06)}


static func handles(kind: String) -> bool:
	return Security.is_kind(kind)


## The visual of a security object `o` (WorldObject; size = its size).
static func make_for(o: WorldObject, size: Vector3, seed: int, damage: float) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [o.kind, seed])
	var wear := 0.25 + damage * 0.5
	if o.kind == "motion_sensor":
		var mm := PropMesh.new()
		mm.set_mat(PropMaterials.L_METAL, STEEL, wear)
		mm.box(Vector3(-0.14, 0.0, -0.14), Vector3(0.14, 0.03, 0.14))             # foot plate
		mm.box(Vector3(-0.035, 0.03, -0.035), Vector3(0.035, Security.SENSOR_HEIGHT - 0.05, 0.035))   # post
		mm.set_mat(PropMaterials.L_PLAIN, HOUSING.darkened(damage * 0.4), wear)
		mm.box(Vector3(-0.08, Security.SENSOR_HEIGHT - 0.09, -0.11), Vector3(0.08, Security.SENSOR_HEIGHT + 0.06, 0.05))
		mm.set_mat(PropMaterials.L_SCREEN, Color(0.08, 0.09, 0.1), 0.1)
		mm.box(Vector3(-0.055, Security.SENSOR_HEIGHT - 0.06, -0.125), Vector3(0.055, Security.SENSOR_HEIGHT + 0.03, -0.11))   # lens
		root.add_child(_mesh(mm, "Mesh"))
		root.add_child(_led(Vector3(0.05, Security.SENSOR_HEIGHT + 0.045, -0.115)))
		return root
	var pm := PropMesh.new()
	pm.set_mat(PropMaterials.L_METAL, STEEL, wear)
	pm.box(Vector3(-0.28, 0.0, -0.28), Vector3(0.28, 0.06, 0.28))                 # base plate
	pm.box(Vector3(-0.09, 0.06, -0.09), Vector3(0.09, Security.TURRET_HEIGHT - 0.12, 0.09))   # column
	pm.cylinder(Vector3(0, Security.TURRET_HEIGHT - 0.14, 0), 0.13, 0.11, 0.06, 10)   # bearing
	pm.set_mat(PropMaterials.L_PLAIN, OLIVE.darkened(damage * 0.3), wear)
	pm.box(Vector3(0.1, 0.06, -0.13), Vector3(0.3, 0.32, 0.13))                    # ammo box
	pm.set_mat(PropMaterials.L_METAL, STEEL.lightened(0.15), wear)
	pm.box(Vector3(0.12, 0.32, -0.04), Vector3(0.28, 0.35, 0.04))                  # its handle
	pm.set_mat(PropMaterials.L_PLAIN, Color(0.12, 0.12, 0.12), wear)
	pm.box(Vector3(-0.3, 0.06, -0.05), Vector3(-0.1, 0.24, 0.05))                  # power unit
	root.add_child(_mesh(pm, "Mesh"))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, Security.TURRET_HEIGHT, 0)
	var hm := PropMesh.new()
	hm.set_mat(PropMaterials.L_METAL, STEEL.lightened(0.05), wear)
	hm.box(Vector3(-0.12, -0.08, -0.08), Vector3(0.12, -0.04, 0.12))               # yoke floor
	for sx in [-1.0, 1.0]:
		hm.box(Vector3(sx * 0.12 - 0.02, -0.08, -0.06), Vector3(sx * 0.12 + 0.02, 0.1, 0.1))   # yoke arms
	hm.box(Vector3(-0.07, -0.04, 0.1), Vector3(0.07, 0.08, 0.2))                   # servo
	head.add_child(_mesh(hm, "Mesh"))
	head.add_child(_led(Vector3(0.0, 0.1, 0.16)))
	var g := gun_model(Security.gun(o))
	if g != null:
		head.add_child(g)
	root.add_child(head)
	return root


## The installed gun's model in head space (barrel along -Z), or null.
static func gun_model(id: String) -> Node3D:
	if id == "":
		return null
	var g: Node3D
	if id == "shotgun":
		g = WeaponHandler.shotgun_model()
		g.rotation.x = PI * 0.5          # the model's barrel runs along -Y
		g.position = Vector3(0, 0.02, 0.12)
	else:
		g = Node3D.new()
		var mm := PropMesh.new()
		mm.set_mat(PropMaterials.L_METAL, Color(0.12, 0.12, 0.13), 0.3)
		mm.box(Vector3(-0.022, 0.0, -0.2), Vector3(0.022, 0.05, 0.02))           # slide and barrel
		mm.box(Vector3(-0.02, -0.11, -0.02), Vector3(0.02, 0.0, 0.03))          # grip
		g.add_child(_mesh(mm, "Mesh"))
		g.position = Vector3(0, 0.0, 0.0)
	g.name = "Gun_" + id
	return g


## Shows the installed gun on the head (after an install or removal).
static func sync_gun(o: WorldObject) -> void:
	var head := head_of(o)
	if head == null:
		return
	var want := Security.gun(o)
	var have := ""
	for c in head.get_children():
		if str(c.name).begins_with("Gun_"):
			have = str(c.name).substr(4)
			if have != want:
				head.remove_child(c)
				c.queue_free()
				have = ""
	if have == "" and want != "":
		var g := gun_model(want)
		if g != null:
			head.add_child(g)


static func head_of(o: WorldObject) -> Node3D:
	if o == null or o.visual == null or not is_instance_valid(o.visual):
		return null
	return o.visual.get_node_or_null("Head") as Node3D


## Turns the head to `yaw` (relative to the object's facing).
static func set_head_yaw(o: WorldObject, yaw: float) -> void:
	var h := head_of(o)
	if h != null:
		h.rotation.y = yaw


## Sets the status LED ("ready", "warn", "off", "dark").
static func set_led(o: WorldObject, status: String) -> void:
	if o == null or o.visual == null or not is_instance_valid(o.visual):
		return
	var led := o.visual.get_node_or_null("Head/Led" if o.kind == "turret_mount" else "Led") as MeshInstance3D
	if led == null or not (led.material_override is StandardMaterial3D) or str(led.get_meta("status", "")) == status:
		return
	led.set_meta("status", status)
	var m := led.material_override as StandardMaterial3D
	var c: Color = LED.get(status, LED["dark"])
	m.albedo_color = c
	m.emission = c
	m.emission_energy_multiplier = 0.0 if status == "dark" else 2.2


static func _led(at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Led"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.025)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = LED["dark"]
	m.emission_enabled = true
	m.emission = LED["dark"]
	m.emission_energy_multiplier = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	return mi


static func _mesh(mm: PropMesh, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var m := mm.commit()
	if m.get_surface_count() > 0:
		m.surface_set_material(0, PropMaterials.kit())
	mi.mesh = m
	return mi


# --- prompts --------------------------------------------------------------------------------

## The interaction line of a security object.
static func prompt(o: WorldObject) -> String:
	if o.kind == "motion_sensor":
		var c := Security.config(o)
		return "[E] %s · %s" % [Security.title(o), "settings" if bool(c["on"]) else "switched off"]
	var id := Security.gun(o)
	if id == "":
		return "[E] Turret mount %s · install a gun" % str(Security.config(o)["name"])
	if Security.needs_hand_reload(o):
		return "[E] Reload the turret (%d in its ammo box)" % Security.box(o)
	var t := "[E] Turret · %s %d/%d · box %d" % [WeaponDefs.name_of(id).to_lower(), Security.mag(o), WeaponDefs.capacity(id), Security.box(o)]
	if Security.mag(o) <= 0 and Security.box(o) <= 0:
		t += " · out of ammo"
	return t
