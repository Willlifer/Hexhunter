class_name HHLobbyTile
extends Control
## A lobby tile (the Gauntlet TourneyTile pattern, drawn without its shader):
## a rounded card in one muted tint, the TAG huge and faded behind a heavy
## name, a white rim when selected, a lift on hover, a lock when the key may
## not change. Hover emits `hovered` (the lobby writes the blurb to its
## ticker); a click emits `pressed`.

signal pressed(tile: HHLobbyTile)
signal hovered(tile: HHLobbyTile)

const RADIUS := 10.0           # corner radius
const HOVER_LIFT := 1.03       # scale while hovered
const TAG_ALPHA := 0.09        # the faded tag behind the name
const RIM_SELECTED := 3.0      # selected outline width
const NAME_SIZE := 30
const TAG_SIZE := 92

var id := ""
var title := ""
var tag := ""
var blurb := ""
var tint := Color("#2a3346")
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
var _font: Font


static func make(parent: Control, rect: Rect2, row: Dictionary) -> HHLobbyTile:
	var t := HHLobbyTile.new()
	t.id = str(row.id)
	t.title = str(row.name)
	t.blurb = str(row.get("blurb", ""))
	var look: Array = row.get("look", ["#2a3346", ""])
	t.tint = Color(str(look[0]))
	t.tag = str(look[1]) if look.size() > 1 else ""
	t.position = rect.position
	t.size = rect.size
	parent.add_child(t)
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	clip_contents = true                   # the faded tag stays inside its own card
	_font = ThemeDB.fallback_font
	mouse_entered.connect(func():
		if not locked:
			_hov = 1.0
			scale = Vector2.ONE * HOVER_LIFT
		hovered.emit(self))
	mouse_exited.connect(func():
		_hov = 0.0
		scale = Vector2.ONE)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	var c := tint.lightened(0.12 * _hov)
	if locked:
		c = c.darkened(0.45)
	sb.bg_color = c
	sb.set_corner_radius_all(int(RADIUS))
	if selected:
		sb.border_color = Color(1, 1, 1, 0.95)
		sb.set_border_width_all(int(RIM_SELECTED))
	else:
		sb.border_color = Color(1, 1, 1, 0.14)
		sb.set_border_width_all(1)
	draw_style_box(sb, r)
	# the faded tag, right-aligned and clipped to the card
	if tag != "":
		var tw := _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		var tx := maxf(size.x - tw - 8.0, -tw * 0.35)
		draw_string(_font, Vector2(tx, size.y * 0.5 + TAG_SIZE * 0.36), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, Color(1, 1, 1, TAG_ALPHA))
	var name_c := Color(1, 1, 1, 0.5 if locked else 1.0)
	var ns := NAME_SIZE                     # shrink a long name until it fits the card
	while ns > 16 and _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x > size.x - 32.0:
		ns -= 2
	draw_string_outline(_font, Vector2(16, size.y * 0.5 + ns * 0.36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 5, Color(0, 0, 0, 0.7))
	draw_string(_font, Vector2(16, size.y * 0.5 + ns * 0.36), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, name_c)
	if locked:
		draw_string(_font, Vector2(16, size.y - 12.0), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.4, 0.9))
	elif selected:
		draw_string(_font, Vector2(16, size.y - 12.0), "selected", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
