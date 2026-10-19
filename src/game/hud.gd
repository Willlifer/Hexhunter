class_name HHHud
extends Control
## The bottom action bar (kickoff HUD): Q W E R boxes with cooldown fill, the
## HP orb, active + backup element, a stamina slot reserved (H19), and the
## monster's HP bar at the top. Drawn from sim state every frame; no nodes
## per element, so it never drifts from the sim.

const BOX := 64.0
const GAP := 10.0
const ORB_R := 44.0
const BAR_W := 520.0
const KEYS := ["q", "w", "e", "r"]

var sim: HHSim
var player_id := ""
var monster_id := ""
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var p := sim.unit(player_id)
	if p.is_empty():
		return
	var size := get_viewport_rect().size
	var cx := size.x * 0.5
	var y := size.y - BOX - 22.0
	# backing plate
	var plate_w := ORB_R * 2 + GAP * 3 + BOX * 4 + GAP * 3 + 200.0
	draw_rect(Rect2(cx - plate_w * 0.5, y - 14.0, plate_w, BOX + 28.0), Color(0.05, 0.05, 0.07, 0.72))
	# HP orb (left of the bar)
	var ox := cx - plate_w * 0.5 + GAP + ORB_R
	var oy := y + BOX * 0.5
	var frac := clampf(float(p.hp) / maxf(1.0, float(p.max_hp)), 0.0, 1.0)
	draw_circle(Vector2(ox, oy), ORB_R, Color(0.12, 0.02, 0.03))
	_draw_orb_fill(Vector2(ox, oy), ORB_R - 3.0, frac, Color(0.78, 0.12, 0.12))
	draw_arc(Vector2(ox, oy), ORB_R, 0.0, TAU, 48, Color(0.9, 0.85, 0.7), 2.0)
	_text(Vector2(ox, oy + 6.0), "%d" % int(p.hp), 18, Color.WHITE, true)
	# skills
	var skills := HHWeapons.skills(str(p.weapon))
	var sx := ox + ORB_R + GAP * 2
	for i in KEYS.size():
		var k: String = KEYS[i]
		var r := Rect2(sx + i * (BOX + GAP), y, BOX, BOX)
		var sk: Dictionary = skills.get(k, {})
		var cd := int(p.cooldowns.get(k, 0))
		var total := int(sk.get("cooldown", 1))
		var el := HHLook.element_color(str(p.element))
		draw_rect(r, Color(0.16, 0.16, 0.2))
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), el.darkened(0.55))
		if cd > 0:
			var f := float(cd) / maxf(1.0, float(total))
			draw_rect(Rect2(r.position.x, r.position.y + r.size.y * (1.0 - f), r.size.x, r.size.y * f), Color(0, 0, 0, 0.62))
			_text(r.get_center() + Vector2(0, 7), "%.1f" % (cd / 30.0), 16, Color.WHITE, true)
		var active := (k == "e" and int(p.guard) > 0)
		draw_rect(r, Color(1.0, 0.9, 0.5) if active else Color(0.75, 0.72, 0.6), false, 2.0 if active else 1.0)
		_text(r.position + Vector2(6, 18), k.to_upper(), 16, Color(1, 1, 1))
		_text(Vector2(r.get_center().x, r.end.y + 14), str(sk.get("name", "")), 11, Color(0.85, 0.85, 0.8), true)
	# elements: active (big) and backup (small)
	var ex := sx + 4 * (BOX + GAP) + GAP + 24.0
	var ey := y + BOX * 0.5
	draw_circle(Vector2(ex, ey), 22.0, HHLook.element_color(str(p.element)))
	draw_arc(Vector2(ex, ey), 22.0, 0.0, TAU, 32, Color.WHITE, 2.0)
	draw_circle(Vector2(ex + 40.0, ey + 10.0), 12.0, HHLook.element_color(str(p.backup)))
	draw_arc(Vector2(ex + 40.0, ey + 10.0), 12.0, 0.0, TAU, 24, Color(0.8, 0.8, 0.8), 1.0)
	_text(Vector2(ex + 20.0, y + BOX + 14.0), "%s / %s" % [p.element, p.backup], 11, Color(0.85, 0.85, 0.8), true)
	# potions (H40): a T box right of the elements
	var tx := ex + 70.0
	var tr := Rect2(tx, y, BOX * 0.8, BOX)
	draw_rect(tr, Color(0.16, 0.16, 0.2))
	var tcd := int(p.cooldowns.get("t", 0))
	draw_rect(Rect2(tr.position + Vector2(3, 3), tr.size - Vector2(6, 6)), Color(0.35, 0.12, 0.2))
	if tcd > 0:
		var tf := float(tcd) / maxf(1.0, HHTune.value("potion_cd"))
		draw_rect(Rect2(tr.position.x, tr.position.y + tr.size.y * (1.0 - tf), tr.size.x, tr.size.y * tf), Color(0, 0, 0, 0.62))
	draw_rect(tr, Color(0.75, 0.72, 0.6), false, 1.0)
	_text(tr.position + Vector2(6, 18), "T", 16, Color(1, 1, 1))
	_text(tr.get_center() + Vector2(0, 14), "x%d" % int(p.potions), 15, Color(1, 0.9, 0.7), true)
	_text(Vector2(tr.get_center().x, tr.end.y + 14), "Potion", 11, Color(0.85, 0.85, 0.8), true)
	if not (p.regen as Dictionary).is_empty():
		var hm := sim.heal_mult(p)
		_text(Vector2(ox, oy - ORB_R - 8.0), "healing x%.1f" % hm, 13, Color(0.5, 1.0, 0.6) if hm >= 1.0 else Color(1.0, 0.5, 0.5), true)
	# stamina slot (reserved, H19)
	draw_rect(Rect2(ox - ORB_R, y + BOX + 4.0, ORB_R * 2, 6.0), Color(0.2, 0.2, 0.25))
	# statuses
	var st: Array = (p.statuses as Dictionary).keys()
	if not st.is_empty():
		_text(Vector2(cx, y - 24.0), " ".join(st), 14, Color(1.0, 0.75, 0.4), true)
	# monster bar
	if monster_id != "":
		var m := sim.unit(monster_id)
		if not m.is_empty():
			var mf := clampf(float(m.hp) / maxf(1.0, float(m.max_hp)), 0.0, 1.0)
			var bx := cx - BAR_W * 0.5
			draw_rect(Rect2(bx - 2, 14, BAR_W + 4, 18), Color(0.05, 0.05, 0.07, 0.8))
			draw_rect(Rect2(bx, 16, BAR_W * mf, 14), Color(0.8, 0.2, 0.15) if not bool(m.untargetable) else Color(0.4, 0.4, 0.5))
			_text(Vector2(cx, 44), "%s   %d / %d%s" % [monster_id.capitalize(), int(m.hp), int(m.max_hp), "   (submerged)" if bool(m.untargetable) else ""], 13, Color.WHITE, true)
	if sim.over != "":
		_text(Vector2(cx, size.y * 0.4), "VICTORY" if sim.over == "win" else "FALLEN", 48, Color(1, 0.9, 0.5) if sim.over == "win" else Color(0.9, 0.3, 0.3), true)


func _draw_orb_fill(c: Vector2, r: float, frac: float, col: Color) -> void:
	if frac <= 0.0:
		return
	# fill from the bottom up: a polygon of the circle below the water line
	var top := c.y + r - 2.0 * r * frac
	var pts := PackedVector2Array()
	var n := 40
	for i in n + 1:
		var a := PI + PI * float(i) / float(n)      # bottom half, left to right... then clip
		var p := c + Vector2(cos(a), -sin(a)) * r
		pts.append(p)
	# simple approach: draw the circle then cover the top with the background
	draw_circle(c, r, col)
	if frac < 1.0:
		draw_rect(Rect2(c.x - r, c.y - r, 2 * r, maxf(0.0, top - (c.y - r))), Color(0.12, 0.02, 0.03))


func _text(at: Vector2, s: String, px: int, col: Color, centered: bool = false) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if centered else 0.0
	draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0, 0, 0, 0.9))
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
