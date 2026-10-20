class_name HHLobbyDisc
extends Control
## One element on the lobby's element strip, in the HUD's socket language: a
## gold-ringed socket holding the element's colour and glyph, the name under
## it. The active element wears a bright gold ring with a glow, the backup a
## silver one; hovering shows what this click will set (`next_sets`, L-19)
## as a dashed ring in that slot's colour and a "set active" / "set backup"
## tag above the disc.

signal pressed(disc: HHLobbyDisc)
signal hovered(disc: HHLobbyDisc)

const NAME_SIZE := 15
const SLOT_SIZE := 12
const ACTIVE := Color(1.0, 0.84, 0.42)
const BACKUP := Color(0.78, 0.82, 0.9)

var id := ""
var title := ""
var blurb := ""
var color := Color.WHITE
var slot := "":              # "" | "active" | "backup"
	set(v):
		slot = v
		queue_redraw()
var locked := false:
	set(v):
		locked = v
		queue_redraw()
var next_sets := "active":   # what the next click will set (the hover hint)
	set(v):
		next_sets = v
		queue_redraw()

var hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		hover = true
		queue_redraw()
		hovered.emit(self))
	mouse_exited.connect(func():
		hover = false
		queue_redraw())


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)


func _draw() -> void:
	paint(HHHud.Paint.new(get_canvas_item()))


## What the hover tag says ("" when no hint: locked, or not hovered).
func hint() -> String:
	if locked or not hover:
		return ""
	return "set " + next_sets


func paint(pt: HHHud.Paint) -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r + 14.0)
	var rr := r - 8.0
	var col := color.darkened(0.5) if locked else color
	if hover and not locked:
		col = col.lightened(0.12)
	if slot == "active":
		for i in 4:
			pt.ring(c, rr + 5.0 + i * 2.0, Color(ACTIVE.r, ACTIVE.g, ACTIVE.b, 0.5 - i * 0.12), 2.0)
	HHHud.socket(pt, c, rr + 3.0, ACTIVE if slot == "active" else (BACKUP if slot == "backup" else HHHud.GOLD_DIM))
	var pts := HHHud.circle_pts(c, rr, 40)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(col.lightened(0.25).lerp(col.darkened(0.45), clampf((p.y - (c.y - rr)) / (2.0 * rr), 0.0, 1.0)))
	pt.poly_colors(pts, cols)
	HHHud.glyph(pt, id, Rect2(c - Vector2(rr, rr) * 0.62, Vector2(rr, rr) * 1.24), Color(1, 0.97, 0.9).lerp(col.lightened(0.6), 0.2))
	if slot == "active":
		pt.ring(c, rr + 3.0, ACTIVE, 3.5)
	elif slot == "backup":
		pt.ring(c, rr + 3.0, BACKUP, 2.0)
	if locked:
		pt.circle(c, rr, Color(0, 0, 0, 0.35))
	var h := hint()
	if h != "":
		var hc := ACTIVE if next_sets == "active" else BACKUP
		var n := 24
		for i in n:
			if i % 2 == 0:
				pt.arc(c, rr + 9.0, TAU * i / n, TAU * (i + 1) / n, hc, 2.0)
		pt.text(Vector2(c.x, 10.0), h.to_upper(), SLOT_SIZE, hc, 1, 4, HHHud.serif())
	var name_c := Color(1, 1, 1, 0.5 if locked else 0.92)
	var base := c.y + rr + 8.0
	pt.text(Vector2(c.x, base + NAME_SIZE), title, NAME_SIZE, name_c, 1, 3, HHHud.serif())
	var tag := slot.to_upper() if slot != "" else ("LOCKED" if locked else "")
	if tag != "":
		var tc := ACTIVE if slot == "active" else (BACKUP if slot == "backup" else Color(1, 0.85, 0.4, 0.9))
		pt.text(Vector2(c.x, base + NAME_SIZE + SLOT_SIZE + 5.0), tag, SLOT_SIZE, tc, 1, 3)
