class_name HHHunterMark
extends Node3D
## The ground mark under a hunter in a party fight (H902, H905): a ring in
## the slot colour under the feet, and while the hunter is downed a wider
## revive ring: a dim full circle with a bright arc that fills clockwise
## from the front as an ally revives (`set_revive(frac)`). Unshaded, drawn
## over the water like the hunt's pulse rings.

const FOOT_R := 0.62
const REVIVE_R := 1.45
const REVIVE_W := 0.16
const ARC_SIDES := 48

var color := Color.WHITE
var foot: MeshInstance3D
var revive_base: MeshInstance3D
var revive_arc: MeshInstance3D
var downed := false
var frac := 0.0
var _arc_mesh: ImmediateMesh
var _drawn_frac := -1.0
var _t := 0.0


func setup(p_color: Color) -> void:
	color = p_color
	foot = HHHuntKit.ring(Color(color.r, color.g, color.b, 0.85), 0.2, 36)
	foot.name = "Foot"
	foot.scale = Vector3(FOOT_R, 1.0, FOOT_R)
	foot.position.y = 0.06
	add_child(foot)
	revive_base = HHHuntKit.ring(Color(color.r, color.g, color.b, 0.22), REVIVE_W / REVIVE_R, ARC_SIDES)
	revive_base.name = "ReviveBase"
	revive_base.scale = Vector3(REVIVE_R, 1.0, REVIVE_R)
	revive_base.position.y = 0.07
	revive_base.visible = false
	add_child(revive_base)
	_arc_mesh = ImmediateMesh.new()
	revive_arc = MeshInstance3D.new()
	revive_arc.name = "ReviveArc"
	revive_arc.mesh = _arc_mesh
	var m := HHLook.flat(color.lightened(0.25), true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 11
	revive_arc.material_override = m
	revive_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	revive_arc.position.y = 0.08
	revive_arc.visible = false
	add_child(revive_arc)


func set_downed(on: bool) -> void:
	downed = on
	revive_base.visible = on
	revive_arc.visible = on
	if not on:
		frac = 0.0


func set_revive(p_frac: float) -> void:
	frac = clampf(p_frac, 0.0, 1.0)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_t += delta
	if not downed:
		return
	# the base ring breathes so a downed ally reads from across the arena
	var a := 0.22 + 0.16 * (0.5 + 0.5 * sin(_t * 4.0))
	(revive_base.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, a)
	if absf(frac - _drawn_frac) > 0.004:
		_draw_arc(frac)


## The filled part of the revive ring: an annulus segment from the front (+Z) clockwise.
func _draw_arc(f: float) -> void:
	_drawn_frac = f
	_arc_mesh.clear_surfaces()
	if f <= 0.0:
		return
	var n := maxi(2, int(ceil(ARC_SIDES * f)))
	_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var r0 := REVIVE_R - REVIVE_W * 1.6
	var r1 := REVIVE_R + REVIVE_W * 0.6
	for i in n + 1:
		var a := -TAU * f * float(i) / float(n) + PI * 0.5
		var c := cos(a)
		var s := sin(a)
		_arc_mesh.surface_add_vertex(Vector3(c * r0, 0.0, s * r0))
		_arc_mesh.surface_add_vertex(Vector3(c * r1, 0.0, s * r1))
	_arc_mesh.surface_end()
