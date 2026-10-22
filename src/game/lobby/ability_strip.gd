class_name HHAbilityStrip
extends Control
## Lane TT (H480): the picked weapon's kit as a card in the weapon row's free
## slot: "ABILITIES" over the HUD's own Q W E R slots (same glyphs, tinted by
## the active element), then a smaller row: the basic attack, the dash, the
## potion, and the active / backup element. Hovering an icon emits `hovered`
## with its key and rect (canvas space); leaving emits `hovered` with "".
## The lobby turns that into an HHAbilityTip.

signal hovered(key: String, rect: Rect2)

const BIG := 48.0
const BIG_GAP := 10.0
const SMALL := 38.0
const SMALL_GAP := 8.0
const HEAD_H := 24.0
const TOP_KEYS := ["q", "w", "e", "r"]
const LOW_KEYS := ["basic", "dash", "t", "active", "backup"]
const CAPTION := { "basic": "Basic", "dash": "Dash" }

var weapon := "lance":
	set(v):
		weapon = v
		queue_redraw()
var element := "fire":
	set(v):
		element = v
		queue_redraw()
var backup := "water":
	set(v):
		backup = v
		queue_redraw()
var hot := ""                       ## the key under the mouse ("" none)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): _set_hot(""))


## Every icon's rect in local space: { key: Rect2 }.
func rects() -> Dictionary:
	var out := {}
	var w := TOP_KEYS.size() * BIG + (TOP_KEYS.size() - 1) * BIG_GAP
	var x := (size.x - w) * 0.5
	var y := HEAD_H + 4.0
	for k in TOP_KEYS:
		out[k] = Rect2(Vector2(x, y), Vector2(BIG, BIG))
		x += BIG + BIG_GAP
	var w2 := LOW_KEYS.size() * SMALL + (LOW_KEYS.size() - 1) * SMALL_GAP + SMALL_GAP
	x = (size.x - w2) * 0.5
	y += BIG + 12.0
	for k in LOW_KEYS:
		if k == "active":
			x += SMALL_GAP                 # a little air between the kit and the elements
		out[k] = Rect2(Vector2(x, y), Vector2(SMALL, SMALL))
		x += SMALL + SMALL_GAP
	return out


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var k := ""
		var rs := rects()
		for key in rs:
			if (rs[key] as Rect2).grow(3.0).has_point(ev.position):
				k = str(key)
		_set_hot(k)


func _set_hot(k: String) -> void:
	if k == hot:
		return
	hot = k
	queue_redraw()
	hovered.emit(k, canvas_rect(k) if k != "" else Rect2())


## An icon's rect in the lobby's (canvas) space.
func canvas_rect(k: String) -> Rect2:
	var r: Rect2 = rects().get(k, Rect2())
	return Rect2(position + r.position, r.size)


func _draw() -> void:
	var pt := HHHud.Paint.new(get_canvas_item(), HHAbilityTip.body_font())
	var r := Rect2(Vector2.ZERO, size)
	pt.rect(r.grow(1.0), Color(0, 0, 0, 0.55))
	pt.vgrad(r, Color(0.12, 0.105, 0.09), Color(0.05, 0.045, 0.04))
	pt.frame(r, HHHud.GOLD_DIM, 1.0)
	pt.text(Vector2(12, 18), "ABILITIES", 14, HHHud.GOLD, 0, 2, HHHud.serif())
	pt.text(Vector2(size.x - 12, 18), "hover for details", 11, Color(1, 0.96, 0.88, 0.45), 2, 0)
	var el := HHLook.element_color(element)
	var bg := el.darkened(0.55).lerp(Color(0.16, 0.13, 0.1), 0.35)
	var rs := rects()
	for k in TOP_KEYS:
		HHHud.slot(pt, rs[k], HHHud.skill_icon(weapon, k), bg, k, 0.0, "", k == hot)
	for k in LOW_KEYS:
		var rr: Rect2 = rs[k]
		match k:
			"t":
				HHHud.slot(pt, rr, "potion", Color(0.62, 0.1, 0.14), "", 0.0, "", k == hot)
			"active":
				HHHud.slot(pt, rr, element, HHLook.element_color(element).darkened(0.1), "", 0.0, "", k == hot)
			"backup":
				HHHud.slot(pt, rr, backup, HHLook.element_color(backup).darkened(0.1), "", 0.0, "", k == hot, 0.0, 0.42)
				pt.text(Vector2(rr.end.x - 3.0, rr.position.y + 12.0), "W", 11, Color(1, 0.95, 0.85, 0.9), 2, 3, HHHud.serif())
			_:
				HHHud.slot(pt, rr, "", Color(0.2, 0.17, 0.14), "", 0.0, "", k == hot)
				pt.text(rr.get_center() + Vector2(0, 5), str(CAPTION[k]), 12, Color(1, 0.95, 0.85), 1, 3, HHHud.serif())
