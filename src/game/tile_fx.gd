class_name HHTileFX
extends RefCounted
## The painted-hex look: Black | White's procedural element shaders
## (shaders/tile_*.gdshader, carried over verbatim) and the pure mapping from
## an HHCharge entry to the layers a hex draws. Per hex: face_h / face_v (the
## axis elements' flat faces) and mark (fuse / gale / stasis marker, or the
## glaze). Instance uniform slots are the shaders' (tile_fx.gdshaderinc):
## dim 0, tier 3, seed 4, frost 5, crack 6, age 7.

const FACE := { "fire": "tile_fire", "water": "tile_water", "light": "tile_light", "dark": "tile_dark" }
## L-4 (Lane FX): the standing-card layer per element (water hugs the tile)
## and the tier above which it stands (Black | White's board_view floors:
## fire smoke from ~0.3, light motes from 1, the abyss tendrils from 2).
const CARDS := { "fire": "tile_flame", "light": "tile_beam", "dark": "tile_tendril" }
const CARD_FLOOR := { "fire": 0.3, "light": 1.0, "dark": 2.0 }
const CARD_ELEMENT := { "tile_flame": "fire", "tile_beam": "light", "tile_tendril": "dark" }
## Card cluster: [radius, angle deg, width, height scale, ring] (BWTileFX).
const CARD_LAYOUT := [
	[0.0, 0.0, 0.62, 1.2, 0],
	[0.36, 30.0, 0.5, 1.0, 1], [0.36, 150.0, 0.5, 1.0, 1], [0.36, 270.0, 0.5, 1.0, 1],
	[0.66, 0.0, 0.42, 0.8, 2], [0.66, 60.0, 0.42, 0.8, 2], [0.66, 120.0, 0.42, 0.8, 2],
	[0.66, 180.0, 0.42, 0.8, 2], [0.66, 240.0, 0.42, 0.8, 2], [0.66, 300.0, 0.42, 0.8, 2],
]
## Culling box for a card cluster (the light column is the tallest at 3.2).
const CARD_AABB := AABB(Vector3(-1.1, -0.05, -1.1), Vector3(2.2, 3.4, 2.2))
const MARKER_INK := { "fuse": Color(0.2, 0.04, 0.38), "gale": Color(0.02, 0.24, 0.08), "stasis": Color(0.04, 0.38, 0.5) }
const MARKER_MODE := { "fuse": 0, "gale": 1, "stasis": 2 }

static var _mats := {}
static var _hex_mesh: ArrayMesh
static var _card_mesh: ArrayMesh


## The layers one entry draws. Pure.
##   h / v: { el, tier } or {} ; mark: "" | "fuse" | "gale" | "stasis" | "glaze"; crack: glaze almost gone
static func layers(e: Dictionary) -> Dictionary:
	var out := { "h": {}, "v": {}, "mark": "", "crack": false, "frozen": false }
	if e.is_empty():
		return out
	if str(e.get("marker", "")) != "":
		out.mark = str(e.marker)
		return out
	var h := int(e.get("h", 0))
	var v := int(e.get("v", 0))
	if h != 0:
		out.h = { "el": "fire" if h > 0 else "water", "tier": absi(h) }
	if v != 0:
		out.v = { "el": "light" if v > 0 else "dark", "tier": absi(v) }
	var g := int(e.get("glaze", 0))
	if g > 0:
		out.mark = "glaze"
		out.crack = g <= 60
	if int(e.get("crystal", 0)) > 0:                 # H365: the ground under a crystal frosts (the prism is HHReactionFx's)
		out.frozen = true                            # ... and its charge is inert: no standing flames, beams or tendrils
		out.mark = "glaze"
		out.crack = int(e.get("crystal_t", 999)) <= 60
	return out


static func seed_for(h: Vector2i, salt: int = 0) -> float:
	return float(absi(hash(Vector3i(h.x, h.y, salt))) % 997) / 997.0


static func material(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	match kind:
		"tile_fire", "tile_water", "tile_light", "tile_dark":
			m.shader = load("res://shaders/%s.gdshader" % kind)
			m.set_shader_parameter("glow", HHLook.glow_color(kind.trim_prefix("tile_")))
		"tile_flame", "tile_beam", "tile_tendril":
			m.shader = load("res://shaders/%s.gdshader" % kind)
			m.set_shader_parameter("glow", HHLook.glow_color(str(CARD_ELEMENT[kind])))
		"fuse", "gale", "stasis":
			m.shader = load("res://shaders/tile_marker.gdshader")
			m.set_shader_parameter("mode", MARKER_MODE[kind])
			var el: String = HHCharge.MARKER_ELEMENT[kind]
			m.set_shader_parameter("glow", HHLook.element_color(el) if kind == "stasis" else HHLook.glow_color(el))
			m.set_shader_parameter("ink", MARKER_INK[kind])
		"glaze":
			m.shader = load("res://shaders/tile_glaze.gdshader")
			m.set_shader_parameter("glow", HHLook.glow_color("ice"))
			m.set_shader_parameter("ink", Color(0.04, 0.38, 0.5))
		"burst":
			m.shader = load("res://shaders/tile_burst.gdshader")
			m.set_shader_parameter("mode", 0)
			m.set_shader_parameter("glow", HHLook.glow_color("thunder"))
		_:
			push_error("HHTileFX: unknown material '%s'" % kind)
			return null
	_mats[kind] = m
	return m


## Flat pointy-top hex of circumradius 1 on XZ (the face shaders' canvas).
static func hex_mesh() -> ArrayMesh:
	if _hex_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var v := HHHex.corners(Vector3.ZERO, 1.0)
		for i in 6:
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(v[i])
			st.add_vertex(v[(i + 1) % 6])
		_hex_mesh = st.commit()
	return _hex_mesh


## L-4: the billboard card cluster (tile_cards.gdshaderinc): ten cards, all
## four corners of a card on its pivot, UV the corner, CUSTOM0 = (width,
## height scale, card seed, ring). Black | White's BWTileFX.card_mesh.
static func card_mesh() -> ArrayMesh:
	if _card_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
		var k := 0
		for c in CARD_LAYOUT:
			var a := deg_to_rad(float(c[1]))
			var pivot := Vector3(cos(a) * float(c[0]), 0.0, sin(a) * float(c[0]))
			var data := Color(float(c[2]), float(c[3]), float(k) * 0.137 + 0.05, float(c[4]))
			for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				st.set_uv(uv)
				st.set_custom(0, data)
				st.add_vertex(pivot)
			k += 1
		_card_mesh = st.commit()
	return _card_mesh
