class_name HHAbilityTip
extends Control
## Lane TT (H482): the lobby's ability tooltip. Draws one HHAbilityInfo
## dictionary on the HUD's plate: a gold key badge and the name in the serif
## face, then its lines, each kind in its own colour (numbers bright, the
## "what it's for" line in gold, the element line in the element's colour,
## slotted upgrades in green). Word-wrapped to MAX_W. `show_for(info, anchor,
## side)` places it beside `anchor` ("above" or "left"), clamped to the
## canvas; `hide_tip()` hides it. Ignores the mouse.

const MAX_W := 470.0
const PAD := Vector2(16, 12)
const TITLE_PX := 21
const BODY_PX := 15
const LINE_GAP := 4.0
const CANVAS := Vector2(1600, 900)
const COLORS := {
	"facts": Color(1, 0.97, 0.9),
	"tiers": Color(1, 0.88, 0.62),
	"does": Color(1, 0.96, 0.88, 0.8),
	"for": Color(0.86, 0.7, 0.38),
	"element": Color(1, 1, 1),
	"upgrade": Color(0.62, 0.9, 0.55),
}

var info := {}
var element := ""                  ## the active element (tints the element line)
var _rows: Array = []              # [{ text, col }] after wrapping
static var _body: Font = null


static func body_font() -> Font:
	if _body == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(HHHud.SERIF_NAMES)
		f.fallbacks = [ThemeDB.fallback_font]
		_body = f
	return _body


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Lay out `p_info` and show it next to `anchor`.
func show_for(p_info: Dictionary, anchor: Rect2, side: String = "above") -> void:
	info = p_info
	_layout()
	var pos := Vector2.ZERO
	if side == "left":
		pos = Vector2(anchor.position.x - size.x - 10.0, anchor.get_center().y - size.y * 0.5)
	else:
		pos = Vector2(anchor.get_center().x - size.x * 0.5, anchor.position.y - size.y - 10.0)
		if pos.y < 8.0:
			pos.y = anchor.end.y + 10.0
	pos.x = clampf(pos.x, 8.0, CANVAS.x - size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, CANVAS.y - size.y - 8.0)
	position = pos
	visible = true
	queue_redraw()


func hide_tip() -> void:
	visible = false
	info = {}


func showing() -> String:
	return str(info.get("key", "")) if visible else ""


## Wrap the lines and size the panel.
func _layout() -> void:
	_rows.clear()
	var f := body_font()
	var widest := 0.0
	var title_w := HHHud.serif().get_string_size(str(info.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX).x
	if str(info.get("label", "")) != "":
		title_w += _badge_w() + 10.0
	widest = title_w
	for ln in info.get("lines", []):
		var col: Color = COLORS.get(str(ln.kind), COLORS.does)
		if str(ln.kind) == "element":
			var el := str(info.get("element", element))
			col = HHLook.element_color(el).lerp(Color(1, 0.97, 0.9), 0.45) if el != "" else col
		for t in wrap_text(str(ln.text), f, BODY_PX, MAX_W - PAD.x * 2.0):
			_rows.append({ "text": t, "col": col })
			widest = maxf(widest, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_PX).x)
	var h := PAD.y * 2.0 + TITLE_PX + 10.0 + _rows.size() * (BODY_PX + LINE_GAP)
	size = Vector2(minf(MAX_W, widest + PAD.x * 2.0), h)


func _badge_w() -> float:
	return maxf(26.0, HHHud.serif().get_string_size(str(info.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0)


## Greedy word wrap at `width` pixels.
static func wrap_text(text: String, f: Font, px: int, width: float) -> Array:
	var out: Array = []
	var cur := ""
	for word in text.split(" ", false):
		var t := word if cur == "" else cur + " " + word
		if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
			out.append(cur)
			cur = word
		else:
			cur = t
	if cur != "":
		out.append(cur)
	return out


func _draw() -> void:
	if info.is_empty():
		return
	var pt := HHHud.Paint.new(get_canvas_item(), body_font())
	var r := Rect2(Vector2.ZERO, size)
	pt.rect(r.grow(6.0), Color(0, 0, 0, 0.35))
	pt.rect(r, Color(0.06, 0.05, 0.045))
	HHHud.plate(pt, r)
	pt.frame(r, Color(HHHud.GOLD_DIM.r, HHHud.GOLD_DIM.g, HHHud.GOLD_DIM.b, 0.8), 1.0)
	var x := PAD.x
	var base := PAD.y + TITLE_PX - 2.0
	var label := str(info.get("label", ""))
	if label != "":
		var bw := _badge_w()
		var br := Rect2(Vector2(x, PAD.y + 1.0), Vector2(bw, TITLE_PX + 1.0))
		pt.rect(br, Color(0.08, 0.065, 0.05))
		pt.frame(br, HHHud.GOLD, 1.0)
		pt.text(Vector2(br.get_center().x, br.end.y - 5.0), label, 14, HHHud.GOLD, 1, 0, HHHud.serif())
		x += bw + 10.0
	pt.text(Vector2(x, base), str(info.get("title", "")), TITLE_PX, HHHud.GOLD, 0, 3, HHHud.serif())
	var y := PAD.y + TITLE_PX + 6.0
	pt.line(Vector2(PAD.x, y), Vector2(size.x - PAD.x, y), Color(HHHud.GOLD_DIM.r, HHHud.GOLD_DIM.g, HHHud.GOLD_DIM.b, 0.6), 1.0)
	y += 4.0
	for row in _rows:
		y += BODY_PX + LINE_GAP
		pt.text(Vector2(PAD.x, y - 3.0), str(row.text), BODY_PX, row.col, 0, 0)
