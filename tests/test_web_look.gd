extends RefCounted
## Lane Z (H90-H92): the web build's (gl_compatibility) GK shader variants
## stay in step with their desktop originals, and desktop never picks them.

const PAIRS := [
	["res://shaders/gk_surface.gdshader", "res://shaders/gk_surface_web.gdshader"],
	["res://shaders/gk_surface_clear.gdshader", "res://shaders/gk_surface_clear_web.gdshader"],
	["res://src/arena/shaders/gk_fade.gdshader", "res://src/arena/shaders/gk_fade_web.gdshader"],
]


## The variant is its original plus exactly: a two-line header, ", ambient_light_disabled"
## on the render_mode, the gk_web_light include and the hh_web_dist line in fragment().
## When this fails, re-copy the original and add those four things back.
static func strip_web(src: String) -> String:
	var lines := src.replace("\r\n", "\n").split("\n")
	var out: PackedStringArray = []
	for i in lines.size():
		var l: String = lines[i]
		if i < 2 and l.begins_with("// Lane Z (H90)") or (i < 2 and l.begins_with("// identical but for its lighting")):
			continue
		if l == "#include \"res://shaders/gk_web_light.gdshaderinc\"" or l == "\thh_web_dist = length(VERTEX);":
			continue
		out.append(l.replace(", ambient_light_disabled;", ";"))
	return "\n".join(out)


func test_variants_match_originals(c: HHSelfTest.HHCheck) -> void:
	for p in PAIRS:
		var orig := FileAccess.get_file_as_string(p[0]).replace("\r\n", "\n")
		var web := FileAccess.get_file_as_string(p[1])
		c.ok(web.contains("ambient_light_disabled") and web.contains("gk_web_light.gdshaderinc"), "%s sums ambient in the sun's pass" % p[1].get_file())
		c.ok(strip_web(web) == orig, "%s matches %s but for its lighting" % [p[1].get_file(), p[0].get_file()])


func test_desktop_keeps_originals(c: HHSelfTest.HHCheck) -> void:
	c.ok(not HHWebLook.active(), "the self-test does not run on the Compatibility renderer")
	var m := GKMaterials.get_material("grass")
	c.ok(m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path == GKMaterials.SHADER, "desktop GK surfaces keep gk_surface")
	c.ok(GKMaterials._variant(GKMaterials.SHADER, true) == "res://shaders/gk_surface_web.gdshader", "the web picks gk_surface_web")
	c.ok(GKMaterials._variant(GKMaterials.SHADER_FADE, true).ends_with("gk_fade_web.gdshader"), "... and gk_fade_web")
	c.ok(GKMaterials._variant(GKMaterials.SHADER, false) == GKMaterials.SHADER, "desktop never does")
	for k in ["web_ambient", "web_reflection", "web_fog", "web_glow_whiten", "web_glow_gain"]:
		c.ok(HHTune.has(k), "tune has %s" % k)
