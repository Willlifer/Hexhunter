class_name HHHud
extends Control
## The bottom action bar (kickoff HUD, after ref/ui_hud.jpg): Q W E R skill
## icons left of a glass HP orb, the active + backup element and the potion
## right of it, all on one dark plate with a gold trim; the monster's name
## plate and HP bar at the top. Drawn from sim state every frame; no nodes
## per element, so it never drifts from the sim.
## L-12: status icons over the bar and a monster-state socket on the monster
## plate. Visual pass (Lane UI, H800-H849): painted glyph icons per skill,
## element and status (`glyph`), a radial cooldown sweep, a liquid orb, a
## serif face (`serif()`), a ghost bar on the monster's HP.
##
## Everything goes through `Paint` (RenderingServer calls on a canvas item
## RID), so the self-test can paint the whole HUD into a scratch RID
## headless; `_draw` just paints into this control's own item.

const SLOT := 60.0                  ## skill icon size
const SLOT_GAP := 4.0
const ORB_R := 54.0
const ORB_GAP := 20.0               ## the orb socket to the nearest slot
const BOTTOM := 14.0                ## the slots' bottom edge above the screen's
const BAR_W := 520.0                ## the monster HP bar
const BAR_H := 16.0
const KEYS := ["q", "w", "e", "r"]
const ICON := 30.0                  ## status icon box
const ICON_GAP := 5.0
const GOLD := Color(0.86, 0.7, 0.38)
const GOLD_DIM := Color(0.52, 0.41, 0.23)
const PLATE_TOP := Color(0.15, 0.13, 0.11, 0.93)
const PLATE_BOT := Color(0.035, 0.03, 0.03, 0.97)
const INK := Color(0.03, 0.025, 0.02, 0.92)     ## glyph outlines and cut lines
const SERIF_NAMES := ["Cambria", "Georgia", "Book Antiqua", "Palatino Linotype", "Times New Roman", "serif"]
const THUMB_DIR := "res://art/ui/thumbs"

## Status icons: glyph (a fallback letter), icon (a `glyph` id), colour.
## Unknown statuses fall back to the first letter in grey.
const STATUS := {
	"slow":      { "glyph": "S",  "icon": "slow",    "color": Color(0.45, 0.72, 1.0),  "label": "slow" },
	"freeze":    { "glyph": "*",  "icon": "ice",     "color": Color(0.75, 0.95, 1.0),  "label": "frozen" },
	"poison":    { "glyph": "P",  "icon": "poison",  "color": Color(0.45, 0.9, 0.35),  "label": "poison" },
	"paralysis": { "glyph": "Z",  "icon": "thunder", "color": Color(0.85, 0.55, 1.0),  "label": "paralysed" },
	"burn":      { "glyph": "^",  "icon": "fire",    "color": Color(1.0, 0.5, 0.2),    "label": "burn" },
	"wet":       { "glyph": "~",  "icon": "water",   "color": Color(0.35, 0.6, 1.0),   "label": "wet" },
	"stagger":   { "glyph": "!",  "icon": "star",    "color": Color(1.0, 0.85, 0.4),   "label": "staggered" },
}
## Monster-state icons on the monster plate (HHMonsterBody.state_name values).
const MONSTER_STATE := {
	"smouldering": { "glyph": "^", "icon": "fire",    "color": Color(1.0, 0.45, 0.15), "label": "smouldering" },
	"cold":        { "glyph": "*", "icon": "ice",     "color": Color(0.62, 0.92, 1.0), "label": "cold" },
	"charged":     { "glyph": "z", "icon": "thunder", "color": Color(0.75, 0.45, 1.0), "label": "charged" },
	"reeds_burnt": { "glyph": "x", "icon": "cross",   "color": Color(0.55, 0.45, 0.4), "label": "reeds cut" },
	"darkness":    { "glyph": "o", "icon": "dark",    "color": Color(0.5, 0.25, 0.9),  "label": "darkness" },
	"submerged":   { "glyph": "~", "icon": "water",   "color": Color(0.4, 0.55, 0.8),  "label": "submerged" },
}
## The glyph each weapon skill wears.
const SKILL_ICON := {
	"lance":   { "q": "pierce",    "w": "exchange", "e": "guard",      "r": "eruption" },
	"daggers": { "q": "flourish",  "w": "exchange", "e": "daggerleap", "r": "knifedance" },
	"bow":     { "q": "energized", "w": "exchange", "e": "arcing",     "r": "arrowstorm" },
}
## Every glyph id `glyph_ops` draws (the self-test walks it).
const GLYPHS := ["pierce", "exchange", "guard", "eruption", "flourish", "daggerleap", "knifedance",
	"energized", "arcing", "arrowstorm", "potion", "fire", "water", "ice", "thunder", "wind", "dark",
	"light", "poison", "slow", "star", "cross"]


## The monster's reactive state from its unit dictionary (pure; the body's
## own state_name agrees). "" when it has none to show.
static func monster_state_of(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	if bool(m.get("reeds_burnt", false)):
		return "reeds_burnt"
	if bool(m.get("smoulder", false)):
		return "smouldering"
	if float(m.get("charge", 0.0)) > 0.6:
		return "charged"
	if float(m.get("cold", 0.0)) > 0.5:
		return "cold"
	if bool(m.get("untargetable", false)):
		return "submerged"
	return ""


## The player's statuses as rows { name, seconds }, longest first (pure).
static func status_rows(u: Dictionary) -> Array:
	var out: Array = []
	var st: Dictionary = u.get("statuses", {})
	for name in st:
		out.append({ "name": str(name), "seconds": float((st[name] as Dictionary).get("ticks", 0)) / 30.0 })
	out.sort_custom(func(a, b): return float(a.seconds) > float(b.seconds))
	return out


## The skill glyph for a weapon key ("" when unknown: the slot shows its letter).
static func skill_icon(weapon: String, key: String) -> String:
	if key == "t":
		return "potion"
	return str((SKILL_ICON.get(weapon, {}) as Dictionary).get(key, ""))


## Where everything on the bar sits for a screen size (pure, for tests and
## the comparison tool): slots {q w e r: Rect2}, orb {c, r}, element,
## backup, potion, plate (Rect2s), status (the first status icon's corner),
## monster (the HP bar's Rect2).
static func layout(size: Vector2) -> Dictionary:
	var cx := size.x * 0.5
	var sy := size.y - BOTTOM - SLOT
	var left_w := 4.0 * SLOT + 3.0 * SLOT_GAP
	var lx := cx - ORB_R - ORB_GAP - left_w
	var slots := {}
	for i in KEYS.size():
		slots[KEYS[i]] = Rect2(lx + i * (SLOT + SLOT_GAP), sy, SLOT, SLOT)
	var rx := cx + ORB_R + ORB_GAP
	var element := Rect2(rx, sy, SLOT, SLOT)
	var bs := SLOT * 0.72
	var backup := Rect2(element.end.x + SLOT_GAP, sy + SLOT - bs, bs, bs)
	var potion := Rect2(backup.end.x + 16.0, sy, SLOT, SLOT)
	var plate := Rect2(lx - 14.0, sy - 9.0, potion.end.x + 14.0 - (lx - 14.0), size.y - (sy - 9.0) - 3.0)
	return {
		"slots": slots, "orb": { "c": Vector2(cx, sy + SLOT * 0.5 - 12.0), "r": ORB_R },
		"element": element, "backup": backup, "potion": potion, "plate": plate,
		"status": Vector2(lx, plate.position.y - 10.0 - ICON),
		"monster": Rect2(cx - BAR_W * 0.5, 38.0, BAR_W, BAR_H),
	}


# ------------------------------------------------------------------ fonts, thumbs

static var _serif: Font = null
static var _thumbs := {}


## The display face: a system serif (Cambria / Georgia ...) in bold, falling
## back to the engine font where none is installed. Nothing is bundled.
static func serif() -> Font:
	if _serif == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(SERIF_NAMES)
		f.font_weight = 700
		f.fallbacks = [ThemeDB.fallback_font]
		_serif = f
	return _serif


## A thumbnail from art/ui/thumbs (tools/ui_thumbs.gd): `kind` arena |
## monster | weapon. Imported when the project has been imported, else read
## straight from the PNG; null when there is none.
static func thumb(kind: String, id: String) -> Texture2D:
	var key := "%s_%s" % [kind, id]
	if _thumbs.has(key):
		return _thumbs[key]
	var path := "%s/%s.png" % [THUMB_DIR, key]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_thumbs[key] = tex
	return tex


static func thumb_path(kind: String, id: String) -> String:
	return "%s/%s_%s.png" % [THUMB_DIR, kind, id]


# ------------------------------------------------------------------ the painter

## RenderingServer drawing on one canvas item RID. `_draw` hands it this
## control's item; the self-test hands it a scratch item.
class Paint:
	extends RefCounted
	var ci: RID
	var font: Font

	func _init(item: RID, p_font: Font = null) -> void:
		ci = item
		font = p_font if p_font != null else ThemeDB.fallback_font

	func rect(r: Rect2, col: Color) -> void:
		RenderingServer.canvas_item_add_rect(ci, r, col)

	func frame(r: Rect2, col: Color, w: float = 1.0) -> void:
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([col]), w, false)

	func line(a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
		RenderingServer.canvas_item_add_line(ci, a, b, col, w, true)

	func polyline(pts: PackedVector2Array, col: Color, w: float = 1.0, closed: bool = false) -> void:
		if pts.size() < 2:
			return
		var p := pts
		if closed:
			p = pts.duplicate()
			p.append(pts[0])
		RenderingServer.canvas_item_add_polyline(ci, p, PackedColorArray([col]), w, true)

	func poly(pts: PackedVector2Array, col: Color) -> void:
		if pts.size() >= 3:
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))

	func poly_colors(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		if pts.size() >= 3 and cols.size() == pts.size():
			RenderingServer.canvas_item_add_polygon(ci, pts, cols)

	func tex_poly(pts: PackedVector2Array, uvs: PackedVector2Array, tex: Texture2D, mod: Color = Color.WHITE) -> void:
		if tex != null and pts.size() >= 3:
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([mod]), uvs, tex.get_rid())

	func tex_rect(r: Rect2, tex: Texture2D, mod: Color = Color.WHITE) -> void:
		if tex != null:
			RenderingServer.canvas_item_add_texture_rect(ci, r, tex.get_rid(), false, mod)

	func circle(c: Vector2, r: float, col: Color) -> void:
		poly(HHHud.circle_pts(c, r, maxi(16, int(r * 0.8))), col)

	func arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float = 1.0) -> void:
		var n := maxi(8, int(absf(a1 - a0) * r * 0.25))
		polyline(HHHud.circle_pts(c, r, n, a0, a1, true), col, w)

	func ring(c: Vector2, r: float, col: Color, w: float = 1.0) -> void:
		arc(c, r, 0.0, TAU, col, w)

	## A vertical gradient rectangle.
	func vgrad(r: Rect2, top: Color, bottom: Color) -> void:
		poly_colors(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))

	func rounded(r: Rect2, col: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(radius))
		if bw > 0:
			sb.border_color = border
			sb.set_border_width_all(bw)
		sb.draw(ci, r)

	func text_width(s: String, px: int, f: Font = null) -> float:
		return (f if f != null else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x

	## Text with an outline. align: 0 left, 1 centred, 2 right of `at`.
	func text(at: Vector2, s: String, px: int, col: Color, align: int = 0, outline: int = 3, f: Font = null, ocol: Color = Color(0, 0, 0, 0.9)) -> void:
		var ff := f if f != null else font
		var w := text_width(s, px, ff)
		var p := at - Vector2(w * 0.5 * align, 0.0)
		if outline > 0:
			ff.draw_string_outline(ci, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, ocol)
		ff.draw_string(ci, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static func circle_pts(c: Vector2, r: float, n: int, a0: float = 0.0, a1: float = TAU, include_end: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := n if not include_end else n + 1
	for i in steps:
		var a := a0 + (a1 - a0) * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# ------------------------------------------------------------------ glyphs

## A glyph as ops in unit space (0..1 both ways): { line: pts, w } polylines,
## { poly: pts } fills, { dot: centre, r } discs; `cut: true` draws in ink
## over the fill (inner detail). [] for an unknown id.
static func glyph_ops(id: String) -> Array:
	var o: Array = []
	match id:
		"pierce":
			o.append(_l([Vector2(0.14, 0.86), Vector2(0.6, 0.4)], 0.07))
			o.append({ "poly": PackedVector2Array([Vector2(0.88, 0.12), Vector2(0.64, 0.5), Vector2(0.5, 0.36)]) })
			o.append(_l([Vector2(0.1, 0.6), Vector2(0.27, 0.43)], 0.035))
			o.append(_l([Vector2(0.4, 0.9), Vector2(0.57, 0.73)], 0.035))
		"exchange":
			var c := Vector2(0.5, 0.5)
			for a in [[PI * 1.06, PI * 1.74], [PI * 0.06, PI * 0.74]]:
				o.append(_l(circle_pts(c, 0.3, 14, a[0], a[1], true), 0.075))
				o.append({ "poly": _head_at_arc(c, 0.3, a[1], 0.17) })
		"guard":
			o.append({ "poly": PackedVector2Array([Vector2(0.5, 0.1), Vector2(0.84, 0.22), Vector2(0.8, 0.54), Vector2(0.5, 0.9), Vector2(0.2, 0.54), Vector2(0.16, 0.22)]) })
			o.append(_l([Vector2(0.5, 0.24), Vector2(0.5, 0.76)], 0.05, true))
			o.append(_l([Vector2(0.28, 0.4), Vector2(0.72, 0.4)], 0.05, true))
		"eruption":
			o.append({ "poly": _star(Vector2(0.5, 0.54), 0.38, 0.15, 8) })
			o.append({ "dot": Vector2(0.5, 0.54), "r": 0.07, "cut": true })
			o.append(_l([Vector2(0.08, 0.9), Vector2(0.92, 0.9)], 0.05))
		"flourish":
			var c := Vector2(0.5, 0.5)
			o.append(_l(circle_pts(c, 0.3, 20, -PI * 0.35, PI * 1.25, true), 0.065))
			o.append({ "poly": _head_at_arc(c, 0.3, PI * 1.25, 0.17) })
			for a in [PI * 0.15, PI * 0.8]:
				var d := Vector2(cos(a), sin(a))
				var t := Vector2(-d.y, d.x)
				var b := c + d * 0.3
				o.append({ "poly": PackedVector2Array([b + t * 0.06, b + d * 0.2, b - t * 0.06]) })
			o.append({ "dot": c, "r": 0.08 })
		"daggerleap":
			o.append_array(_dashes(_quad(Vector2(0.1, 0.88), Vector2(0.14, 0.22), Vector2(0.5, 0.44), 12), 0.045))
			o.append_array(_dagger(Vector2(0.48, 0.52), Vector2(0.9, 0.12)))
		"knifedance":
			o.append_array(_dagger(Vector2(0.18, 0.86), Vector2(0.8, 0.18)))
			o.append_array(_dagger(Vector2(0.82, 0.86), Vector2(0.2, 0.18)))
			o.append(_l(circle_pts(Vector2(0.5, 0.56), 0.44, 12, PI * 1.18, PI * 1.82, true), 0.035))
		"energized":
			o.append(_l([Vector2(0.16, 0.84), Vector2(0.72, 0.28)], 0.055))
			o.append({ "poly": _head(Vector2(0.88, 0.12), Vector2(1, -1).normalized(), 0.22) })
			o.append(_l([Vector2(0.16, 0.84), Vector2(0.1, 0.68)], 0.04))
			o.append(_l([Vector2(0.16, 0.84), Vector2(0.32, 0.9)], 0.04))
			o.append({ "poly": PackedVector2Array([Vector2(0.4, 0.08), Vector2(0.2, 0.36), Vector2(0.31, 0.36), Vector2(0.22, 0.56), Vector2(0.46, 0.26), Vector2(0.34, 0.26), Vector2(0.46, 0.08)]) })
		"arcing":
			o.append_array(_dashes(_quad(Vector2(0.08, 0.88), Vector2(0.34, -0.08), Vector2(0.6, 0.52), 14), 0.045))
			o.append({ "dot": Vector2(0.68, 0.68), "r": 0.17 })
			o.append(_l([Vector2(0.78, 0.55), Vector2(0.88, 0.42)], 0.04))
			o.append({ "poly": _star(Vector2(0.9, 0.38), 0.08, 0.035, 5) })
		"arrowstorm":
			var xs := [0.24, 0.5, 0.76]
			var ys := [0.14, 0.06, 0.18]
			for i in 3:
				var x: float = xs[i]
				var y: float = ys[i]
				o.append(_l([Vector2(x, y), Vector2(x, y + 0.5)], 0.05))
				o.append({ "poly": _head(Vector2(x, y + 0.66), Vector2(0, 1), 0.16) })
				o.append(_l([Vector2(x - 0.07, y - 0.03), Vector2(x, y + 0.08), Vector2(x + 0.07, y - 0.03)], 0.035))
			o.append(_l([Vector2(0.08, 0.92), Vector2(0.92, 0.92)], 0.045))
		"potion":
			o.append({ "dot": Vector2(0.5, 0.64), "r": 0.26 })
			o.append({ "poly": _box(0.41, 0.22, 0.59, 0.44) })
			o.append({ "poly": _box(0.37, 0.1, 0.63, 0.22) })
			o.append(_l([Vector2(0.3, 0.6), Vector2(0.7, 0.6)], 0.035, true))
		"fire":
			o.append({ "poly": PackedVector2Array([Vector2(0.5, 0.06), Vector2(0.6, 0.26), Vector2(0.72, 0.38), Vector2(0.8, 0.56), Vector2(0.76, 0.74), Vector2(0.64, 0.88), Vector2(0.5, 0.92), Vector2(0.36, 0.88), Vector2(0.24, 0.74), Vector2(0.2, 0.56), Vector2(0.28, 0.4), Vector2(0.36, 0.48), Vector2(0.38, 0.3)]) })
			o.append({ "poly": PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.59, 0.64), Vector2(0.61, 0.76), Vector2(0.5, 0.85), Vector2(0.39, 0.76), Vector2(0.42, 0.63)]), "cut": true })
		"water":
			o.append({ "poly": _drop(Vector2(0.5, 0.08), Vector2(0.5, 0.62), 0.27) })
			o.append(_l(circle_pts(Vector2(0.5, 0.62), 0.16, 6, PI * 0.6, PI * 0.95, true), 0.045, true))
		"poison":
			o.append({ "poly": _drop(Vector2(0.42, 0.14), Vector2(0.42, 0.64), 0.25) })
			o.append({ "dot": Vector2(0.8, 0.28), "r": 0.08 })
			o.append({ "dot": Vector2(0.84, 0.52), "r": 0.055 })
		"ice":
			var c := Vector2(0.5, 0.5)
			for a in [PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]:
				var d := Vector2(cos(a), sin(a))
				o.append(_l([c - d * 0.4, c + d * 0.4], 0.065))
				for s in [-1.0, 1.0]:
					var b: Vector2 = c + d * 0.24 * s
					for k in [-1.0, 1.0]:
						o.append(_l([b, b + (d * s).rotated(k * PI / 4.0) * 0.13], 0.05))
		"thunder":
			o.append({ "poly": PackedVector2Array([Vector2(0.6, 0.06), Vector2(0.24, 0.54), Vector2(0.46, 0.54), Vector2(0.36, 0.94), Vector2(0.78, 0.4), Vector2(0.55, 0.4), Vector2(0.7, 0.06)]) })
		"wind":
			var a := PackedVector2Array([Vector2(0.08, 0.36), Vector2(0.58, 0.36)])
			a.append_array(circle_pts(Vector2(0.58, 0.24), 0.12, 10, PI * 0.5, -PI * 0.9, true))
			o.append(_l(a, 0.055))
			var b := PackedVector2Array([Vector2(0.16, 0.56), Vector2(0.76, 0.56)])
			b.append_array(circle_pts(Vector2(0.76, 0.44), 0.12, 10, PI * 0.5, -PI * 0.9, true))
			o.append(_l(b, 0.055))
			var c2 := PackedVector2Array([Vector2(0.1, 0.74), Vector2(0.5, 0.74)])
			c2.append_array(circle_pts(Vector2(0.5, 0.84), 0.1, 10, -PI * 0.5, PI * 0.9, true))
			o.append(_l(c2, 0.055))
		"dark":
			var cres := Geometry2D.clip_polygons(circle_pts(Vector2(0.5, 0.52), 0.37, 28), circle_pts(Vector2(0.66, 0.38), 0.3, 28))
			if not cres.is_empty():
				o.append({ "poly": cres[0] })
			o.append({ "poly": _star(Vector2(0.74, 0.72), 0.1, 0.04, 4) })
		"light":
			var c := Vector2(0.5, 0.5)
			o.append({ "dot": c, "r": 0.19 })
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				o.append(_l([c + d * 0.28, c + d * 0.43], 0.06))
		"slow":
			o.append(_l([Vector2(0.22, 0.22), Vector2(0.5, 0.46), Vector2(0.78, 0.22)], 0.1))
			o.append(_l([Vector2(0.22, 0.52), Vector2(0.5, 0.76), Vector2(0.78, 0.52)], 0.1))
		"star":
			o.append({ "poly": _star(Vector2(0.5, 0.53), 0.42, 0.18, 5) })
		"cross":
			o.append(_l([Vector2(0.2, 0.2), Vector2(0.8, 0.8)], 0.11))
			o.append(_l([Vector2(0.8, 0.2), Vector2(0.2, 0.8)], 0.11))
	return o


## Paint a glyph into `r` in `col` with an ink outline (two passes: every
## outline first, so overlapping strokes merge into one silhouette).
static func glyph(pt: Paint, id: String, r: Rect2, col: Color, ink: Color = INK) -> bool:
	var ops := glyph_ops(id)
	if ops.is_empty():
		return false
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var ow := maxf(1.5, s * 0.06)
	for pass_ in 2:
		for op in ops:
			var cut := bool(op.get("cut", false))
			if pass_ == 0 and cut:
				continue
			var c := ink if (pass_ == 0 or cut) else col
			if op.has("line"):
				var pts := _scaled(op.line, o, s)
				var w := float(op.w) * s + (ow if pass_ == 0 else 0.0)
				pt.polyline(pts, c, w)
				if pass_ == 0:                       # round the stroke ends
					pt.circle(pts[0], w * 0.5, c)
					pt.circle(pts[pts.size() - 1], w * 0.5, c)
			elif op.has("poly"):
				var pts := _scaled(op.poly, o, s)
				if pass_ == 0:
					pt.polyline(pts, c, ow * 2.0, true)
				pt.poly(pts, c)
				if pass_ == 1:
					pt.polyline(pts, c, 1.0, true)     # anti-aliased edge
			elif op.has("dot"):
				var cc: Vector2 = o + (op.dot as Vector2) * s
				pt.circle(cc, float(op.r) * s + (ow if pass_ == 0 else 0.0), c)
	return true


## Triangle-fan indices for a centre + ring array (a radial gradient).
static func _fan(n: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for i in range(1, n - 1):
		idx.append_array([0, i, i + 1])
	return idx


static func _scaled(pts: PackedVector2Array, o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(o + p * s)
	return out


static func _l(pts: Array, w: float, cut: bool = false) -> Dictionary:
	return { "line": PackedVector2Array(pts), "w": w, "cut": cut }


static func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


static func _star(c: Vector2, ro: float, ri: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n * 2:
		var a := -PI * 0.5 + PI * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * (ro if i % 2 == 0 else ri))
	return out


static func _head(tip: Vector2, dir: Vector2, size: float) -> PackedVector2Array:
	var perp := Vector2(-dir.y, dir.x)
	return PackedVector2Array([tip, tip - dir * size + perp * size * 0.55, tip - dir * size - perp * size * 0.55])


static func _head_at_arc(c: Vector2, r: float, a: float, size: float) -> PackedVector2Array:
	var p := c + Vector2(cos(a), sin(a)) * r
	var t := Vector2(-sin(a), cos(a))
	return _head(p + t * size * 0.75, t, size)


static func _quad(a: Vector2, ctrl: Vector2, b: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out


static func _dashes(pts: PackedVector2Array, w: float) -> Array:
	var out: Array = []
	for i in range(0, pts.size() - 1, 2):
		out.append(_l([pts[i], pts[i + 1]], w))
	return out


static func _dagger(base: Vector2, tip: Vector2) -> Array:
	var d := (tip - base).normalized()
	var perp := Vector2(-d.y, d.x)
	var g := base + (tip - base) * 0.3
	return [
		_l([base, g], 0.05),
		_l([g + perp * 0.1, g - perp * 0.1], 0.045),
		{ "poly": PackedVector2Array([g + perp * 0.055, tip, g - perp * 0.055]) },
	]


static func _drop(tip: Vector2, c: Vector2, r: float) -> PackedVector2Array:
	var d := tip.distance_to(c)
	var th := acos(clampf(r / d, -1.0, 1.0))
	var up := (tip - c).angle()
	var out := PackedVector2Array([tip])
	out.append_array(circle_pts(c, r, 20, up + th, up + TAU - th, true))
	return out


# ------------------------------------------------------------------ shared pieces

## An icon slot: bevelled frame, a gradient in `bg`, the glyph, a radial
## cooldown sweep (`cd_frac` of the turn left, clockwise from 12 o'clock,
## `cd_text` centred), the key letter, a gold glow when `active`, a white
## flash `flash` (0..1) when it comes off cooldown.
static func slot(pt: Paint, r: Rect2, icon: String, bg: Color, key: String = "", cd_frac: float = 0.0,
		cd_text: String = "", active: bool = false, flash: float = 0.0, dim: float = 0.0) -> void:
	pt.rect(r.grow(2.0), Color(0, 0, 0, 0.92))
	var tl := bg.lightened(0.22)
	var br := bg.darkened(0.6)
	pt.poly_colors(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([tl, bg, br, bg.darkened(0.3)]))
	# a lit core behind the glyph (the painted icons' depth) and a soft shine
	var core := PackedVector2Array([r.get_center()])
	var core_cols := PackedColorArray([bg.lightened(0.55)])
	for q in circle_pts(r.get_center(), r.size.x * 0.48, 24, 0.0, TAU, true):
		core.append(q)
		core_cols.append(Color(bg.r, bg.g, bg.b, 0.0))
	RenderingServer.canvas_item_add_triangle_array(pt.ci, _fan(core.size()), core, core_cols)
	pt.poly(circle_pts(r.position + r.size * Vector2(0.34, 0.3), r.size.x * 0.3, 18), Color(1, 1, 1, 0.07))
	var gcol := Color(1.0, 0.97, 0.9).lerp(bg.lightened(0.6), 0.18)
	if not glyph(pt, icon, r.grow(-r.size.x * 0.15), gcol):
		pt.text(r.get_center() + Vector2(0, r.size.y * 0.18), key.to_upper(), int(r.size.y * 0.5), gcol, 1, 4, serif())
	if dim > 0.0:
		pt.rect(r, Color(0, 0, 0, dim))
	# bevel: light top-left, dark bottom-right
	pt.line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 1, 1, 0.22), 1.0)
	pt.line(r.position + Vector2(1, 1), Vector2(r.position.x + 1, r.end.y - 1), Color(1, 1, 1, 0.14), 1.0)
	pt.line(Vector2(r.position.x + 1, r.end.y - 1), r.end - Vector2(1, 1), Color(0, 0, 0, 0.5), 1.0)
	pt.line(Vector2(r.end.x - 1, r.position.y + 1), r.end - Vector2(1, 1), Color(0, 0, 0, 0.5), 1.0)
	if cd_frac > 0.0:
		sweep(pt, r, cd_frac)
		if cd_text != "":
			pt.text(r.get_center() + Vector2(0, 8), cd_text, 22, Color.WHITE, 1, 4, serif())
	if flash > 0.0:
		pt.rect(r, Color(1, 1, 0.9, 0.55 * flash))
	pt.frame(r, GOLD if active else GOLD_DIM, 1.0)
	if active:
		for i in 4:
			pt.frame(r.grow(1.5 + i * 1.5), Color(GOLD.r, GOLD.g, GOLD.b, 0.75 - i * 0.18), 1.5)
	if key != "":
		pt.text(r.position + Vector2(5, r.size.y - 5), key.to_upper(), 14, Color(1, 0.95, 0.85), 0, 3, serif())


## The cooldown shade: the part of the turn still to run, as a pie clipped
## to the slot, with a bright hand on its leading edge.
static func sweep(pt: Paint, r: Rect2, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0:
		return
	var c := r.get_center()
	var rad := r.size.length()
	var a0 := -PI * 0.5 + TAU * (1.0 - frac)
	var a1 := -PI * 0.5 + TAU
	var pie := PackedVector2Array([c])
	pie.append_array(circle_pts(c, rad, maxi(3, int(48 * frac)), a0, a1, true))
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if frac >= 0.999:
		pt.poly(box, Color(0, 0, 0, 0.66))
	else:
		for part in Geometry2D.intersect_polygons(pie, box):
			pt.poly(part, Color(0, 0, 0, 0.66))
	if frac < 0.999:
		var hand := c + Vector2(cos(a0), sin(a0)) * rad
		var clipped := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([c, hand]), box)
		for seg in clipped:
			pt.polyline(seg, Color(1, 0.92, 0.7, 0.75), 1.5)


## A dark plate with a gold trim and diamond end caps (the action bar, the
## monster plate, the ambush and results banners share it).
static func plate(pt: Paint, r: Rect2, trim_top: bool = true, trim_bottom: bool = false, alpha: float = 1.0) -> void:
	var top := PLATE_TOP
	var bot := PLATE_BOT
	top.a *= alpha
	bot.a *= alpha
	pt.rounded(r.grow(1.0), Color(0, 0, 0, 0.55 * alpha), 7.0)
	pt.vgrad(Rect2(r.position + Vector2(3, 0), r.size - Vector2(6, 0)), top, bot)
	pt.vgrad(Rect2(r.position + Vector2(0, 3), Vector2(3, r.size.y - 3)), top, bot)
	pt.vgrad(Rect2(Vector2(r.end.x - 3, r.position.y + 3), Vector2(3, r.size.y - 3)), top, bot)
	var g := Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * alpha)
	for y in ([r.position.y] if trim_top else []) + ([r.end.y] if trim_bottom else []):
		pt.line(Vector2(r.position.x + 8, y + 0.5), Vector2(r.end.x - 8, y + 0.5), g, 1.5)
		pt.line(Vector2(r.position.x + 14, y + 3.5), Vector2(r.end.x - 14, y + 3.5), Color(g.r, g.g, g.b, 0.25 * alpha), 1.0)
		for x in [r.position.x + 6.0, r.end.x - 6.0]:
			pt.poly(PackedVector2Array([Vector2(x, y - 4.5), Vector2(x + 4.5, y), Vector2(x, y + 4.5), Vector2(x - 4.5, y)]), g)


## A round socket (orb, portrait, state): dark well, gold ring, ink inner ring.
static func socket(pt: Paint, c: Vector2, r: float, ring_col: Color = GOLD) -> void:
	pt.circle(c, r + 3.0, Color(0, 0, 0, 0.6))
	pt.circle(c, r, PLATE_BOT)
	pt.ring(c, r, ring_col, 2.0)
	pt.ring(c, r - 2.5, Color(0, 0, 0, 0.8), 2.0)


## A circular crop of a thumbnail (the monster portrait).
static func thumb_disc(pt: Paint, tex: Texture2D, c: Vector2, r: float, zoom: float = 1.0) -> void:
	if tex == null:
		return
	var sz := tex.get_size()
	var aspect := sz.y / maxf(1.0, sz.x)
	var pts := circle_pts(c, r, 40)
	var uvs := PackedVector2Array()
	for p in pts:
		var d := (p - c) / r
		uvs.append(Vector2(0.5 + d.x * 0.5 * aspect / zoom, 0.5 + d.y * 0.5 / zoom))
	pt.tex_poly(pts, uvs, tex)


# ------------------------------------------------------------------ the HUD

var sim: HHSim
var player_id := ""
var monster_id := ""
var monster_body: Node = null       ## optional: the monster's HHMonsterBody (its state_name wins over the unit read)
var font: Font
## Co-op (Lane C, H903-H906): set by HHFight only when the party has more than one hunter.
var party: Array = []               ## [{ id, name }] in slot order: the party frames at the left
var plates: Array = []              ## [{ id, pos: Vector2 }] where each hunter's nameplate sits this frame
var revive := {}                    ## hunter id -> revive progress 0..1 (from the sim's revive events)
var gone := {}                      ## hunter id -> true: that peer disconnected mid-fight (its hunter idles on the host)
var spectating := ""                ## the ally the camera follows while the local hunter is down
var _t := 0.0
var _ghost := -1.0                  ## the monster bar's trailing (recent damage) fraction
var _prev_cd := {}
var _flash := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	tick(delta)
	queue_redraw()


## Advance the HUD's own animation state (ghost bar, cooldown-ready flashes).
func tick(delta: float) -> void:
	_t += delta
	if sim == null:
		return
	var p := sim.unit(player_id)
	if not p.is_empty():
		for k in KEYS + ["t"]:
			var cd := int((p.cooldowns as Dictionary).get(k, 0))
			if int(_prev_cd.get(k, 0)) > 0 and cd == 0:
				_flash[k] = 1.0
			_prev_cd[k] = cd
			_flash[k] = maxf(0.0, float(_flash.get(k, 0.0)) - delta * 3.0)
		for k in _int_flash.keys():
			_int_flash[k] = maxf(0.0, float(_int_flash[k]) - delta * 2.5)
	if monster_id != "":
		var m := sim.unit(monster_id)
		if not m.is_empty():
			var mf := clampf(float(m.hp) / maxf(1.0, float(m.max_hp)), 0.0, 1.0)
			if _ghost < mf:
				_ghost = mf
			else:
				_ghost = maxf(mf, _ghost - delta * 0.12)


func _draw() -> void:
	paint(Paint.new(get_canvas_item(), font), get_viewport_rect().size)


## Paint the whole HUD for a screen `size` (the self-test calls this with a
## scratch canvas item). False when there is nothing to paint.
func paint(pt: Paint, size: Vector2) -> bool:
	if sim == null:
		return false
	var p := sim.unit(player_id)
	if p.is_empty():
		return false
	var L := layout(size)
	var weapon := str(p.weapon)
	plate(pt, L.plate)
	_orb(pt, L.orb.c, float(L.orb.r), p)
	# Q W E R
	var skills := HHWeapons.skills(weapon)
	var el := HHLook.element_color(str(p.element))
	var cooldowns: Dictionary = p.cooldowns
	for k in KEYS:
		var sk: Dictionary = skills.get(k, {})
		var cd := int(cooldowns.get(k, 0))
		var total := maxf(1.0, float(sk.get("cooldown", 1)))
		var frac := clampf(float(cd) / total, 0.0, 1.0) if cd > 0 else 0.0
		var ch: Dictionary = p.get("charging", {})
		var active: bool = (k == "e" and int(p.get("guard", 0)) > 0) or (k == "q" and not ch.is_empty())
		slot(pt, L.slots[k], skill_icon(weapon, k), _skill_bg(el), k, frac, _secs(cd) if cd > 0 else "", active, float(_flash.get(k, 0.0)))
		if k == "q" and not ch.is_empty():          # H56: the held level on the Q box
			var qr: Rect2 = L.slots.q
			pt.text(qr.get_center() + Vector2(0, 10), str(int(ch.get("level", 1))), 30, Color(1, 0.95, 0.7), 1, 5, serif())
		_interrupt_flash(pt, L.slots[k], k)
	# the elements: active and backup
	var er: Rect2 = L.element
	slot(pt, er, str(p.element), HHLook.element_color(str(p.element)).darkened(0.1))
	pt.text(Vector2(er.get_center().x, er.end.y - 4.0), str(p.element).capitalize(), 11, Color(1, 1, 1, 0.92), 1, 3)
	var br: Rect2 = L.backup
	slot(pt, br, str(p.backup), HHLook.element_color(str(p.backup)).darkened(0.1), "", 0.0, "", false, 0.0, 0.42)
	pt.text(Vector2(br.get_center().x, br.position.y - 4.0), "W", 12, Color(1, 0.95, 0.85, 0.8), 1, 3, serif())
	# the potion (H40)
	var tcd := int(cooldowns.get("t", 0))
	var tf := clampf(float(tcd) / maxf(1.0, HHTune.value("potion_cd")), 0.0, 1.0) if tcd > 0 else 0.0
	var tr: Rect2 = L.potion
	slot(pt, tr, "potion", Color(0.62, 0.1, 0.14), "t", tf, _secs(tcd) if tcd > 0 else "", false, float(_flash.get("t", 0.0)),
		0.5 if int(p.get("potions", 0)) <= 0 else 0.0)
	pt.text(Vector2(tr.end.x - 4.0, tr.position.y + 15.0), "x%d" % int(p.get("potions", 0)), 14, Color(1, 0.92, 0.75), 2, 3, serif())
	_interrupt_flash(pt, tr, "t")
	# healing multiplier over the orb (H56: while standing in a heal zone)
	if not (p.get("regen", {}) as Dictionary).is_empty() or sim.in_heal_zone(p):
		var hm := sim.heal_mult(p)
		var oc: Vector2 = L.orb.c
		pt.text(Vector2(oc.x, oc.y - ORB_R - 24.0), "healing x%.1f" % hm, 14, Color(0.5, 1.0, 0.6) if hm >= 1.0 else Color(1.0, 0.5, 0.5), 1, 3)
	# statuses: icons in a row above the skills, longest first
	var ix: float = (L.status as Vector2).x
	for row in status_rows(p):
		_status_icon(pt, Rect2(Vector2(ix, (L.status as Vector2).y), Vector2(ICON, ICON)), str(row.name), float(row.seconds))
		ix += ICON + ICON_GAP
	_monster_plate(pt, L.monster)
	if party.size() > 1:
		for pl in plates:
			nameplate(pt, pl.pos, sim.unit(str(pl.id)), _party_name(str(pl.id)), str(pl.id), float(revive.get(str(pl.id), 0.0)), str(pl.id) == player_id, gone.has(str(pl.id)))
		party_frames(pt, size)
		if bool(p.get("downed", false)) and sim.over == "":
			_down_banner(pt, size)
	if sim.over != "":
		_banner(pt, size, "VICTORY" if sim.over == "win" else "FALLEN", sim.over == "win")
	return true


## The skills wear the active element (W recolours the whole bar).
static func _skill_bg(el: Color) -> Color:
	return el.darkened(0.18).lerp(Color(0.2, 0.18, 0.16), 0.22)


static func _secs(cd: int) -> String:
	var s := float(cd) / 30.0
	return ("%.1f" % s) if s < 10.0 else ("%d" % int(ceil(s)))


## H58: a cancelled skill's box flashes red for a moment (`interrupted`).
var _int_flash := {}


func interrupted(skill: String) -> void:
	if skill == "basic" or skill == "":
		return
	_int_flash[skill] = 1.0


func _interrupt_flash(pt: Paint, r: Rect2, key: String) -> void:
	var f := float(_int_flash.get(key, 0.0))
	if f <= 0.0:
		return
	pt.rect(r, Color(0.9, 0.12, 0.08, 0.5 * f))
	pt.frame(r.grow(2.0), Color(1.0, 0.3, 0.2, f), 2.0)


## H56: the dash pips sit in the orb's crown arc (H19's reserved stamina
## track; H57: "a bar showing dashes is enough stamina"): one segment per
## charge, full when banked, the recharging one filling.
static func dash_fill(p: Dictionary) -> Array:
	var cap := int(HHTune.value("dash_charges"))
	var have := int(p.get("dash_charges", cap))
	var full_t := maxf(1.0, HHTune.value("dash_recharge_s") * 30.0)
	var out: Array = []
	for i in cap:
		if i < have:
			out.append(1.0)
		elif i == have:
			out.append(clampf(1.0 - float(p.get("dash_recharge", 0)) / full_t, 0.0, 1.0))
		else:
			out.append(0.0)
	return out


## The glass HP orb: socket, liquid with a moving surface, glass highlight,
## the dash pips in the arc over its crown (H19's track, H56), the number.
func _orb(pt: Paint, c: Vector2, r: float, p: Dictionary) -> void:
	var frac := clampf(float(p.hp) / maxf(1.0, float(p.max_hp)), 0.0, 1.0)
	# the track (H19) now holds the dash charges (H56)
	pt.arc(c, r + 14.0, -PI * 0.8, -PI * 0.2, Color(0, 0, 0, 0.8), 8.0)
	var fills := dash_fill(p)
	var span := PI * 0.6 / maxf(1.0, float(fills.size()))
	for i in fills.size():
		var a0 := -PI * 0.8 + span * i + 0.03
		var a1 := a0 + span - 0.06
		var fv := float(fills[i])
		if fv >= 1.0:
			pt.arc(c, r + 14.0, a0, a1, Color(0.62, 0.9, 1.0, 0.95), 6.0)
		elif fv > 0.0:
			pt.arc(c, r + 14.0, a0, a0 + (a1 - a0) * fv, Color(0.4, 0.55, 0.65, 0.8), 4.0)
	pt.arc(c, r + 10.5, -PI * 0.8, -PI * 0.2, Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 1.5)
	pt.arc(c, r + 17.5, -PI * 0.8, -PI * 0.2, Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 1.5)
	for a in [-PI * 0.8, -PI * 0.2]:
		var q := c + Vector2(cos(a), sin(a)) * (r + 14.0)
		pt.poly(PackedVector2Array([q + Vector2(0, -5), q + Vector2(5, 0), q + Vector2(0, 5), q + Vector2(-5, 0)]), GOLD)
	socket(pt, c, r + 6.0)
	pt.circle(c, r, Color(0.1, 0.02, 0.025))
	if frac > 0.0:
		var level := c.y + r - 2.0 * r * frac
		var pts := PackedVector2Array()
		if frac >= 0.995:
			pts = circle_pts(c, r, 48)
		else:
			var dy := level - c.y
			var hw := sqrt(maxf(0.0, r * r - dy * dy))
			var n := 18
			for i in n + 1:
				var u := float(i) / float(n)
				var x := c.x - hw + 2.0 * hw * u
				pts.append(Vector2(x, level + sin(u * TAU * 1.5 + _t * 3.0) * 2.2 * sin(u * PI)))
			var ar := asin(clampf(dy / r, -1.0, 1.0))
			var arc := circle_pts(c, r, 28, ar, PI - ar, true)
			for i in range(1, arc.size() - 1):
				pts.append(arc[i])
		var cols := PackedColorArray()
		var top := Color(0.95, 0.22, 0.14)
		var bot := Color(0.38, 0.02, 0.03)
		for q in pts:
			cols.append(top.lerp(bot, clampf((q.y - (c.y - r)) / (2.0 * r), 0.0, 1.0)))
		pt.poly_colors(pts, cols)
		if frac < 0.995:                            # a bright meniscus
			var dy2 := level - c.y
			var hw2 := sqrt(maxf(0.0, r * r - dy2 * dy2))
			var line_pts := PackedVector2Array()
			for i in 13:
				var u := float(i) / 12.0
				line_pts.append(Vector2(c.x - hw2 + 2.0 * hw2 * u, level + sin(u * TAU * 1.5 + _t * 3.0) * 2.2 * sin(u * PI)))
			pt.polyline(line_pts, Color(1.0, 0.6, 0.45, 0.6), 1.5)
	# glass: a highlight cap and a rim glint
	var hl := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		hl.append(c + Vector2(-0.22 * r, -0.46 * r) + Vector2(cos(a) * 0.5 * r, sin(a) * 0.24 * r).rotated(-0.35))
	pt.poly(hl, Color(1, 1, 1, 0.16))
	pt.circle(c + Vector2(-0.42 * r, -0.5 * r), r * 0.08, Color(1, 1, 1, 0.45))
	pt.arc(c, r - 3.0, PI * 0.15, PI * 0.55, Color(1, 0.8, 0.7, 0.22), 2.0)
	pt.ring(c, r, Color(0, 0, 0, 0.9), 2.0)
	pt.text(c + Vector2(0, 8), "%d" % int(p.hp), 24, Color(1, 0.97, 0.92), 1, 4, serif())


## A status icon: a framed tile in the status colour, its glyph, the
## seconds left in the corner.
func _status_icon(pt: Paint, r: Rect2, name: String, seconds: float) -> void:
	var row: Dictionary = STATUS.get(name, { "glyph": name.substr(0, 1).to_upper(), "icon": "", "color": Color(0.7, 0.7, 0.7), "label": name })
	var col: Color = row.color
	pt.rect(r.grow(1.5), Color(0, 0, 0, 0.9))
	pt.vgrad(r, col.darkened(0.35), col.darkened(0.75))
	if not glyph(pt, str(row.get("icon", "")), r.grow(-4.0), col.lightened(0.55)):
		pt.text(r.get_center() + Vector2(0, 7), str(row.glyph), 18, col.lightened(0.4), 1)
	pt.frame(r, col.lightened(0.2), 1.0)
	var s := ("%.1f" % seconds) if seconds < 10.0 else ("%d" % int(ceil(seconds)))
	pt.text(Vector2(r.end.x + 2.0, r.end.y + 2.0), s, 12, Color.WHITE, 2, 4, serif())


## The top plate: portrait socket, name, HP bar with a ghost of recent
## damage and quarter ticks, the state socket on the right.
func _monster_plate(pt: Paint, bar: Rect2) -> void:
	if monster_id == "":
		return
	var m := sim.unit(monster_id)
	if m.is_empty():
		return
	var mf := clampf(float(m.hp) / maxf(1.0, float(m.max_hp)), 0.0, 1.0)
	var ghost := maxf(mf, _ghost)
	var plate_r := Rect2(bar.position.x - 18.0, 8.0, bar.size.x + 36.0, bar.end.y + 9.0 - 8.0)
	plate(pt, plate_r, false, true, 0.92)
	# name
	var title := HHRegistry.name_of("monster", monster_id).to_upper()
	pt.text(Vector2(bar.get_center().x, bar.position.y - 7.0), title, 19, Color(1.0, 0.93, 0.8), 1, 4, serif())
	# bar
	pt.rect(bar.grow(2.0), Color(0, 0, 0, 0.9))
	pt.rect(bar, Color(0.12, 0.05, 0.04))
	if ghost > mf:
		pt.rect(Rect2(bar.position.x + bar.size.x * mf, bar.position.y, bar.size.x * (ghost - mf), bar.size.y), Color(1.0, 0.78, 0.45, 0.85))
	var untarget := bool(m.get("untargetable", false))
	var fill := Rect2(bar.position, Vector2(bar.size.x * mf, bar.size.y))
	if untarget:
		pt.vgrad(fill, Color(0.55, 0.58, 0.68), Color(0.25, 0.27, 0.35))
	else:
		pt.vgrad(fill, Color(0.92, 0.26, 0.17), Color(0.45, 0.05, 0.04))
	pt.rect(Rect2(fill.position, Vector2(fill.size.x, bar.size.y * 0.35)), Color(1, 1, 1, 0.13))
	for q in [0.25, 0.5, 0.75]:
		var x: float = bar.position.x + bar.size.x * q
		pt.line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.55), 1.0)
	pt.frame(bar, GOLD_DIM, 1.0)
	pt.text(Vector2(bar.get_center().x, bar.end.y - 3.0), "%d / %d" % [int(m.hp), int(m.max_hp)], 12, Color(1, 1, 1, 0.92), 1, 3)
	pt.text(Vector2(bar.end.x, bar.position.y - 8.0), tier_tag(sim), 12, Color(GOLD.r, GOLD.g, GOLD.b, 0.7), 2, 3, serif())   # H243: the tier, small, right of the name
	if int(m.get("exposed", 0)) > 0:                # H57: the punish window
		var pulse := 0.7 + 0.3 * sin(_t * 12.0)
		var tag := Rect2(bar.end.x - 92.0, bar.end.y + 5.0, 92.0, 20.0)
		pt.rect(tag.grow(1.0), Color(0, 0, 0, 0.85))
		pt.rect(tag, Color(0.55, 0.38, 0.08, 0.9 * pulse))
		pt.frame(tag, Color(1.0, 0.86, 0.45, pulse), 1.0)
		pt.text(Vector2(tag.get_center().x, tag.end.y - 4.0), "EXPOSED", 14, Color(1.0, 0.95, 0.75), 1, 3, serif())
		pt.frame(bar.grow(3.0), Color(1.0, 0.82, 0.35, 0.8 * pulse), 2.0)
	# portrait
	var pc := Vector2(plate_r.position.x - 4.0, plate_r.get_center().y + 2.0)
	socket(pt, pc, 30.0)
	thumb_disc(pt, thumb("monster", monster_id), pc, 26.0, 0.9)
	pt.ring(pc, 26.0, Color(0, 0, 0, 0.7), 2.0)
	# state socket
	var ms := ""
	if monster_body != null and is_instance_valid(monster_body) and monster_body.get("state_name") != null:
		ms = str(monster_body.get("state_name"))
	if ms == "":
		ms = monster_state_of(m)
	var sc := Vector2(plate_r.end.x + 4.0, plate_r.get_center().y + 2.0)
	if ms != "":
		var row: Dictionary = MONSTER_STATE.get(ms, { "glyph": "?", "icon": "", "color": Color(0.7, 0.7, 0.7), "label": ms })
		var col: Color = row.color
		var pulse := 0.75 + 0.25 * sin(_t * 6.0)
		socket(pt, sc, 20.0, col * pulse)
		pt.circle(sc, 16.0, col.darkened(0.55))
		if not glyph(pt, str(row.get("icon", "")), Rect2(sc - Vector2(12, 12), Vector2(24, 24)), col.lightened(0.5)):
			pt.text(sc + Vector2(0, 6), str(row.glyph), 16, col.lightened(0.4), 1)
		pt.text(Vector2(sc.x + 27.0, sc.y + 6.0), str(row.label).to_upper(), 15, col.lightened(0.6), 0, 5, serif())
	else:                                           # no state: the socket holds a dim ornament
		socket(pt, sc, 20.0, GOLD_DIM)
		pt.poly(_scaled(_star(Vector2(0.5, 0.5), 0.5, 0.18, 4), sc - Vector2(10, 10), 20.0), Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.8))


## The fight's tier under the monster bar, small and dim (H243): "EASY" / "NORMAL".
static func tier_tag(s: HHSim) -> String:
	return str(s.difficulty).to_upper() if s != null else ""


## The end banner: a band across the screen, gold rules fading to the edges.
static func _banner(pt: Paint, size: Vector2, text: String, won: bool) -> void:
	var y := size.y * 0.36
	var h := 96.0
	var band := Rect2(0, y - h * 0.5, size.x, h)
	var cx := size.x * 0.5
	var clear := Color(0, 0, 0, 0)
	var dark := Color(0.03, 0.025, 0.02, 0.82)
	for half in [[band.position.x, cx], [cx, band.end.x]]:
		var x0: float = half[0]
		var x1: float = half[1]
		var c0 := clear if x0 == band.position.x else dark
		var c1 := dark if x0 == band.position.x else clear
		pt.poly_colors(PackedVector2Array([Vector2(x0, band.position.y), Vector2(x1, band.position.y), Vector2(x1, band.end.y), Vector2(x0, band.end.y)]),
			PackedColorArray([c0, c1, c1, c0]))
		var g0 := Color(GOLD.r, GOLD.g, GOLD.b, 0.0 if x0 == band.position.x else 0.9)
		var g1 := Color(GOLD.r, GOLD.g, GOLD.b, 0.9 if x0 == band.position.x else 0.0)
		for yy in [band.position.y, band.end.y]:
			pt.poly_colors(PackedVector2Array([Vector2(x0, yy - 1), Vector2(x1, yy - 1), Vector2(x1, yy + 1), Vector2(x0, yy + 1)]),
				PackedColorArray([g0, g1, g1, g0]))
	var col := Color(1.0, 0.86, 0.45) if won else Color(0.92, 0.3, 0.26)
	pt.text(Vector2(cx, y + 24.0), text, 68, col, 1, 8, serif(), Color(0.05, 0.02, 0.0, 0.95))


# ------------------------------------------------------------------ co-op (Lane C, H903-H906)

const FRAME_SIZE := Vector2(232, 50)
const FRAME_GAP := 8.0
const PLATE_W := 96.0
const DOWN_RED := Color(0.95, 0.32, 0.26)


## Where the party frames sit (pure): one Rect2 per member, a column at the
## left a third of the way down, clear of the F3 read-out's first lines.
static func party_layout(size: Vector2, n: int) -> Array:
	var out: Array = []
	var y0 := maxf(150.0, size.y * 0.3)
	for i in n:
		out.append(Rect2(Vector2(16.0, y0 + i * (FRAME_SIZE.y + FRAME_GAP)), FRAME_SIZE))
	return out


func _party_name(id: String) -> String:
	for m in party:
		if str(m.id) == id:
			return str(m.name)
	return id


## The party frames: a plate per hunter with its slot colour on the left
## edge, the name (YOU tag for this machine's), an HP bar, and when downed
## a red DOWN with the revive bar filling under it.
func party_frames(pt: Paint, size: Vector2) -> void:
	var rects := party_layout(size, party.size())
	for i in party.size():
		var id := str(party[i].id)
		var u := sim.unit(id)
		var r: Rect2 = rects[i]
		var col := HHParty.slot_color(id)
		var down := bool(u.get("downed", false))
		var dead := not down and not u.is_empty() and float(u.hp) <= 0.0
		plate(pt, r, false, false, 0.88)
		pt.rect(Rect2(r.position + Vector2(0, 3), Vector2(4, r.size.y - 6)), col)
		if id == player_id:
			pt.frame(r.grow(-1.0), Color(col.r, col.g, col.b, 0.55), 1.0)
		var name_col := Color(1, 0.95, 0.85) if not (down or dead or gone.has(id)) else Color(1, 0.95, 0.85, 0.55)
		pt.text(Vector2(r.position.x + 14, r.position.y + 19), str(party[i].name), 16, name_col, 0, 3, serif())
		var tag := "YOU" if id == player_id else ("DISCONNECTED" if gone.has(id) else id.to_upper())
		pt.text(Vector2(r.end.x - 10, r.position.y + 17), tag, 11, Color(col.r, col.g, col.b, 0.9), 2, 3)
		var bar := Rect2(r.position.x + 14, r.position.y + 28, r.size.x - 28, 9)
		var frac := clampf(float(u.get("hp", 0.0)) / maxf(1.0, float(u.get("max_hp", 1.0))), 0.0, 1.0)
		pt.rect(bar.grow(1.5), Color(0, 0, 0, 0.9))
		pt.rect(bar, Color(0.1, 0.05, 0.04))
		if down:
			var rf := clampf(float(revive.get(id, 0.0)), 0.0, 1.0)
			pt.rect(Rect2(bar.position, Vector2(bar.size.x * rf, bar.size.y)), col.lightened(0.15))
			pt.text(Vector2(bar.get_center().x, bar.end.y - 0.5), "DOWN" if rf <= 0.0 else "REVIVING %d%%" % int(rf * 100.0), 11, DOWN_RED.lightened(0.3) if rf <= 0.0 else Color.WHITE, 1, 3)
		else:
			pt.vgrad(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.4, 0.88, 0.42), Color(0.12, 0.45, 0.14))
			pt.text(Vector2(bar.end.x, r.end.y - 3), "%d" % int(u.get("hp", 0.0)), 10, Color(1, 1, 1, 0.7), 2, 2)
		pt.frame(bar, GOLD_DIM, 1.0)


## A hunter's nameplate over its head: the name in its slot colour over a
## small HP bar; a downed hunter's bar becomes the revive bar with a DOWN
## tag. The local hunter's plate is smaller and has no name (the HUD's orb says it all).
static func nameplate(pt: Paint, at: Vector2, u: Dictionary, name: String, id: String, revive_frac: float, mine: bool, left: bool = false) -> void:
	if u.is_empty():
		return
	var col := HHParty.slot_color(id)
	var down := bool(u.get("downed", false))
	var w := PLATE_W * (0.7 if mine else 1.0)
	var bar := Rect2(at.x - w * 0.5, at.y, w, 6.0)
	if not mine:
		pt.text(Vector2(at.x, at.y - 5.0), name, 15, col.lightened(0.2), 1, 4, serif())
	pt.rect(bar.grow(1.5), Color(0, 0, 0, 0.85))
	if down:
		pt.rect(bar, Color(0.18, 0.04, 0.03))
		pt.rect(Rect2(bar.position, Vector2(bar.size.x * clampf(revive_frac, 0.0, 1.0), bar.size.y)), col.lightened(0.2))
		pt.text(Vector2(at.x, bar.end.y + 15.0), "DOWN" if revive_frac <= 0.0 else "REVIVING", 13, DOWN_RED.lightened(0.25) if revive_frac <= 0.0 else Color.WHITE, 1, 4, serif())
	else:
		var frac := clampf(float(u.get("hp", 0.0)) / maxf(1.0, float(u.get("max_hp", 1.0))), 0.0, 1.0)
		pt.rect(bar, Color(0.12, 0.05, 0.04))
		pt.rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.42, 0.9, 0.44))
	pt.line(Vector2(bar.position.x, bar.position.y - 1.5), Vector2(bar.end.x, bar.position.y - 1.5), Color(col.r, col.g, col.b, 0.9), 1.0)
	if left:
		pt.text(Vector2(at.x, bar.end.y + (30.0 if down else 15.0)), "DISCONNECTED", 12, Color(0.75, 0.75, 0.78), 1, 4, serif())


## The local hunter is down: a band over the lower middle of the screen
## with the line the brief asks for, and who the camera now follows.
func _down_banner(pt: Paint, size: Vector2) -> void:
	var y := size.y - 186.0                     # above the action bar, below the hunters
	var band := Rect2(size.x * 0.5 - 270.0, y - 30.0, 540.0, 60.0)
	plate(pt, band, true, true, 0.85)
	pt.text(Vector2(size.x * 0.5, y + 4.0), "DOWN, an ally can revive you", 26, DOWN_RED.lightened(0.15), 1, 5, serif())
	var rf := clampf(float(revive.get(player_id, 0.0)), 0.0, 1.0)
	var sub := ("being revived: %d%%" % int(rf * 100.0)) if rf > 0.0 else (("watching %s" % _party_name(spectating)) if spectating != "" else "")
	if sub != "":
		pt.text(Vector2(size.x * 0.5, y + 24.0), sub, 14, Color(1, 0.95, 0.85, 0.85), 1, 3)
