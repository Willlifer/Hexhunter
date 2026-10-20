class_name HHLobbyDisc
extends Control
## One element on the lobby's element strip: a coloured disc (HHLook's
## element colour) with the element's name under it and, when it is the
## active or backup element, a ring and an "active" / "backup" label. The
## control is the disc plus the label strip below it.

signal pressed(disc: HHLobbyDisc)
signal hovered(disc: HHLobbyDisc)

const RING := 4.0            # ring width round the picked discs
const NAME_SIZE := 15
const SLOT_SIZE := 13

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
var next_sets := "active"    # what the next click will set (the hover hint)

var _hov := false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		_hov = true
		queue_redraw()
		hovered.emit(self))
	mouse_exited.connect(func():
		_hov = false
		queue_redraw())


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)


func _draw() -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r)
	var col := color.darkened(0.5) if locked else color
	if _hov and not locked:
		col = col.lightened(0.15)
	draw_circle(c, r - RING, col)
	if slot != "":
		draw_arc(c, r - RING * 0.5, 0.0, TAU, 48, Color.WHITE if slot == "active" else Color(1, 1, 1, 0.6), RING)
	var name_c := Color(1, 1, 1, 0.5 if locked else 0.9)
	var nw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	draw_string(_font, Vector2(r - nw * 0.5, size.x + NAME_SIZE + 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, name_c)
	var tag := slot if slot != "" else ("LOCKED" if locked else "")
	if tag != "":
		var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, SLOT_SIZE).x
		draw_string(_font, Vector2(r - tw * 0.5, size.x + NAME_SIZE + SLOT_SIZE + 6.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, SLOT_SIZE, Color(1, 0.85, 0.4, 0.9) if locked and slot == "" else Color(1, 1, 1, 0.65))
