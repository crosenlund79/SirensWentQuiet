extends Node2D
## An illustrated character token (art faces +X). Motion is by transforms
## only, like the reference: facing rotation, walk sway and bob, recoil or
## lunge along the facing, and a bright hit flash.

const Art := preload("res://src/illustrated/ill_art.gd")

var sprite: Sprite2D
var facing := 0.0
var sway := 0.0        ## extra rotation (radians)
var bob := 0.0         ## relative scale pulse
var kick := 0.0        ## px pushed back along the facing (negative = lunge forward)
var _flash := 0.0
var _base_scale := 1.0


func setup(tex_name: String, size_m := 1.0) -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	var tex := Art.tex(tex_name)
	sprite.texture = tex
	if tex != null:
		_base_scale = size_m * Art.PX_PER_M / tex.get_size().x
	_apply()


func face(angle: float, delta: float, rate: float) -> void:
	facing = lerp_angle(facing, angle, clampf(rate * delta, 0.0, 1.0))


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	kick = move_toward(kick, 0.0, delta * 90.0)
	_flash = maxf(_flash - delta * 7.0, 0.0)
	_apply()


func _apply() -> void:
	if sprite == null:
		return
	sprite.rotation = facing + sway
	sprite.position = Vector2(-kick, 0.0).rotated(facing)
	var s := _base_scale * (1.0 + bob)
	sprite.scale = Vector2(s, s)
	sprite.modulate = Color.WHITE.lerp(Color(2.6, 2.3, 2.1), _flash)
