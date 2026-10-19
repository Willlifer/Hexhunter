class_name HHLook
## The visual constants: element colours (Black | White's elements.csv, hair
## and tile glow hex values), the rig scale, hex corners. One place.

const RIG_HEIGHT := 2.2

const ELEMENT_COLOR := {
	"fire": Color("#E8432E"), "water": Color("#2E6FE8"), "ice": Color("#5FD8F0"), "thunder": Color("#8B3DF0"),
	"wind": Color("#3CCB5A"), "dark": Color("#3A2A5C"), "light": Color("#F5D23A"),
}
const GLOW_COLOR := {
	"fire": Color("#FF5A1F"), "water": Color("#2E8CFF"), "ice": Color("#BFF4FF"), "thunder": Color("#9B4DFF"),
	"wind": Color("#3CDB6A"), "dark": Color("#2A1745"), "light": Color("#FFC81A"),
}
const TRUE_HEX := Color(1.0, 0.95, 0.6, 1.0)
const DEST_HEX := Color(0.6, 1.0, 0.7, 1.0)


static func element_color(element: String) -> Color:
	return ELEMENT_COLOR.get(element, Color(0.5, 0.5, 0.5))


static func glow_color(element: String) -> Color:
	return GLOW_COLOR.get(element, Color(0.6, 0.6, 0.6))


static func hex_corners(center: Vector3, r: float) -> PackedVector3Array:
	return HHHex.corners(center, r)


## An unshaded, flat material of one colour.
static func flat(c: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if transparent or c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
