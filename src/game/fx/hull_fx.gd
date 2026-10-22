class_name HHHullFx
extends Node3D
## Lane H (H250-H259): the monster's hull and its Attack Ring on the ground,
## drawn from sim state each frame (view only, never writes the sim).
##   hull         one thick connected border round every hex the body holds
##                (radius `size` round its hex: 19 hexes at radius 2), an ink
##                band with a bone rim outside it, in the comic-ink language of
##                the bodies. Shown while the monster stands or walks; hidden
##                in the air (a leap) and under water (submerged Swampfang)
##   attack ring  when it matters to the LOCAL hunter: the cursor is on the
##                monster (an attack click would walk there), or the hunter is
##                walking in to attack it. The Attack Ring hexes (18 at radius 2) glow
##                faintly gold, the outer edge of the weapon's reach band
##                (lance 2, bow 7 beyond the hull) is a thin gold line, and
##                the spot the click resolves to (HHSim.attack_spot) is lit
##   push-out     a dust scuff along the slide (`push_out` events)
## `hover_id` is set by the fight every frame (the monster under the cursor).

const LIFT := 0.12
const HEX_R := 1.0
const HULL_W := 0.28                  # the ink band reaches this far inside the border ... (H279: 0.24 -> 0.28, "a tinge" thicker)
const INK_OUT := 0.16                 # ... and this far outside it (0.14 -> 0.16)
const RIM_W := 0.12                   # the bone rim, outside the ink (0.11 -> 0.12)
const INK := Color(0.07, 0.05, 0.06, 0.82)
const RIM := Color(0.95, 0.9, 0.78, 0.9)
const GOLD := Color(1.0, 0.86, 0.42)

var arena: HHArena
var enabled := true
var hover_id := ""
var _hulls := {}                       # monster id -> { ink, rim, key }
var _ring_line: MeshInstance3D
var _ring_key := ""
var _ring_tiles: Array = []            # pooled hex tiles for the Attack Ring
var _spot: MeshInstance3D
var _ink_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _tile_mat: StandardMaterial3D
var _spot_mat: StandardMaterial3D
var motes: HHFxParticles
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _ring_alpha := 0.0
var _spot_key := ""
var _spot_hex := HHSim.NO_HEX


func setup(a: HHArena) -> void:
	arena = a
	_rng.seed = 2503
	_ink_mat = _line_mat(INK, 3)
	_rim_mat = _line_mat(RIM, 4)
	_ring_mat = _line_mat(Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 4)
	_tile_mat = HHLook.flat(Color(GOLD.r, GOLD.g, GOLD.b, 0.2), true)
	_tile_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tile_mat.render_priority = 1
	_spot_mat = HHLook.flat(Color(1.0, 0.95, 0.7, 0.55), true)
	_spot_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spot_mat.render_priority = 2
	_ring_line = _mesh_node()
	_spot = MeshInstance3D.new()
	_spot.mesh = HHTileFX.hex_mesh()
	_spot.material_override = _spot_mat
	_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spot.visible = false
	add_child(_spot)
	motes = HHFxParticles.new(120, true)
	add_child(motes)


func _mesh_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _line_mat(c: Color, prio: int) -> StandardMaterial3D:
	var m := HHLook.flat(c, true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = prio
	return m


## A band along `edges` (HHAimFx.boundary), inset toward each hex centre from
## `from_w` to `to_w`, following the ground (water: the surface).
func _band(mi: MeshInstance3D, edges: Array, from_w: float, to_w: float, mat: Material, lift: float) -> void:
	var im: ImmediateMesh = mi.mesh
	im.clear_surfaces()
	if edges.is_empty():
		mi.visible = false
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var c: Vector3 = e[2]
		var floor_y := arena.surface(HHHex.from_world(Vector2(c.x, c.z))).y
		var pts: Array = []
		for p in [a + (c - a).normalized() * from_w, b + (c - b).normalized() * from_w,
				b + (c - b).normalized() * to_w, a + (c - a).normalized() * to_w]:
			pts.append(Vector3(p.x, maxf(arena.height_at(p.x, p.z), floor_y) + lift, p.z))
		im.surface_add_vertex(pts[0])
		im.surface_add_vertex(pts[1])
		im.surface_add_vertex(pts[2])
		im.surface_add_vertex(pts[0])
		im.surface_add_vertex(pts[2])
		im.surface_add_vertex(pts[3])
	im.surface_end()
	mi.visible = true


func sync(sim: HHSim, player_id: String, delta: float) -> void:
	if not enabled or sim == null or arena == null:
		return
	_t += delta
	_sync_hulls(sim)
	_sync_ring(sim, sim.unit(player_id), delta)
	motes.step(delta)


func _sync_hulls(sim: HHSim) -> void:
	var seen := {}
	for m in sim.monsters():
		var id := str(m.id)
		var show := sim.alive(m) and (m.leap as Dictionary).is_empty() and not bool(m.untargetable)
		var node: Dictionary = _hulls.get(id, {})
		if node.is_empty():
			node = { "ink": _mesh_node(), "rim": _mesh_node(), "key": "" }
			_hulls[id] = node
		if not show:
			(node.ink as MeshInstance3D).visible = false
			(node.rim as MeshInstance3D).visible = false
			continue
		seen[id] = true
		var key := "%s:%d" % [m.hex, int(m.size)]
		if key != str(node.key):
			node.key = key
			var edges := HHAimFx.boundary(HHHex.area(m.hex, int(m.size)))
			_band(node.ink, edges, -INK_OUT, HULL_W, _ink_mat, LIFT)                   # straddles the border, mostly inside
			_band(node.rim, edges, -INK_OUT - RIM_W, -INK_OUT, _rim_mat, LIFT + 0.005)  # a bone rim just outside it
		(node.ink as MeshInstance3D).visible = true
		(node.rim as MeshInstance3D).visible = true


## The monster the local hunter is about to hit or is walking in to hit.
func ring_monster(sim: HHSim, me: Dictionary) -> Dictionary:
	if me.is_empty() or not sim.alive(me):
		return {}
	var want := hover_id
	if want == "" and str(me.target) != "" and bool(me.attacking):
		var t := sim.unit(str(me.target))
		if not t.is_empty() and not sim.in_attack_range(me, t):
			want = str(me.target)                           # approaching: show where it is going
	var m := sim.unit(want)
	if m.is_empty() or not sim.targetable(m) or not (m.leap as Dictionary).is_empty():
		return {}
	return m


func _sync_ring(sim: HHSim, me: Dictionary, delta: float) -> void:
	var m := ring_monster(sim, me)
	_ring_alpha = move_toward(_ring_alpha, 1.0 if not m.is_empty() else 0.0, delta * 6.0)
	if m.is_empty():
		if _ring_alpha <= 0.0:
			_hide_ring()
		_set_ring_alpha()
		return
	var reach := int(me.reach)
	var size := int(m.size)
	var sk := "%s:%s:%s:%d" % [me.hex, m.hex, str(me.weapon), sim.players().size()]
	if sk != _spot_key:                                 # a BFS: only when someone moved a hex
		_spot_key = sk
		_spot_hex = sim.attack_spot(me, m).hex
	var at: Vector2i = _spot_hex
	var key := "%s:%d:%d" % [m.hex, size, reach]
	if key != _ring_key:
		_ring_key = key
		var band: Array = []                                # every hex in reach of the hull's edge
		for h in HHHex.area(m.hex, size + reach):
			if HHHex.distance(h, m.hex) > size:
				band.append(h)
		_band(_ring_line, HHAimFx.boundary(band), 0.0, 0.09, _ring_mat, LIFT + 0.01)
		var ring := sim.attack_ring(m)
		var n := 0
		for h in ring:
			if not arena.walkable(h):
				continue
			var mi: MeshInstance3D
			if n < _ring_tiles.size():
				mi = _ring_tiles[n]
			else:
				mi = MeshInstance3D.new()
				mi.mesh = HHTileFX.hex_mesh()
				mi.material_override = _tile_mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				_ring_tiles.append(mi)
			mi.position = arena.surface(h) + Vector3(0, LIFT - 0.03, 0)
			mi.scale = Vector3.ONE * 0.9
			mi.visible = true
			n += 1
		for i in range(n, _ring_tiles.size()):
			(_ring_tiles[i] as MeshInstance3D).visible = false
	_ring_line.visible = true
	if at != HHSim.NO_HEX:
		var pulse := 0.5 + 0.5 * sin(_t * 7.0)
		_spot.position = arena.surface(at) + Vector3(0, LIFT - 0.01, 0)
		_spot.scale = Vector3.ONE * (0.8 + 0.08 * pulse)
		_spot.visible = true
	else:
		_spot.visible = false
	_set_ring_alpha()


func _set_ring_alpha() -> void:
	var a := _ring_alpha * HHTune.value("attack_ring_alpha")   # H438: "a little too bright"
	_tile_mat.albedo_color.a = 0.2 * a
	_ring_mat.albedo_color.a = 0.8 * a
	_spot_mat.albedo_color.a = (0.4 + 0.2 * sin(_t * 7.0)) * a


func _hide_ring() -> void:
	_ring_key = ""
	_ring_line.visible = false
	_spot.visible = false
	for mi in _ring_tiles:
		(mi as MeshInstance3D).visible = false


## A dust scuff along a push-out slide.
func on_event(e: Dictionary, _sim: HHSim) -> void:
	if not enabled or str(e.get("type", "")) != "push_out":
		return
	var a: Vector3 = e.get("from_pos", Vector3.ZERO)
	var b: Vector3 = e.get("to_pos", a)
	for i in 14:
		var t := float(i) / 13.0
		var p := a.lerp(b, t) + Vector3(_rng.randf_range(-0.25, 0.25), 0.08, _rng.randf_range(-0.25, 0.25))
		motes.spawn({ "pos": p, "vel": Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.3, 0.9), _rng.randf_range(-0.4, 0.4)),
			"life": _rng.randf_range(0.35, 0.6), "size": 0.2, "size_end": 0.05, "color": Color(0.78, 0.7, 0.58, 0.7),
			"color_end": Color(0.7, 0.65, 0.55, 0.0), "shape": HHFxParticles.DOT })
