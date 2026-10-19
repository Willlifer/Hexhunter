class_name HHArenaView
extends Node3D
## Draws an HHArena: the heightfield floor (GKMesh, Gauntlet kit materials),
## the skirt, lighting, the painted-hex FX layers over the charge grid, and
## the true-hex outlines. Reads the sim; never writes it.

const FX_LIFT := 0.04        # painted faces sit this far above the ground
const OUTLINE_LIFT := 0.06
const TIER_RATE := 6.0       # tier fade in/out, per second

var arena: HHArena
var floor_mi: MeshInstance3D
var fx := {}                 # hex -> { face_h, face_v, mark, tier_h, tier_v, tier_m }
var true_hex: MeshInstance3D
var dest_hex: MeshInstance3D
var sun: DirectionalLight3D


func build(a: HHArena) -> void:
	arena = a
	for c in get_children():
		c.queue_free()
	fx = {}
	_build_floor()
	_build_lights()
	true_hex = _outline(HHLook.TRUE_HEX)
	dest_hex = _outline(HHLook.DEST_HEX)
	dest_hex.visible = false


func _build_floor() -> void:
	var g := GKMesh.new()
	var hf: Dictionary = arena.hf
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var ox: float = hf.origin[0]
	var oz: float = hf.origin[1]
	# subdivide each heightfield cell so hex-scale bumps read; the floor role
	# inside the radius, the skirt role outside
	var sub := 3
	var fs := step / sub
	for j in (rows - 1) * sub:
		for i in (cols - 1) * sub:
			var x0 := ox + i * fs
			var z0 := oz + j * fs
			var p := [Vector3(x0, arena.height_at(x0, z0), z0), Vector3(x0 + fs, arena.height_at(x0 + fs, z0), z0),
				Vector3(x0 + fs, arena.height_at(x0 + fs, z0 + fs), z0 + fs), Vector3(x0, arena.height_at(x0, z0 + fs), z0 + fs)]
			var cx := x0 + fs * 0.5
			var cz := z0 + fs * 0.5
			var d := sqrt(cx * cx + cz * cz)
			var role := "grass" if d <= arena.radius_m else ("hedge" if d <= arena.radius_m + 2.5 else "stone_grey")
			g.quad(role, p[0], p[1], p[2], p[3])      # this winding faces up (GKMesh emits CW for the front)
	floor_mi = MeshInstance3D.new()
	floor_mi.name = "Floor"
	floor_mi.mesh = g.commit()
	GKMaterials.apply(floor_mi)
	add_child(floor_mi)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.35, 0.55, 0.9)
	mat.sky_horizon_color = Color(0.78, 0.85, 0.92)
	mat.ground_bottom_color = Color(0.2, 0.22, 0.2)
	mat.ground_horizon_color = Color(0.6, 0.62, 0.58)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _outline(c: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = HHLook.flat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _draw_outline(mi: MeshInstance3D, hex: Vector2i) -> void:
	var im: ImmediateMesh = mi.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var c := HHHex.corners(Vector3.ZERO, HHArena.HEX * 0.92)
	var w := HHHex.to_world(hex, HHArena.HEX)
	for i in 7:
		var p := c[i % 6]
		im.surface_add_vertex(Vector3(p.x, arena.height_at(w.x + p.x, w.y + p.z) + OUTLINE_LIFT, p.z))
	im.surface_end()
	mi.position = Vector3(w.x, 0.0, w.y)
	mi.visible = true


## Per frame: the true-hex outlines and the FX layers from the sim.
func sync(sim: HHSim, player_id: String, delta: float) -> void:
	var p := sim.unit(player_id)
	if not p.is_empty():
		_draw_outline(true_hex, p.hex)
		var path: Array = p.path
		if path.is_empty():
			dest_hex.visible = false
		else:
			_draw_outline(dest_hex, path[-1])
	_sync_fx(sim.charge, delta)


func _sync_fx(charge: HHCharge, delta: float) -> void:
	var live := {}
	for hex in charge.entries:
		live[hex] = true
		var L := HHTileFX.layers(charge.entries[hex])
		var node: Dictionary = fx.get(hex, {})
		if node.is_empty():
			node = _make_fx(hex)
			fx[hex] = node
		_set_face(node, "h", L.h, delta)
		_set_face(node, "v", L.v, delta)
		_set_mark(node, L, delta)
	# fade out and drop what is gone
	for hex in fx.keys():
		if live.has(hex):
			continue
		var node: Dictionary = fx[hex]
		var any := false
		for k in ["h", "v", "m"]:
			node["tier_" + k] = maxf(0.0, float(node["tier_" + k]) - TIER_RATE * delta)
			any = any or float(node["tier_" + k]) > 0.0
		_push_tier(node.face_h, float(node.tier_h))
		_push_tier(node.face_v, float(node.tier_v))
		_push_tier(node.mark, float(node.tier_m))
		if not any:
			for k in ["face_h", "face_v", "mark"]:
				(node[k] as Node).queue_free()
			fx.erase(hex)


func _make_fx(hex: Vector2i) -> Dictionary:
	var w := arena.world(hex)
	var node := { "tier_h": 0.0, "tier_v": 0.0, "tier_m": 0.0, "el_h": "", "el_v": "", "kind_m": "" }
	for k in ["face_h", "face_v", "mark"]:
		var mi := MeshInstance3D.new()
		mi.mesh = HHTileFX.hex_mesh()
		mi.position = w + Vector3(0, FX_LIFT + (0.01 if k == "mark" else 0.0), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("seed", HHTileFX.seed_for(hex))
		mi.set_instance_shader_parameter("tier", 0.0)
		mi.visible = false
		add_child(mi)
		node[k] = mi
	return node


func _set_face(node: Dictionary, axis: String, layer: Dictionary, delta: float) -> void:
	var mi: MeshInstance3D = node["face_" + axis]
	var want := float(layer.get("tier", 0))
	if not layer.is_empty() and node["el_" + axis] != layer.el:
		node["el_" + axis] = layer.el
		mi.material_override = HHTileFX.material(HHTileFX.FACE[layer.el])
		node["tier_" + axis] = 0.0
	node["tier_" + axis] = move_toward(float(node["tier_" + axis]), want, TIER_RATE * delta)
	_push_tier(mi, float(node["tier_" + axis]))


func _set_mark(node: Dictionary, L: Dictionary, delta: float) -> void:
	var mi: MeshInstance3D = node.mark
	var kind := str(L.mark)
	if kind != "" and node.kind_m != kind:
		node.kind_m = kind
		mi.material_override = HHTileFX.material(kind)
		node.tier_m = 0.0
	node.tier_m = move_toward(float(node.tier_m), 1.0 if kind != "" else 0.0, TIER_RATE * delta)
	_push_tier(mi, float(node.tier_m))
	mi.set_instance_shader_parameter("crack", 1.0 if bool(L.crack) else 0.0)
	mi.set_instance_shader_parameter("age", 1.0)
	var frost := 1.0 if kind == "glaze" else 0.0
	node.face_h.set_instance_shader_parameter("frost", frost)
	node.face_v.set_instance_shader_parameter("frost", frost)


func _push_tier(mi: MeshInstance3D, tier: float) -> void:
	mi.set_instance_shader_parameter("tier", tier)
	mi.visible = tier > 0.001
