class_name HHWorldMap
extends Node3D
## The region map (Lane H, H48): one overhead 3D screen about 200 m across
## with four sites in the four biome looks (pond, cave mouth, glade,
## caldera), a hunter token that runs where you right-click (the fight's
## pace and orbit camera), and ONE disturbance: rings and motes pulsing at
## a site the seed picks. Walking within `hunt_approach_m` of it ends the
## screen with finished({ result: "approach", monster, arena, site }).
## The other sites show their monster's name when the cursor is near them.
##
##   right-click   run there        left-drag / middle-drag   orbit
##   wheel         zoom             Esc                       quit the hunt
##
## `layout(seed)` is pure (sites, which one stirs, the terrain blobs) so a
## test can check determinism without a window; `setup(cfg)` builds the
## scene and works out of the tree (no camera / viewport needed).

signal finished(result: Dictionary)

const BIOMES := ["pond", "cave", "glade", "caldera"]
const MONSTER_OF := { "pond": "swampfang", "cave": "rimeslithe", "glade": "spirewalker", "caldera": "colambros" }
const HF_STEP := 2.0            ## terrain sample spacing (m)
const SITE_R := 14.0            ## a site's dressed radius (m)
const HOVER_PX := 90.0          ## cursor within this of a site shows its name
const MAX_STEP := 1.0 / 20.0    ## movement integrates at most this long per step
const CAM_SCALE := 4.0          ## the camera rig's parent scale (H502): rig metres x4 = world metres
const TOKEN_SCALE := 1.6        ## the hunter is a map token, a little bigger than life

var cfg := {}
var seed := 1
var layout_data := {}           ## layout(seed)
var sites: Array = []           ## [{ biome, monster, pos: Vector3, angle }]
var disturbance := 0            ## index into sites
var hunter: Node3D
var camera: HHCameraRig
var hover_site := -1
var hover_force := -1           ## tools: show this site's name as if hovered
var goal := HHSim.NO_POS
var time := 0.0
var _hf := PackedFloat32Array()
var _hf_n := 0
var _hf_origin := 0.0
var _rings: Array = []
var _labels: Array = []
var _hint: Label
var _cam_root: Node3D
var _token_ring: MeshInstance3D
var _done := false
var _setup_done := false
var _hunter_prev := Vector3.ZERO


# ------------------------------------------------------------------ pure

## Where the four sites sit and which one stirs, from the seed alone.
static func layout(p_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunt-map-%d" % p_seed)
	var base := rng.randf_range(0.0, TAU)
	var order := BIOMES.duplicate()
	for i in range(order.size() - 1, 0, -1):          # seeded shuffle: which corner each biome takes
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out_sites: Array = []
	var r := HHHuntKit.t("map_site_r")
	for i in 4:
		var a := base + TAU * float(i) / 4.0 + rng.randf_range(-0.22, 0.22)
		var d := r + rng.randf_range(-8.0, 8.0)
		var biome: String = order[i]
		out_sites.append({ "biome": biome, "monster": MONSTER_OF[biome], "pos": Vector3(cos(a) * d, 0.0, sin(a) * d), "angle": a })
	var which := rng.randi_range(0, 3)
	var blobs: Array = []
	if ResourceLoader.exists("res://src/arena/gen/gen_util.gd"):
		var gu: GDScript = load("res://src/arena/gen/gen_util.gd")
		blobs = gu.make_blobs(rng, 28, 95.0, 9.0, 26.0, 2.6)
	else:
		for i in 28:
			blobs.append({ "x": rng.randf_range(-95, 95), "z": rng.randf_range(-95, 95), "s": rng.randf_range(9, 26), "a": rng.randf_range(-2.6, 2.6) })
	return { "sites": out_sites, "disturbance": which, "blobs": blobs }


static func within_approach(hunter_pos: Vector3, site_pos: Vector3, radius: float) -> bool:
	return Vector2(hunter_pos.x - site_pos.x, hunter_pos.z - site_pos.z).length() <= radius


# ------------------------------------------------------------------ setup

func setup(p_cfg: Dictionary) -> void:
	if _setup_done:
		return
	_setup_done = true
	cfg = p_cfg
	seed = int(cfg.get("seed", 1))
	layout_data = layout(seed)
	sites = layout_data.sites
	disturbance = int(layout_data.disturbance)
	_bake_heights()
	_build_terrain()
	_build_sites()
	_build_disturbance()
	_build_lights()
	hunter = HHHuntKit.hunter_body(str(cfg.get("weapon", "lance")))
	hunter.name = "Hunter"
	hunter.position = Vector3(0.0, height_at(0.0, 0.0), 0.0)
	hunter.scale = Vector3.ONE * TOKEN_SCALE
	_hunter_prev = hunter.position
	add_child(hunter)
	_token_ring = HHHuntKit.ring(HHLook.TRUE_HEX, 0.22, 24)        # the true-hex colour under the token
	_token_ring.name = "TokenRing"
	_token_ring.scale = Vector3(2.4, 1.0, 2.4)
	add_child(_token_ring)
	# H502: the rig clamps dist to 40 m; a 200 m region needs ~110 m, so the
	# rig sits under a scaled parent (Camera3D orthonormalises, so only the
	# orbit radius scales). Pivots are given in rig units: world / CAM_SCALE.
	_cam_root = Node3D.new()
	_cam_root.name = "CameraRoot"
	_cam_root.scale = Vector3.ONE * CAM_SCALE
	add_child(_cam_root)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	camera.pivot_lift = 0.0
	camera.dist = HHHuntKit.t("map_cam_dist") / CAM_SCALE
	camera.pitch = deg_to_rad(HHHuntKit.t("map_cam_pitch"))
	camera.yaw = atan2(-(sites[disturbance].pos as Vector3).x, -(sites[disturbance].pos as Vector3).z) + PI   # start looking toward the stir
	_cam_root.add_child(camera)
	camera.clicked.connect(_on_click)
	camera.follow(hunter.position / CAM_SCALE, true)
	_build_hud()


# ------------------------------------------------------------------ terrain

## The raw ground: rolling blobs, a bowl at the pond, a mound at the cave,
## a rim at the caldera, flat at the glade and the start.
func _ground(x: float, z: float) -> float:
	var h := 0.0
	var blobs: Array = layout_data.blobs
	for b in blobs:
		var bd: Dictionary = b
		var dx := x - float(bd.x)
		var dz := z - float(bd.z)
		var s := float(bd.s)
		h += float(bd.a) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
	var flat := clampf(1.0 - Vector2(x, z).length() / 16.0, 0.0, 1.0)
	h *= 1.0 - smoothstep(0.0, 1.0, flat)
	for s in sites:
		var sp: Vector3 = s.pos
		var d := Vector2(x - sp.x, z - sp.z).length()
		var w := smoothstep(0.0, 1.0, clampf(1.0 - d / (SITE_R + 4.0), 0.0, 1.0))
		var base := _ground_blobs_only(sp.x, sp.z)
		h = lerpf(h, base, w)                           # level the site to its own base
		match str(s.biome):
			"pond": h -= 1.6 * smoothstep(0.0, 1.0, clampf(1.0 - d / 12.0, 0.0, 1.0))
			"cave": h += 5.0 * smoothstep(0.0, 1.0, clampf(1.0 - d / 13.0, 0.0, 1.0))
			"caldera":
				h += 4.5 * smoothstep(0.0, 1.0, clampf(1.0 - absf(d - 9.5) / 5.0, 0.0, 1.0))
				h -= 1.2 * smoothstep(0.0, 1.0, clampf(1.0 - d / 7.0, 0.0, 1.0))
	return h


func _ground_blobs_only(x: float, z: float) -> float:
	var h := 0.0
	var blobs: Array = layout_data.blobs
	for b in blobs:
		var bd: Dictionary = b
		var dx := x - float(bd.x)
		var dz := z - float(bd.z)
		var s := float(bd.s)
		h += float(bd.a) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
	return h


func _bake_heights() -> void:
	var span := HHHuntKit.t("map_span_m")
	_hf_n = int(span / HF_STEP) + 1
	_hf_origin = -span * 0.5
	_hf.resize(_hf_n * _hf_n)
	for j in _hf_n:
		for i in _hf_n:
			_hf[j * _hf_n + i] = _ground(_hf_origin + i * HF_STEP, _hf_origin + j * HF_STEP)


## Bilinear ground height; flat beyond the baked region.
func height_at(x: float, z: float) -> float:
	if _hf_n == 0:
		return 0.0
	var fx := clampf((x - _hf_origin) / HF_STEP, 0.0, float(_hf_n - 1) - 0.001)
	var fz := clampf((z - _hf_origin) / HF_STEP, 0.0, float(_hf_n - 1) - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := _hf[j * _hf_n + i]
	var h10 := _hf[j * _hf_n + i + 1]
	var h01 := _hf[(j + 1) * _hf_n + i]
	var h11 := _hf[(j + 1) * _hf_n + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _site_near(x: float, z: float) -> Dictionary:
	var best := {}
	var bd := 1e9
	for i in sites.size():
		var sp: Vector3 = sites[i].pos
		var d := Vector2(x - sp.x, z - sp.z).length()
		if d < bd:
			bd = d
			best = { "i": i, "d": d, "biome": sites[i].biome }
	return best


## Role and tint for the ground quad centred at (x, z).
func _pick(x: float, z: float) -> Array:
	var s := _site_near(x, z)
	var d: float = s.d
	var h := height_at(x, z)
	var shade := clampf(0.82 + h * 0.03, 0.7, 1.0)
	if d < SITE_R:
		var inner := clampf(1.0 - d / SITE_R, 0.0, 1.0)
		match str(s.biome):
			"pond": return ["pond_bed" if d < 11.0 else "meadow_grass", Color(shade, shade, shade)]
			"cave": return ["cave_floor" if d < 11.0 else "stone_grey", Color(1.0 - inner * 0.35, 1.0 - inner * 0.35, 1.0 - inner * 0.3)]
			"glade": return ["glade_grass", Color(1.0, 1.0, 1.0)]
			"caldera": return ["ash" if d < 7.0 else "snow", Color(1.0, 1.0, 1.0)]
	if d < SITE_R + 6.0:
		var t := (d - SITE_R) / 6.0
		var c := lerpf(0.9, shade, t)
		return ["meadow_grass", Color(c, c, c)]
	if h > 6.0:
		return ["stone_grey", Color(shade, shade, shade)]
	return ["meadow_grass", Color(shade, shade, shade)]


func _build_terrain() -> void:
	var g := GKMesh.new()
	for j in _hf_n - 1:
		for i in _hf_n - 1:
			var x0 := _hf_origin + i * HF_STEP
			var z0 := _hf_origin + j * HF_STEP
			var rt := _pick(x0 + HF_STEP * 0.5, z0 + HF_STEP * 0.5)
			g.tint = rt[1]
			g.quad(str(rt[0]), Vector3(x0, _hf[j * _hf_n + i], z0), Vector3(x0 + HF_STEP, _hf[j * _hf_n + i + 1], z0),
				Vector3(x0 + HF_STEP, _hf[(j + 1) * _hf_n + i + 1], z0 + HF_STEP), Vector3(x0, _hf[(j + 1) * _hf_n + i], z0 + HF_STEP))
	g.tint = Color.WHITE
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = g.commit()
	GKMaterials.apply(mi)
	add_child(mi)


## The four sites' dressing, one mesh each: water + reeds + pads, a mound
## with a black mouth and stalagmites, trees and flowers, a basalt rim round
## a lava pool. Seeded from the map seed so every run of a seed matches.
func _build_sites() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunt-sites-%d" % seed)
	for i in sites.size():
		var s: Dictionary = sites[i]
		var sp: Vector3 = s.pos
		var g := GKMesh.new()
		var cy := height_at(sp.x, sp.z)
		match str(s.biome):
			"pond":
				var wl := cy + 1.1
				var ring_pts := PackedVector3Array()
				for k in 32:
					var a := TAU * k / 32.0
					ring_pts.append(Vector3(sp.x + cos(a) * 10.5, wl, sp.z + sin(a) * 10.5))
				g.poly("water_shallow", ring_pts)
				for k in 14:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(9.0, 12.5)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z)
					var hgt := rng.randf_range(1.2, 2.2)
					g.tube("reed", [p, p + Vector3(0, hgt, 0)], [0.1, 0.03], 6)
					g.sphere("cattail", p + Vector3(0, hgt * 0.8, 0), 0.14, 6, Vector3(1, 2.2, 1))
				for k in 9:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(2.0, 8.5)
					var c := Vector3(sp.x + cos(a) * rr, wl + 0.03, sp.z + sin(a) * rr)
					var pad := PackedVector3Array()
					var pr := rng.randf_range(0.7, 1.3)
					for q in 10:
						var b := TAU * q / 10.0
						pad.append(Vector3(c.x + cos(b) * pr, c.y, c.z + sin(b) * pr))
					g.poly("lilypad", pad)
			"cave":
				var mouth_dir := Vector3(-sp.x, 0.0, -sp.z).normalized()     # the mouth faces the centre
				g.sphere("cave_wall", Vector3(sp.x, cy + 1.5, sp.z), 7.5, 14, Vector3(1.0, 0.75, 1.0))
				g.sphere("cave_wall", Vector3(sp.x, cy + 1.0, sp.z) - mouth_dir * 4.0 + Vector3(3.5, 0, 0), 5.0, 12, Vector3(1.0, 0.9, 1.0))
				g.sphere("cave_wall", Vector3(sp.x, cy + 1.0, sp.z) - mouth_dir * 3.0 - Vector3(3.5, 0, 0), 4.5, 12, Vector3(1.0, 0.85, 1.0))
				var mouth_c := Vector3(sp.x, cy + 1.2, sp.z) + mouth_dir * 6.6
				var mouth := PackedVector3Array()
				var right := mouth_dir.cross(Vector3.UP)
				for k in 14:
					var a := TAU * k / 14.0
					mouth.append(mouth_c + right * cos(a) * 3.2 + Vector3(0, sin(a) * 2.4 + 1.0, 0) + mouth_dir * 0.6)
				g.poly("window_dark", mouth)
				mouth.reverse()
				g.poly("window_dark", mouth)                        # both windings: the mouth reads from any side
				for k in 6:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(8.5, 12.0)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z) - 0.2
					g.tube("stalagmite", [p, p + Vector3(0, rng.randf_range(1.5, 3.2), 0)], [rng.randf_range(0.5, 0.9), 0.0], 8)
			"glade":
				for k in 9:
					var a := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
					var rr := rng.randf_range(6.0, 12.5)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z) - 0.3
					var hgt := rng.randf_range(4.5, 7.0)
					g.tube("glade_trunk", [p, p + Vector3(0, hgt, 0)], [0.45, 0.3], 8)
					g.sphere("canopy", p + Vector3(0, hgt + 1.2, 0), rng.randf_range(2.6, 3.6), 12, Vector3(1.0, 0.8, 1.0))
				for k in 18:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(1.0, 9.0)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z) + 0.35
					g.sphere("glade_flower", p, 0.28, 6)
				for k in 5:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(4.0, 11.0)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z) + 0.3
					g.sphere("bush", p, rng.randf_range(0.9, 1.5), 8, Vector3(1.0, 0.7, 1.0))
			"caldera":
				var rim: Array = []
				for k in 25:
					var a := TAU * k / 24.0
					var p := Vector3(sp.x + cos(a) * 9.5, 0.0, sp.z + sin(a) * 9.5)
					p.y = height_at(p.x, p.z) + 0.6
					rim.append(p)
				g.tube("basalt", rim, 2.6, 10, false)
				var lava := PackedVector3Array()
				var ly := height_at(sp.x, sp.z) + 0.6
				for k in 24:
					var a := TAU * k / 24.0
					lava.append(Vector3(sp.x + cos(a) * 6.5, ly, sp.z + sin(a) * 6.5))
				g.poly("lava", lava)
				for k in 7:
					var a := rng.randf_range(0.0, TAU)
					var rr := rng.randf_range(11.0, 14.0)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z) + 0.2
					g.sphere("scoria", p, rng.randf_range(0.6, 1.3), 7, Vector3(1.0, 0.7, 1.2))
		var mi := MeshInstance3D.new()
		mi.name = "Site_%s" % str(s.biome)
		mi.mesh = g.commit()
		GKMaterials.apply(mi)
		add_child(mi)
		if str(s.biome) == "caldera":                            # a glow disc so the lava reads from above
			var glow := HHHuntKit.ring(Color(1.0, 0.5, 0.1, 0.55), 1.0, 24)
			glow.position = Vector3(sp.x, cy + 0.75, sp.z)
			glow.scale = Vector3(5.5, 1, 5.5)
			add_child(glow)
		var l := Label3D.new()
		l.text = HHHuntFlow.display_name(str(s.monster))
		l.font_size = 96
		l.pixel_size = 0.055                                     # ~5 m tall: legible from 110 m up
		l.outline_size = 18
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(sp.x, cy + 9.0, sp.z)
		l.modulate = Color(1, 1, 1, 0.0)
		l.outline_modulate = Color(0, 0, 0, 0.0)
		add_child(l)
		_labels.append(l)


func _site_surface_y(i: int) -> float:
	var sp: Vector3 = sites[i].pos
	var y := height_at(sp.x, sp.z)
	match str(sites[i].biome):
		"pond": return y + 1.15
		"caldera": return y + 0.7
	return y + 0.15


func _build_disturbance() -> void:
	var s: Dictionary = sites[disturbance]
	var sp: Vector3 = s.pos
	var d := HHHuntKit.disturbance(str(s.biome))
	var y := _site_surface_y(disturbance)
	for k in 3:
		var r := HHHuntKit.ring(d.ring, 0.14)
		r.name = "Pulse%d" % k
		r.position = Vector3(sp.x, y + 0.05, sp.z)
		add_child(r)
		_rings.append(r)
	var motes := HHHuntKit.motes(str(s.biome), 60, 3.0)
	motes.name = "Motes"
	motes.position = Vector3(sp.x, y, sp.z)
	add_child(motes)


func _build_lights() -> void:
	var lights := { "sun_dir_deg": [-58.0, 30.0], "sun_energy": 1.25, "sky_top": "#5a8ce6", "sky_horizon": "#c7d9ea", "ambient": 0.85 }
	if ResourceLoader.exists("res://src/arena/stage.gd"):
		var stage: GDScript = load("res://src/arena/stage.gd")
		var sun: DirectionalLight3D = stage.sun(lights)
		sun.directional_shadow_max_distance = 160.0
		add_child(sun)
		add_child(stage.sky(lights))
		return
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_hint = HHHuntKit.label("", 18)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.position = Vector2(16, 14)
	layer.add_child(_hint)
	var s: Dictionary = sites[disturbance]
	var d := HHHuntKit.disturbance(str(s.biome))
	_hint.text = "Something %s in %s.   Right-click: run    drag: orbit    Esc: leave" % [d.verb, HHHuntFlow.display_name(str(s.biome))]


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if not _setup_done:
		return
	time += delta
	_move(delta)
	_pulse()
	_hover()
	if hunter.has_method("update"):
		hunter.update(delta)
	if _token_ring != null:
		_token_ring.position = hunter.position + Vector3(0, 0.12, 0)
	if camera != null:
		camera.follow(hunter.position / CAM_SCALE)
	if not _done and check_approach():
		_approach()


## Run toward the goal at the fight's pace, clamped to the region.
func _move(delta: float) -> void:
	if goal == HHSim.NO_POS:
		return
	var left := delta
	while left > 0.0:
		var step := minf(left, MAX_STEP)
		left -= step
		var to := Vector2(goal.x - hunter.position.x, goal.z - hunter.position.z)
		var dist := to.length()
		if dist < 0.05:
			goal = HHSim.NO_POS
			break
		var mv := minf(dist, HHHuntKit.t("run_mps") * step)
		var dir := to / dist
		var nx := hunter.position.x + dir.x * mv
		var nz := hunter.position.z + dir.y * mv
		var lim := HHHuntKit.t("map_span_m") * 0.5 - 4.0
		nx = clampf(nx, -lim, lim)
		nz = clampf(nz, -lim, lim)
		hunter.position = Vector3(nx, height_at(nx, nz), nz)
		hunter.rotation.y = atan2(dir.x, dir.y)


func _pulse() -> void:
	var period := HHHuntKit.t("pulse_period")
	var rad := HHHuntKit.t("pulse_radius_m")
	for k in _rings.size():
		var r: MeshInstance3D = _rings[k]
		var ph := fmod(time / period + float(k) / 3.0, 1.0)
		var sc := maxf(0.2, ph * rad)
		r.scale = Vector3(sc, 1.0, sc)
		var m: StandardMaterial3D = r.material_override
		var base: Color = HHHuntKit.disturbance(str(sites[disturbance].biome)).ring
		m.albedo_color = Color(base.r, base.g, base.b, base.a * (1.0 - ph) * (1.0 - ph))


## Site names fade in when the cursor is near them on screen.
func _hover() -> void:
	var vp := get_viewport()
	if vp == null or camera == null or camera.cam == null:
		return
	var mouse := vp.get_mouse_position()
	var best := -1
	var bd := HOVER_PX
	for i in sites.size():
		var l: Label3D = _labels[i]
		var p := camera.cam.unproject_position(l.position - Vector3(0, 6, 0))
		if camera.cam.is_position_behind(l.position):
			continue
		var d := p.distance_to(mouse)
		if d < bd:
			bd = d
			best = i
	hover_site = best if hover_force < 0 else hover_force
	for i in _labels.size():
		var l: Label3D = _labels[i]
		var want := 1.0 if i == hover_site else 0.0
		var a := move_toward(l.modulate.a, want, 0.12)
		l.modulate = Color(1, 1, 1, a)
		l.outline_modulate = Color(0, 0, 0, a)


## True when the hunter stands within hunt_approach_m of the stirring site.
func check_approach() -> bool:
	if hunter == null or sites.is_empty():
		return false
	return within_approach(hunter.position, sites[disturbance].pos, HHHuntKit.t("approach_m"))


func _approach() -> void:
	if _done:
		return
	_done = true
	goal = HHSim.NO_POS
	var s: Dictionary = sites[disturbance]
	finished.emit({ "result": "approach", "monster": str(s.monster), "arena": str(s.biome), "site": disturbance })


## Tests and tools: put the hunter somewhere (on the ground there).
func teleport(x: float, z: float) -> void:
	hunter.position = Vector3(x, height_at(x, z), z)
	goal = HHSim.NO_POS
	if camera != null:
		camera.follow(hunter.position / CAM_SCALE, true)


func run_to(x: float, z: float) -> void:
	goal = Vector3(x, height_at(x, z), z)


# ------------------------------------------------------------------ input

func _on_click(button: int, screen_pos: Vector2) -> void:
	if button != MOUSE_BUTTON_RIGHT or _done:
		return
	var p := HHHuntKit.ground_under(camera, screen_pos, height_at)
	if p != HHSim.NO_POS:
		goal = p


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE and not _done:
		_done = true
		finished.emit({ "result": "quit" })
