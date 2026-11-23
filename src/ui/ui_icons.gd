class_name UiIcons
extends RefCounted
## Tiny vector icons drawn with CanvasItem primitives (no texture assets), so
## they stay crisp at any HUD scale. Owner: U.
##   UiIcons.paint(canvas_item, "moon", Rect2(0, 0, 18, 18), UiTheme.TEXT)
## Kinds: sun, moon, health, food, water, energy, ammo, warn, cheat, dot.

const KINDS := ["sun", "moon", "health", "food", "water", "energy", "ammo", "warn", "cheat", "dot"]


static func paint(ci: CanvasItem, kind: String, r: Rect2, color: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	match kind:
		"sun":
			ci.draw_circle(c, s * 0.22, color)
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * s * 0.32, c + d * s * 0.46, color, maxf(1.2, s * 0.08), true)
		"moon":
			ci.draw_colored_polygon(_crescent(c, s * 0.42), color)
		"health":
			ci.draw_colored_polygon(_heart(c, s * 0.46), color)
		"food":
			# fork and knife
			var w := maxf(1.2, s * 0.08)
			var fx := c.x - s * 0.17
			ci.draw_line(Vector2(fx, c.y - s * 0.05), Vector2(fx, c.y + s * 0.44), color, w * 1.2, true)
			for k in [-1, 0, 1]:
				ci.draw_line(Vector2(fx + k * s * 0.1, c.y - s * 0.44), Vector2(fx + k * s * 0.1, c.y - s * 0.12), color, w, true)
			ci.draw_line(Vector2(fx - s * 0.1, c.y - s * 0.12), Vector2(fx + s * 0.1, c.y - s * 0.12), color, w, true)
			ci.draw_arc(Vector2(fx, c.y - s * 0.12), s * 0.1, 0.0, PI, 8, color, w, true)
			var kx := c.x + s * 0.2
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(kx - s * 0.06, c.y - s * 0.44), Vector2(kx + s * 0.08, c.y - s * 0.3),
				Vector2(kx + s * 0.08, c.y + s * 0.02), Vector2(kx - s * 0.06, c.y + s * 0.02)]), color)
			ci.draw_line(Vector2(kx, c.y), Vector2(kx, c.y + s * 0.44), color, w * 1.3, true)
		"water":
			ci.draw_colored_polygon(_drop(c, s * 0.46), color)
		"energy":
			var p := PackedVector2Array()
			for v in [Vector2(0.12, -0.48), Vector2(-0.26, 0.06), Vector2(-0.02, 0.06), Vector2(-0.12, 0.48), Vector2(0.26, -0.08), Vector2(0.02, -0.08)]:
				p.append(c + v * s)
			ci.draw_colored_polygon(p, color)
		"ammo":
			# one cartridge: brass case and a rounded bullet
			var bw := s * 0.3
			var case_r := Rect2(c.x - bw * 0.5, c.y - s * 0.05, bw, s * 0.48)
			ci.draw_rect(case_r, color)
			ci.draw_rect(Rect2(case_r.position.x - s * 0.03, case_r.end.y - s * 0.07, bw + s * 0.06, s * 0.07), color)
			var tip := PackedVector2Array()
			for i in 9:
				var a := PI + PI * i / 8.0
				tip.append(Vector2(c.x + cos(a) * bw * 0.5, c.y - s * 0.12 + sin(a) * s * 0.34))
			tip.append(Vector2(c.x + bw * 0.5, c.y - s * 0.08))
			tip.append(Vector2(c.x - bw * 0.5, c.y - s * 0.08))
			ci.draw_colored_polygon(tip, color)
		"warn":
			var tri := PackedVector2Array([c + Vector2(0, -0.44) * s, c + Vector2(0.48, 0.4) * s, c + Vector2(-0.48, 0.4) * s])
			ci.draw_colored_polygon(tri, color)
			var ink := Color(0.05, 0.05, 0.06, 0.95)
			ci.draw_line(c + Vector2(0, -0.14) * s, c + Vector2(0, 0.14) * s, ink, maxf(1.5, s * 0.1))
			ci.draw_circle(c + Vector2(0, 0.27) * s, maxf(0.9, s * 0.055), ink)
		"cheat":
			# a small asterisk / star burst
			for i in 4:
				var a := PI * i / 4.0
				var d := Vector2(cos(a), sin(a)) * s * 0.4
				ci.draw_line(c - d, c + d, color, maxf(1.4, s * 0.11), true)
		_:
			ci.draw_circle(c, s * 0.2, color)


static func _crescent(c: Vector2, r: float) -> PackedVector2Array:
	# Outer arc on the left of a circle; inner arc of a shifted circle through both tips.
	var pts := PackedVector2Array()
	var a0 := deg_to_rad(-62.0)   # upper-right tip (y down)
	var a1 := deg_to_rad(62.0)    # lower-right tip
	var n := 20
	for i in n + 1:
		var a := a0 - (TAU - (a1 - a0)) * float(i) / n   # the long way round, via the left
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var tip_a := c + Vector2(cos(a0), sin(a0)) * r
	var tip_b := c + Vector2(cos(a1), sin(a1)) * r
	var c2 := c + Vector2(r * 0.5, 0.0)
	var r2 := (tip_a - c2).length()
	var ang_a := (tip_a - c2).angle()
	var ang_b := (tip_b - c2).angle()
	var span := fposmod(ang_a - ang_b, TAU)   # from tip_b back to tip_a around c2's left side
	for i in range(1, n):
		var a := ang_b + span * float(i) / n
		pts.append(c2 + Vector2(cos(a), sin(a)) * r2)
	return pts


static func _heart(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y + 1.5) / 17.0 * r)
	return pts


static func _drop(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cc := c + Vector2(0, r * 0.28)
	var rr := r * 0.62
	pts.append(c + Vector2(0, -r))
	for i in 21:
		var a := deg_to_rad(-30.0) + deg_to_rad(240.0) * i / 20.0
		pts.append(cc + Vector2(cos(a), sin(a)) * rr)
	return pts
