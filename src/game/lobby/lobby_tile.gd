class_name HHLobbyTile
extends Control
## A lobby tile: a framed card in the HUD's language (black outer edge,
## bevel, gold-dim rim, gold when selected) holding the id's thumbnail
## (art/ui/thumbs, tools/ui_thumbs.gd; L-19) over its muted tint, the name in
## the serif face on a dark strip along the bottom, a lift on hover, a lock
## when the key may not change. Without a thumbnail the old faded TAG shows.
## Hover emits `hovered` (the lobby writes the blurb to its ticker); a click
## emits `pressed`.

signal pressed(tile: HHLobbyTile)
signal hovered(tile: HHLobbyTile)

const HOVER_LIFT := 1.03       # scale while hovered
const TAG_ALPHA := 0.09        # the faded tag behind the name (no thumbnail)
const NAME_SIZE := 24
const TAG_SIZE := 92
const STRIP_H := 40.0          # the name strip

var id := ""
var kind := ""
var title := ""
var tag := ""
var blurb := ""
var tint := Color("#2a3346")
var thumb: Texture2D = null
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var locked := false:
	set(v):
		locked = v
		mouse_default_cursor_shape = Control.CURSOR_ARROW if v else Control.CURSOR_POINTING_HAND
		queue_redraw()

var _hov := 0.0


static func make(parent: Control, rect: Rect2, row: Dictionary, p_kind: String = "") -> HHLobbyTile:
	var t := HHLobbyTile.new()
	t.id = str(row.id)
	t.kind = p_kind
	t.title = str(row.name)
	t.blurb = str(row.get("blurb", ""))
	var look: Array = row.get("look", ["#2a3346", ""])
	t.tint = Color(str(look[0]))
	t.tag = str(look[1]) if look.size() > 1 else ""
	if p_kind != "":
		t.thumb = HHHud.thumb(p_kind, t.id)
	t.position = rect.position
	t.size = rect.size
	parent.add_child(t)
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	mouse_entered.connect(func():
		if not locked:
			_hov = 1.0
			scale = Vector2.ONE * HOVER_LIFT
			queue_redraw()
		hovered.emit(self))
	mouse_exited.connect(func():
		_hov = 0.0
		scale = Vector2.ONE
		queue_redraw())


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)


func _draw() -> void:
	paint(HHHud.Paint.new(get_canvas_item()))


## Paint the tile (the self-test calls this on a scratch canvas item).
func paint(pt: HHHud.Paint) -> void:
	var r := Rect2(Vector2.ZERO, size)
	pt.rect(r.grow(2.0), Color(0, 0, 0, 0.9))
	var c := tint.lightened(0.1 * _hov)
	pt.vgrad(r, c.lightened(0.12), c.darkened(0.45))
	if thumb != null:
		var opaque := kind == "arena"
		pt.tex_rect(r if opaque else r.grow(-2.0), thumb, Color(1, 1, 1, 1) if not locked else Color(0.55, 0.55, 0.55))
	elif tag != "":
		var f := ThemeDB.fallback_font
		var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		var tx := maxf(size.x - tw - 8.0, 0.0)
		f.draw_string(pt.ci, Vector2(tx, size.y * 0.5 + TAG_SIZE * 0.36), tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - tx, TAG_SIZE, Color(1, 1, 1, TAG_ALPHA))
	if locked:
		pt.rect(r, Color(0, 0, 0, 0.35))
	# the name strip: dark gradient up from the bottom edge
	var strip := Rect2(0, size.y - STRIP_H - 14.0, size.x, STRIP_H + 14.0)
	pt.vgrad(strip, Color(0, 0, 0, 0.0), Color(0.02, 0.015, 0.01, 0.88))
	var ns := NAME_SIZE
	var serif := HHHud.serif()
	while ns > 14 and pt.text_width(title, ns, serif) > size.x - 24.0:
		ns -= 2
	pt.text(Vector2(12, size.y - 12.0), title, ns, Color(1, 0.96, 0.88, 0.55 if locked else 1.0), 0, 5, serif)
	# bevel and rim
	pt.line(Vector2(1, 1), Vector2(size.x - 1, 1), Color(1, 1, 1, 0.2), 1.0)
	pt.line(Vector2(1, 1), Vector2(1, size.y - 1), Color(1, 1, 1, 0.12), 1.0)
	if selected:
		pt.frame(r, HHHud.GOLD, 2.0)
		for i in 3:
			pt.frame(r.grow(2.0 + i * 1.5), Color(HHHud.GOLD.r, HHHud.GOLD.g, HHHud.GOLD.b, 0.55 - i * 0.17), 1.5)
		_badge(pt, "LOCKED" if locked else "SELECTED", HHHud.GOLD)   # one badge: they overlapped
	else:
		pt.frame(r, HHHud.GOLD_DIM if _hov > 0.0 else Color(HHHud.GOLD_DIM.r, HHHud.GOLD_DIM.g, HHHud.GOLD_DIM.b, 0.6), 1.0)
	if locked and not selected:
		_badge(pt, "LOCKED", Color(1, 0.85, 0.4))


## A small plate in the top-right corner.
func _badge(pt: HHHud.Paint, text: String, col: Color) -> void:
	var w := pt.text_width(text, 12, HHHud.serif()) + 14.0
	var b := Rect2(size.x - w - 6.0, 6.0, w, 20.0)
	pt.rect(b, Color(0.03, 0.025, 0.02, 0.85))
	pt.frame(b, col, 1.0)
	pt.text(Vector2(b.get_center().x, b.end.y - 5.0), text, 12, col, 1, 0, HHHud.serif())
