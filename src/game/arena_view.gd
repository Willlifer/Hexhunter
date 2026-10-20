class_name HHArenaView
extends Node3D
## Draws an HHArena: the floor (a Lane C GKAsset when one is given, else a
## heightfield floor from GKMesh), lighting, the painted-hex FX layers over
## the charge grid, the telegraph danger hexes, and the true-hex outlines.
## Reads the sim; never writes it.

const FX_LIFT := 0.04        # painted faces sit this far above the ground
const TG_LIFT := 0.07        # telegraphs above the paint
const OUTLINE_LIFT := 0.09
const TIER_RATE := 6.0       # tier fade in/out, per second

var arena: HHArena
var asset: GKAsset
var floor_mi: MeshInstance3D
var fx := {}                 # hex -> { face_h, face_v, mark, tier_h, tier_v, tier_m }
var tg_pool: Array = []      # MeshInstance3D for telegraph hexes
var true_hex: MeshInstance3D
var dest_hex: MeshInstance3D
var sun: DirectionalLight3D
var _tg_mat: ShaderMaterial
var _tg_player_mat: ShaderMaterial          # R-U3: the hunter's own telegraphs (aftershock, bomblet)
var proj_pool: Array = []                   # R-U3: MeshInstance3D markers for sim.projectiles
var flashes: Array = []                     # R-U3: [{ mi, t }] launch / hit / end flashes, fading
var _proj_seen := {}                        # projectile id -> last hex (hits / ends found by disappearance)
const PLAYER_TG := Color(1.0, 0.85, 0.3)    # gold: the hunter's own shapes
const PROJ_LIFT := 0.7
const FLASH_SECONDS := 0.35


func build(a: HHArena, p_asset: GKAsset = null) -> void:
	arena = a
	asset = p_asset
	for c in get_children():
		c.queue_free()
	fx = {}
	tg_pool = []
	if asset != null:
		var root := asset.instantiate(true)
		root.name = "Env"
		add_child(root)
	else:
		_build_floor()
	_build_lights()
	true_hex = _outline(HHLook.TRUE_HEX)
	dest_hex = _outline(HHLook.DEST_HEX)
	dest_hex.visible = false
	_tg_mat = ShaderMaterial.new()
	_tg_mat.shader = load("res://shaders/telegraph.gdshader")
	_tg_player_mat = ShaderMaterial.new()
	_tg_player_mat.shader = _tg_mat.shader
	_tg_player_mat.set_shader_parameter("glow", PLAYER_TG)
	proj_pool = []
	flashes = []
	_proj_seen = {}


func _build_floor() -> void:
	var g := GKMesh.new()
	var hf: Dictionary = arena.hf
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var ox: float = hf.origin[0]
	var oz: float = hf.origin[1]
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
	if asset != null and not asset.lights.is_empty() and ResourceLoader.exists("res://src/arena/stage.gd"):
		var stage: GDScript = load("res://src/arena/stage.gd")       # Lane C: the biome's own sun and sky
		sun = stage.sun(asset.lights)
		add_child(sun)
		add_child(stage.sky(asset.lights))
		return
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
	var flat := arena.kind(hex) in ["water", "deep", "pad"]
	var sy := arena.surface(hex).y
	for i in 7:
		var p := c[i % 6]
		var y := sy if flat else arena.height_at(w.x + p.x, w.y + p.z)
		im.surface_add_vertex(Vector3(p.x, y + OUTLINE_LIFT, p.z))
	im.surface_end()
	mi.position = Vector3(w.x, 0.0, w.y)
	mi.visible = true


## Per frame: outlines, FX layers and telegraphs from the sim.
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
	_sync_telegraphs(sim, player_id)
	_sync_projectiles(sim, delta)


## R-U3: the hunter's own telegraphs (its id as owner, or the upgrade shapes
## named aftershock / bomblet) draw in the player tint, everything else in
## the monster's red.
static func is_player_telegraph(tg: Dictionary, player_id: String) -> bool:
	if player_id != "" and str(tg.get("owner", "")) == player_id:
		return true
	return str((tg.get("payload", {}) as Dictionary).get("name", "")) in ["aftershock", "bomblet"]


func _sync_telegraphs(sim: HHSim, player_id: String = "") -> void:
	var n := 0
	for tg in sim.telegraphs:
		var prog := 1.0 - float(tg.left) / maxf(1.0, float(tg.total))
		var mat := _tg_player_mat if is_player_telegraph(tg, player_id) else _tg_mat
		for h in tg.hexes:
			if not arena.exists(h):
				continue
			var mi: MeshInstance3D
			if n < tg_pool.size():
				mi = tg_pool[n]
			else:
				mi = MeshInstance3D.new()
				mi.mesh = HHTileFX.hex_mesh()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				tg_pool.append(mi)
			mi.material_override = mat
			mi.position = arena.surface(h) + Vector3(0, TG_LIFT, 0)
			var ripple := bool((tg.payload as Dictionary).get("ripple", false))
			mi.set_instance_shader_parameter("progress", 0.0 if ripple else prog)
			mi.set_instance_shader_parameter("tier", 0.45 if ripple else 1.0)
			mi.visible = true
			n += 1
	for i in range(n, tg_pool.size()):
		(tg_pool[i] as MeshInstance3D).visible = false


## R-U3: sim.projectiles as small glowing markers over their hex (element
## colour, a hop that peaks between steps), with flashes on launch and on
## every disappearance (a hit or an end), found by comparing ids between
## frames so no event wiring in fight.gd is needed.
func _sync_projectiles(sim: HHSim, delta: float) -> void:
	var n := 0
	var seen := {}
	for p in sim.projectiles:
		var h: Vector2i = p.hex
		if not arena.exists(h):
			continue
		seen[p.id] = h
		var mi: MeshInstance3D
		if n < proj_pool.size():
			mi = proj_pool[n]
		else:
			mi = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.32
			sm.height = 0.64
			sm.radial_segments = 10
			sm.rings = 5
			mi.mesh = sm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			proj_pool.append(mi)
		var el := str(p.get("element", ""))
		mi.material_override = HHLook.flat(HHLook.glow_color(el) if el != "" else Color(0.95, 0.9, 0.7))
		var every := maxf(1.0, float(p.get("every", 2)))
		var phase := 1.0 - float(p.get("left", every)) / every          # 0 just after a step, 1 just before the next
		mi.position = arena.surface(h) + Vector3(0, PROJ_LIFT + 0.35 * sin(phase * PI), 0)
		mi.scale = Vector3.ONE * (1.0 + 0.3 * (1.0 - phase))
		mi.visible = true
		if not _proj_seen.has(p.id):
			_flash(arena.surface(h), HHLook.glow_color(el) if el != "" else Color(1, 1, 0.8), 0.9)   # launch
		n += 1
	for i in range(n, proj_pool.size()):
		(proj_pool[i] as MeshInstance3D).visible = false
	for id in _proj_seen:
		if not seen.has(id):
			var last: Vector2i = _proj_seen[id]
			if arena.exists(last):
				_flash(arena.surface(last), Color(1.0, 0.95, 0.8), 1.6)                                # hit or end
	_proj_seen = seen
	var keep: Array = []
	for f in flashes:
		f.t = float(f.t) + delta
		var k := clampf(float(f.t) / FLASH_SECONDS, 0.0, 1.0)
		var mi: MeshInstance3D = f.mi
		mi.scale = Vector3.ONE * float(f.size) * (0.6 + 1.2 * k)
		var m := mi.material_override as StandardMaterial3D
		m.albedo_color.a = 0.85 * (1.0 - k)
		if k >= 1.0:
			mi.queue_free()
		else:
			keep.append(f)
	flashes = keep


func _flash(at: Vector3, col: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	var c := col
	c.a = 0.85
	mi.material_override = HHLook.flat(c, true)
	(mi.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.position = at + Vector3(0, PROJ_LIFT, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	flashes.append({ "mi": mi, "t": 0.0, "size": size })


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
	var w := arena.surface(hex)
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
