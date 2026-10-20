class_name HHAimFx
extends Node3D
## Lane W (H56, H57): what the hunter needs to read its reach and its
## commitments, drawn on the ground from sim state each frame (view only):
##   range ring   the local hunter's basic-attack reach, a thin hex outline
##                that follows it (the "radius bar"); only the local hunter's
##   charge aim   while the local hunter holds Q: the footprint the release
##                would paint at the current level (tiles shaded by
##                strength), at the live cursor aim, plus 1/2/3 pips over
##                its head that fill as the level rises
##   charge glow  under EVERY charging hunter (co-op: the others see it too):
##                a pulsing disc in the element's colour; the lance's braced
##                charge adds a steel ring
##   heal zones   every live potion zone: a soft green outline, a faint fill,
##                motes rising
##   dash         a streak of afterimage motes from `dash` events
##   exposed      a monster in its punish window (H57): a gold glint ring
## `aim_hex` is set by the fight each frame (the local cursor); without it
## the replicated charging.aim is used.

const LIFT := 0.11
const RING_W := 0.12
const HEX_R := 1.0
const NO_HEX := Vector2i(-9999, -9999)
const ZONE_COL := Color(0.45, 1.0, 0.55)
const EXPOSED_COL := Color(1.0, 0.82, 0.35)

var arena: HHArena
var aim_hex := NO_HEX
var enabled := true
var _ring: MeshInstance3D
var _ring_key := ""
var _tiles: Array = []                 # pooled hex tiles for the charge preview
var _tile_mats := {}                   # "el:strength" -> material
var _preview: MeshInstance3D           # the preview's outline
var _preview_key := ""
var _pips: Array = []                  # three spheres
var _pip_on: StandardMaterial3D
var _pip_off: StandardMaterial3D
var _glows := {}                       # hunter id -> MeshInstance3D disc
var _zones := {}                       # owner id -> { ring, fill: Array, key }
var _zone_fill_mat: StandardMaterial3D
var _exposed := {}                     # monster id -> MeshInstance3D ring
var motes: HHFxParticles
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _mote_acc := 0.0


func setup(a: HHArena) -> void:
	arena = a
	_rng.seed = 911
	_ring = _mesh_node()
	_preview = _mesh_node()
	_pip_on = HHLook.flat(Color(1.0, 0.92, 0.55))
	_pip_off = HHLook.flat(Color(0.1, 0.09, 0.08, 0.75), true)
	for i in 3:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		sm.radial_segments = 10
		sm.rings = 5
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pips.append(mi)
	_zone_fill_mat = HHLook.flat(Color(ZONE_COL.r, ZONE_COL.g, ZONE_COL.b, 0.13), true)
	_zone_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	motes = HHFxParticles.new(220, true)
	add_child(motes)


func _mesh_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _line_mat(c: Color) -> StandardMaterial3D:
	var m := HHLook.flat(c, true)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.render_priority = 2
	return m


## The outer edges of a hex set: [[a, b], ...] in world (x, z) pairs.
static func boundary(hexes: Array) -> Array:
	var inset := {}
	for h in hexes:
		inset[h] = true
	var out: Array = []
	for h in hexes:
		var c2 := HHHex.to_world(h)
		var cs := HHHex.corners(Vector3(c2.x, 0.0, c2.y), HEX_R)
		for i in 6:
			var a: Vector3 = cs[i]
			var b: Vector3 = cs[(i + 1) % 6]
			var mid := (a + b) * 0.5
			var across := HHHex.from_world(Vector2(c2.x + (mid.x - c2.x) * 2.0, c2.y + (mid.z - c2.y) * 2.0))
			if not inset.has(across):
				out.append([a, b, Vector3(c2.x, 0.0, c2.y)])
		continue
	return out


## Draw a ribbon along `edges` into `mi`'s ImmediateMesh (each edge inset
## toward its hex centre by `w`), following the ground.
func _ribbon(mi: MeshInstance3D, edges: Array, w: float, mat: Material) -> void:
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
		var ai := a + (c - a).normalized() * w
		var bi := b + (c - b).normalized() * w
		var pts := [a, b, bi, ai]
		var ys: Array = []
		var floor_y := arena.surface(HHHex.from_world(Vector2(c.x, c.z))).y      # water and pads: the surface, not the bed
		for p in pts:
			ys.append(Vector3(p.x, maxf(arena.height_at(p.x, p.z), floor_y) + LIFT, p.z))
		im.surface_add_vertex(ys[0])
		im.surface_add_vertex(ys[1])
		im.surface_add_vertex(ys[2])
		im.surface_add_vertex(ys[0])
		im.surface_add_vertex(ys[2])
		im.surface_add_vertex(ys[3])
	im.surface_end()
	mi.visible = true


func sync(sim: HHSim, player_id: String, delta: float) -> void:
	if not enabled or sim == null or arena == null:
		return
	_t += delta
	var me := sim.unit(player_id)
	_sync_ring(sim, me)
	_sync_preview(sim, me)
	_sync_glows(sim, delta)
	_sync_zones(sim, delta)
	_sync_exposed(sim)
	motes.step(delta)


## The local hunter's basic reach (lance 2, daggers 1, bow 7 hexes).
func _sync_ring(sim: HHSim, me: Dictionary) -> void:
	if me.is_empty() or not sim.alive(me):
		_ring.visible = false
		return
	var reach := int(me.reach)
	var key := "%s:%d" % [me.hex, reach]
	if key != _ring_key:
		_ring_key = key
		var col := Color(1.0, 0.93, 0.65, 0.62) if str(me.weapon) != "daggers" else Color(1.0, 0.93, 0.65, 0.45)
		_ring.set_meta("mat", _line_mat(col))
		_ribbon(_ring, boundary(sim.arena.area(me.hex, reach)), RING_W, _ring.get_meta("mat"))


func _tile_mat(el: String, strength: int) -> StandardMaterial3D:
	var k := "%s:%d" % [el, strength]
	if not _tile_mats.has(k):
		var c := HHLook.glow_color(el)
		var m := HHLook.flat(Color(c.r, c.g, c.b, [0.0, 0.16, 0.3, 0.48][clampi(strength, 0, 3)]), true)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 1
		_tile_mats[k] = m
	return _tile_mats[k]


## While the local hunter holds Q: the release's footprint at the current
## level, and the level pips.
func _sync_preview(sim: HHSim, me: Dictionary) -> void:
	var ch: Dictionary = me.get("charging", {}) if not me.is_empty() else {}
	var n := 0
	if not ch.is_empty() and sim.alive(me):
		var level := int(ch.get("level", 1))
		var aim: Vector2i = aim_hex if aim_hex != NO_HEX else ch.get("aim", me.hex)
		var shape := HHWeapons.charge_shape(sim, me, aim, level)
		var el := str(me.element)
		for h in shape:
			var mi: MeshInstance3D
			if n < _tiles.size():
				mi = _tiles[n]
			else:
				mi = MeshInstance3D.new()
				mi.mesh = HHTileFX.hex_mesh()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				_tiles.append(mi)
			mi.material_override = _tile_mat(el, int(shape[h]))
			mi.position = sim.arena.surface(h) + Vector3(0, LIFT - 0.02, 0)
			mi.scale = Vector3.ONE * 0.9
			mi.visible = true
			n += 1
		var key := "%s:%d:%s:%s" % [aim, level, me.hex, el]
		if key != _preview_key:
			_preview_key = key
			var c := HHLook.glow_color(el)
			_ribbon(_preview, boundary(shape.keys()), 0.07, _line_mat(Color(c.r, c.g, c.b, 0.85)))
		# pips: three over the head, filled to the level; the next one swells with progress
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var right := cam.global_transform.basis.x if cam != null else Vector3.RIGHT
		var head: Vector3 = (me.pos as Vector3) + Vector3(0, HHLook.RIG_HEIGHT + 0.55, 0)
		var l2 := HHTune.value("charge_l2_s") * 30.0
		var l3 := HHTune.value("charge_l3_s") * 30.0
		var t := float(ch.get("ticks", 0))
		var prog := clampf(t / l2, 0.0, 1.0) if level == 1 else clampf((t - l2) / maxf(1.0, l3 - l2), 0.0, 1.0)
		for i in 3:
			var p: MeshInstance3D = _pips[i]
			p.visible = true
			p.position = head + right * (float(i) - 1.0) * 0.3
			var lit := i < level
			p.material_override = _pip_on if lit else _pip_off
			var s := 1.0 if lit else 0.6
			if i == level:
				s = 0.6 + 0.35 * prog
			if lit and i == level - 1:
				s *= 1.0 + 0.12 * sin(_t * 14.0)
			p.scale = Vector3.ONE * s
	else:
		_preview.visible = false
		_preview_key = ""
		for p in _pips:
			(p as MeshInstance3D).visible = false
	for i in range(n, _tiles.size()):
		(_tiles[i] as MeshInstance3D).visible = false


## Under every charging hunter: a pulsing disc in its element colour (level
## brightens it); the braced lance adds a steel rim.
func _sync_glows(sim: HHSim, _delta: float) -> void:
	var seen := {}
	for u in sim.players():
		var ch: Dictionary = u.get("charging", {})
		if ch.is_empty() or not sim.alive(u):
			continue
		var id := str(u.id)
		seen[id] = true
		var mi: MeshInstance3D = _glows.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.9
			cm.bottom_radius = 0.9
			cm.height = 0.02
			cm.radial_segments = 28
			mi.mesh = cm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := HHLook.flat(Color(1, 1, 1, 0.3), true)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mi.material_override = m
			add_child(mi)
			_glows[id] = mi
		var level := int(ch.get("level", 1))
		var c := HHLook.glow_color(str(u.element))
		if str(u.weapon) == "lance":
			c = c.lerp(Color(0.75, 0.85, 1.0), 0.35)      # braced: a steel cast
		var pulse := 0.5 + 0.5 * sin(_t * (6.0 + 3.0 * level))
		(mi.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.12 + 0.1 * level + 0.08 * pulse)
		mi.position = (u.pos as Vector3) + Vector3(0, 0.06, 0)
		mi.scale = Vector3.ONE * (0.8 + 0.25 * level + 0.06 * pulse)
		mi.visible = true
	for id in _glows:
		if not seen.has(id):
			(_glows[id] as MeshInstance3D).visible = false


## Every live potion zone: outline, faint fill, rising motes.
func _sync_zones(sim: HHSim, delta: float) -> void:
	var seen := {}
	for u in sim.players():
		var z: Dictionary = u.get("heal_zone", {})
		if z.is_empty():
			continue
		var id := str(u.id)
		seen[id] = true
		var node: Dictionary = _zones.get(id, {})
		if node.is_empty():
			node = { "ring": _mesh_node(), "fill": [], "key": "" }
			_zones[id] = node
		var hexes: Array = sim.arena.area(z.hex, int(z.radius))
		var key := "%s:%d" % [z.hex, int(z.radius)]
		var left := clampf(float(z.left) / maxf(1.0, float(z.total)), 0.0, 1.0)
		if key != str(node.key):
			node.key = key
			var mat := _line_mat(Color(ZONE_COL.r, ZONE_COL.g, ZONE_COL.b, 0.8))
			node.ring.set_meta("mat", mat)
			_ribbon(node.ring, boundary(hexes), 0.13, mat)
			for f in node.fill:
				(f as Node).queue_free()
			node.fill = []
			for h in hexes:
				var fi := MeshInstance3D.new()
				fi.mesh = HHTileFX.hex_mesh()
				fi.material_override = _zone_fill_mat
				fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				fi.position = sim.arena.surface(h) + Vector3(0, LIFT - 0.04, 0)
				fi.scale = Vector3.ONE * 0.97
				add_child(fi)
				(node.fill as Array).append(fi)
		var rm: StandardMaterial3D = node.ring.get_meta("mat")
		rm.albedo_color.a = 0.35 + 0.45 * left * (0.8 + 0.2 * sin(_t * 4.0))
		node.ring.visible = true
		for f in node.fill:
			(f as MeshInstance3D).visible = true
		_mote_acc += delta * 34.0 * (0.4 + 0.6 * left)
		while _mote_acc >= 1.0:
			_mote_acc -= 1.0
			var h: Vector2i = hexes[_rng.randi() % hexes.size()]
			var p := sim.arena.surface(h) + Vector3(_rng.randf_range(-0.5, 0.5), 0.1, _rng.randf_range(-0.5, 0.5))
			motes.spawn({ "pos": p, "vel": Vector3(0, _rng.randf_range(0.8, 1.6), 0), "life": _rng.randf_range(0.9, 1.5),
				"size": 0.09, "size_end": 0.02, "color": Color(0.6, 1.0, 0.65, 0.9), "color_end": Color(0.9, 1.0, 0.8, 0.0), "shape": HHFxParticles.DOT })
	for id in _zones.keys():
		if seen.has(id):
			continue
		var node: Dictionary = _zones[id]
		(node.ring as MeshInstance3D).queue_free()
		for f in node.fill:
			(f as Node).queue_free()
		_zones.erase(id)


## H57: a monster in its punish window wears a gold ring that glints.
func _sync_exposed(sim: HHSim) -> void:
	var seen := {}
	for m in sim.monsters():
		if int(m.get("exposed", 0)) <= 0 or not sim.alive(m):
			continue
		var id := str(m.id)
		seen[id] = true
		var mi: MeshInstance3D = _exposed.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.92
			tm.outer_radius = 1.0
			tm.rings = 40
			tm.ring_segments = 6
			mi.mesh = tm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := HHLook.flat(EXPOSED_COL, true)
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mi.material_override = mat
			add_child(mi)
			_exposed[id] = mi
		var r := (float(m.size) + 0.9) * 1.6
		var pulse := 0.5 + 0.5 * sin(_t * 12.0)
		var base: Vector3 = m.pos
		base.y = maxf(base.y, sim.arena.surface(m.hex).y)          # a swimmer: on the water, not the bed
		mi.position = base + Vector3(0, 0.45 + 0.2 * pulse, 0)
		mi.scale = Vector3(r, 1.0, r) * (1.0 + 0.05 * pulse)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(EXPOSED_COL.r, EXPOSED_COL.g, EXPOSED_COL.b, 0.55 + 0.4 * pulse)
		mi.visible = true
		if _rng.randf() < 0.35:
			var a := _rng.randf() * TAU
			motes.spawn({ "pos": (m.pos as Vector3) + Vector3(cos(a) * r, 0.4 + _rng.randf() * 2.0, sin(a) * r), "vel": Vector3(0, 0.6, 0),
				"life": 0.35, "size": 0.18, "size_end": 0.0, "color": Color(1.0, 0.95, 0.7, 1.0), "shape": HHFxParticles.SPARK })
	for id in _exposed:
		if not seen.has(id):
			(_exposed[id] as MeshInstance3D).visible = false


## One-shots: the dash's afterimage streak.
func on_event(e: Dictionary, sim: HHSim) -> void:
	if not enabled or str(e.get("type", "")) != "dash":
		return
	var a: Vector3 = e.get("from", Vector3.ZERO)
	var b: Vector3 = e.get("to", a)
	var u := sim.unit(str(e.get("id", "")))
	var c := HHLook.glow_color(str(u.get("element", ""))).lerp(Color.WHITE, 0.5)
	var dir := (b - a)
	dir.y = 0.0
	var n := 18
	for i in n:
		var t := float(i) / float(n - 1)
		var p := a.lerp(b, t) + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.3, 1.8), _rng.randf_range(-0.15, 0.15))
		motes.spawn({ "pos": p, "vel": -dir.normalized() * 2.0 if dir.length() > 0.01 else Vector3.ZERO, "life": 0.18 + 0.2 * t,
			"size": 0.22, "size_end": 0.02, "color": Color(c.r, c.g, c.b, 0.8), "shape": HHFxParticles.STREAK, "streak": 0.06 })
