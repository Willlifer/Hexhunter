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
const CAM_DIST_MAX := 260.0     ## L-21 (H761): the map rig's own zoom-out limit (world metres)
const BAKE_MARGIN := 80.0       ## terrain baked this far beyond the playable span, so the frame never shows its edge
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
var dress := {}                 ## dress_layout(seed, sites): paths, lake, landmarks (H760)
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


## H760 (Lane ENV, L-20): the region's dressing from the seed alone, on its
## own rng stream so layout() (sites, disturbance) is untouched. Paths from
## the start to each site (a gentle seeded bend), a lake and its river in
## one gap between sites, a ruined tower and a stone ring in two others,
## tree clusters and rock outcrops off the paths.
static func dress_layout(p_seed: int, p_sites: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunt-dress-%d" % p_seed)
	var paths: Array = []
	for s in p_sites:
		var sp: Vector3 = s.pos
		var to := Vector2(sp.x, sp.z)
		var side := Vector2(-to.y, to.x).normalized() * rng.randf_range(-10.0, 10.0)
		paths.append({ "a": Vector2.ZERO, "c": to * 0.5 + side, "b": to - to.normalized() * (SITE_R - 3.0) })
	# the four gaps between neighbouring sites, by angle
	var angs: Array = []
	for s in p_sites:
		angs.append(fposmod(float(s.angle), TAU))
	angs.sort()
	var gaps: Array = []
	for i in 4:
		var a0: float = angs[i]
		var a1: float = angs[(i + 1) % 4] + (TAU if i == 3 else 0.0)
		gaps.append(fposmod((a0 + a1) * 0.5, TAU))
	var order := [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var lake_a: float = gaps[order[0]]
	var lake := Vector2(cos(lake_a), sin(lake_a)) * rng.randf_range(76.0, 84.0)
	var river: Array = [lake]
	var dir := lake.normalized()
	var p := lake + dir * 12.0
	for k in 8:
		river.append(p)
		dir = dir.rotated(rng.randf_range(-0.35, 0.35)).lerp(lake.normalized(), 0.4).normalized()
		p += dir * 14.0
	var tower_a: float = gaps[order[1]]
	var tower := Vector2(cos(tower_a), sin(tower_a)) * rng.randf_range(30.0, 38.0)
	var stones_a: float = gaps[order[2]]
	var stones := Vector2(cos(stones_a), sin(stones_a)) * rng.randf_range(62.0, 72.0)
	var grove_a: float = gaps[order[3]]
	var keep: Array = [{ "p": lake, "r": 22.0 }, { "p": tower, "r": 12.0 }, { "p": stones, "r": 11.0 }, { "p": Vector2.ZERO, "r": 18.0 }]
	for s in p_sites:
		keep.append({ "p": Vector2((s.pos as Vector3).x, (s.pos as Vector3).z), "r": SITE_R + 7.0 })
	var clusters: Array = [{ "p": Vector2(cos(grove_a), sin(grove_a)) * rng.randf_range(55.0, 75.0), "r": 14.0, "n": 16 }]
	var outcrops: Array = []
	var tries := 0
	while (clusters.size() < 9 or outcrops.size() < 7) and tries < 400:
		tries += 1
		var q := Vector2(rng.randf_range(-92.0, 92.0), rng.randf_range(-92.0, 92.0))
		var ok := true
		for kp in keep:
			if q.distance_to(kp.p) < float(kp.r) + 6.0:
				ok = false
				break
		if ok:
			for pa in paths:
				if _near_path(q, pa) < 9.0:
					ok = false
					break
		if not ok:
			continue
		if clusters.size() < 9:
			clusters.append({ "p": q, "r": rng.randf_range(6.0, 11.0), "n": rng.randi_range(5, 10) })
			keep.append({ "p": q, "r": 10.0 })
		else:
			outcrops.append({ "p": q, "r": rng.randf_range(2.5, 4.5), "n": rng.randi_range(3, 5) })
			keep.append({ "p": q, "r": 6.0 })
	return { "paths": paths, "lake": lake, "lake_r": 13.0, "river": river, "tower": tower, "stones": stones,
		"clusters": clusters, "outcrops": outcrops, "seed": p_seed }


## A point on a path's quadratic bend (t 0..1).
static func path_at(pa: Dictionary, t: float) -> Vector2:
	var a: Vector2 = pa.a
	var c: Vector2 = pa.c
	var b: Vector2 = pa.b
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


static func _near_path(q: Vector2, pa: Dictionary) -> float:
	var best := 1e9
	for i in 21:
		best = minf(best, q.distance_to(path_at(pa, float(i) / 20.0)))
	return best


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
	dress = dress_layout(seed, sites)
	_bake_heights()
	_build_terrain()
	_build_sites()
	_build_landmarks()
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
	# L-21 (H761): the rig's clamp is per instance now, so the map raises it
	# and the rig sits in world metres (H502's x5 scaled parent is gone)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	camera.pivot_lift = 0.0
	camera.dist_max = CAM_DIST_MAX
	camera.dist = HHHuntKit.t("map_cam_dist")
	camera.pitch = deg_to_rad(HHHuntKit.t("map_cam_pitch"))
	camera.yaw = atan2(-(sites[disturbance].pos as Vector3).x, -(sites[disturbance].pos as Vector3).z) + PI   # start looking toward the stir
	add_child(camera)
	camera.clicked.connect(_on_click)
	camera.follow(hunter.position, true)
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
	if not dress.is_empty():
		# H760: the lake's bowl, and hills rising past the playable square (the region's edge)
		var lk: Vector2 = dress.lake
		var ld := Vector2(x, z).distance_to(lk)
		h -= 2.4 * smoothstep(0.0, 1.0, clampf(1.0 - ld / (float(dress.lake_r) + 5.0), 0.0, 1.0))
		var half := HHHuntKit.t("map_span_m") * 0.5
		var e := maxf(absf(x), absf(z)) * 0.75 + Vector2(x, z).length() * 0.25
		var rise := smoothstep(half - 8.0, half + 40.0, e)
		h += rise * (16.0 + 6.0 * sin(atan2(z, x) * 5.0 + 1.3) + 3.0 * sin(atan2(z, x) * 13.0))
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
	var span := HHHuntKit.t("map_span_m") + BAKE_MARGIN * 2.0
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
	# H760: each site wears its gauntlet-tested arena's palette; the hills at
	# the edge darken and turn to rock; the lake shore is damp
	if d < SITE_R:
		var inner := clampf(1.0 - d / SITE_R, 0.0, 1.0)
		var hh := absf(sin(x * 12.9898 + z * 78.233) * 43758.5453)
		var dither := hh - floorf(hh)
		match str(s.biome):
			"pond": return ["pond_bed" if d < 11.0 else "meadow_grass", Color(shade, shade, shade) if d >= 11.0 else Color(0.5, 0.6, 0.6)]
			"cave": return ["cave_floor" if d < 11.0 else "tube_rock", Color(1.0 - inner * 0.3, 0.95 - inner * 0.3, 0.9 - inner * 0.3)]
			"glade": return ["sun_grass" if d < 4.5 else "glade_grass", Color(1.0, 1.0, 1.0)]
			"caldera":
				if d < 7.5:
					return ["basalt", Color(1.0, 1.0, 1.0)]
				var g := HHCalderaGen.gully(x * 2.0, z * 2.0) if ResourceLoader.exists("res://src/arena/gen/caldera_gen.gd") else dither
				return ["snow" if g + (dither - 0.5) * 0.2 > 0.48 else "rim_rock", Color(1.0, 1.0, 1.0)]
	if d < SITE_R + 6.0:
		var t := (d - SITE_R) / 6.0
		var c := lerpf(0.9, shade, t)
		return ["meadow_grass", Color(c, c, c)]
	var lk: Vector2 = dress.get("lake", Vector2(1e6, 1e6))
	if Vector2(x, z).distance_to(lk) < float(dress.get("lake_r", 0.0)) + 3.0:
		return ["pond_bed", Color(0.22, 0.3, 0.32) if Vector2(x, z).distance_to(lk) < float(dress.get("lake_r", 0.0)) else Color(0.7, 0.75, 0.7)]
	var half := HHHuntKit.t("map_span_m") * 0.5
	var e := maxf(absf(x), absf(z)) * 0.75 + Vector2(x, z).length() * 0.25
	var edge := smoothstep(half - 10.0, half + 30.0, e)
	if h > 9.0:
		return ["moss_rock", Color(shade, shade, shade)]
	var c2 := shade * (1.0 - edge * 0.35)
	return ["meadow_grass", Color(c2, c2, c2 * 0.95)]


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
	var dr := RandomNumberGenerator.new()               # H760: the new dressing's own stream
	dr.seed = hash("hunt-sites-dress-%d" % seed)
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
				# H760: the pond arena's look: pad beds hugging the bank, a conifer stand behind it
				for k in 40:
					var a := dr.randf_range(0.0, TAU)
					var rr := 10.0 - pow(dr.randf(), 1.5) * 6.0
					var c := Vector3(sp.x + cos(a) * rr, wl + 0.03, sp.z + sin(a) * rr)
					var pr := dr.randf_range(0.35, 0.7)
					var pad := PackedVector3Array()
					for q in 7:
						var b := TAU * q / 7.0
						pad.append(Vector3(c.x + cos(b) * pr, c.y, c.z + sin(b) * pr))
					g.tint = Color(dr.randf_range(0.8, 1.1), 1.0, 0.9)
					g.poly("lilypad", pad)
				g.tint = Color.WHITE
				for k in 9:
					var a := TAU * float(k) / 9.0 + dr.randf_range(-0.25, 0.25)
					var rr := dr.randf_range(13.5, 17.0)
					var p := Vector3(sp.x + cos(a) * rr, 0.0, sp.z + sin(a) * rr)
					p.y = height_at(p.x, p.z)
					var ti := dr.randf_range(0.8, 1.1)
					HHGenUtil.conifer(g, "conifer", "bark", p, dr.randf_range(7.0, 11.0), dr.randf_range(1.6, 2.3), Color(ti, ti, ti))
			"cave":
				var mouth_dir := Vector3(-sp.x, 0.0, -sp.z).normalized()     # the mouth faces the centre
				g.tint = Color(1.2, 1.05, 0.95)
				g.sphere("tube_rock", Vector3(sp.x, cy + 1.5, sp.z), 7.5, 14, Vector3(1.0, 0.75, 1.0))
				g.sphere("tube_rock", Vector3(sp.x, cy + 1.0, sp.z) - mouth_dir * 4.0 + Vector3(3.5, 0, 0), 5.0, 12, Vector3(1.0, 0.9, 1.0))
				g.sphere("tube_rock", Vector3(sp.x, cy + 1.0, sp.z) - mouth_dir * 3.0 - Vector3(3.5, 0, 0), 4.5, 12, Vector3(1.0, 0.85, 1.0))
				g.tint = Color.WHITE
				# H760: torches either side of the mouth and their warm pool, as in the cave arena
				var side := mouth_dir.cross(Vector3.UP)
				var pools: Array = []
				for sgn in [-1.0, 1.0]:
					var tp: Vector3 = Vector3(sp.x, 0.0, sp.z) + mouth_dir * 8.5 + side * 4.2 * float(sgn)
					tp.y = height_at(tp.x, tp.z)
					g.cyl("torch_post", tp, tp + Vector3(0, 2.2, 0), 0.12, 6)
					g.sphere("torch_flame", tp + Vector3(0, 2.5, 0), 0.35, 8, Vector3(1.0, 1.6, 1.0))
					pools.append({ "x": tp.x, "z": tp.z, "r": 6.0, "col": Color(0.9, 0.45, 0.12, 1.0) })
				var pool_mi := MeshInstance3D.new()
				pool_mi.name = "CaveGlow"
				pool_mi.mesh = HHGenUtil.glow_discs(pools, "glow_warm", height_at, 0.1)
				pool_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				GKMaterials.apply(pool_mi)
				add_child(pool_mi)
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
					var cw := rng.randf_range(2.6, 3.6)
					# H760: the glade arena's loose two-tone broadleaves, not a lollipop
					HHGenUtil.broadleaf(g, "leaf_young" if k % 2 == 0 else "canopy", "glade_trunk", p + Vector3(cos(a), 0.0, sin(a)) * 3.5, hgt * 1.4, cw * 1.2, dr, Color.WHITE, 5)
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
				g.tube("rim_rock", rim, 2.6, 10, false)
				# H760: the caldera arena's look: snow lying in streaks on the dark rim, steam off the lava
				for k in 16:
					var a := TAU * float(k) / 16.0 + dr.randf_range(-0.12, 0.12)
					var p := Vector3(sp.x + cos(a) * 9.5, 0.0, sp.z + sin(a) * 9.5)
					p.y = height_at(p.x, p.z) + 0.6 + 2.0
					g.push(Transform3D(Basis(Vector3.UP, -a), p))
					g.sphere("snow", Vector3.ZERO, dr.randf_range(1.0, 1.8), 6, Vector3(0.6, 0.25, 1.4))
					g.pop()
				HHGenUtil.plume(g, "steam", Vector3(sp.x, cy + 0.8, sp.z), 9.0, 1.8, dr, 6, 0.05)
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
		if str(s.biome) == "caldera":                            # a soft glow so the lava reads from above (H760)
			var glow := MeshInstance3D.new()
			glow.name = "CalderaGlow"
			glow.mesh = HHGenUtil.glow_discs([{ "x": sp.x, "z": sp.z, "y": cy + 0.7, "r": 12.0, "col": Color(1.0, 0.4, 0.08, 1.0) }], "glow_warm", height_at, 0.0)
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			GKMaterials.apply(glow)
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


## H760 (L-20): the region between the sites. Dirt paths from the start to
## every site, the lake and the stream feeding it, a ruined tower, a ring of
## standing stones, tree clusters, rock outcrops, and a forest wall on the
## hills that close the region in.
func _build_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunt-landmarks-%d" % seed)
	var g := GKMesh.new()
	# -- paths: ribbons draped on the ground, a little wider near the start
	for pd in dress.paths:
		var pa: Dictionary = pd
		var n := 40
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in n + 1:
			var t := float(k) / float(n)
			var p := path_at(pa, t)
			var ahead := path_at(pa, minf(t + 0.01, 1.0)) - path_at(pa, maxf(t - 0.01, 0.0))
			var side := Vector2(-ahead.y, ahead.x).normalized() * lerpf(1.8, 1.3, t)
			var l := Vector3(p.x + side.x, 0.0, p.y + side.y)
			var r := Vector3(p.x - side.x, 0.0, p.y - side.y)
			l.y = height_at(l.x, l.z) + 0.12
			r.y = height_at(r.x, r.z) + 0.12
			if k > 0:
				g.tint = Color(0.95, 0.92, 0.88)
				g.quad("dirt_path", prev_l, prev_r, r, l)
			prev_l = l
			prev_r = r
	# -- the lake: a dark water disc in its bowl, reeds round it, the stream coming down from the hills
	var lk: Vector2 = dress.lake
	var lr: float = dress.lake_r
	var wl := height_at(lk.x, lk.y) + 1.3
	var ring := PackedVector3Array()
	for k in 40:
		var a := TAU * float(k) / 40.0
		var rr := lr + sin(a * 3.0 + 1.0) * 1.5
		ring.append(Vector3(lk.x + cos(a) * rr, wl, lk.y + sin(a) * rr))
	g.poly("water_river", ring)
	for k in 26:
		var a := rng.randf_range(0.0, TAU)
		var rr := lr + rng.randf_range(-0.5, 2.5)
		var p := Vector3(lk.x + cos(a) * rr, 0.0, lk.y + sin(a) * rr)
		p.y = height_at(p.x, p.z)
		HHGenUtil.tuft(g, "reed_tall", p.x, p.y, p.z, rng.randf_range(1.2, 2.2), 5, 0.3, rng.randf() * TAU)
	var river: Array = dress.river
	for k in river.size() - 1:
		var a: Vector2 = river[k]
		var b: Vector2 = river[k + 1]
		var side := Vector2(-(b - a).y, (b - a).x).normalized() * (0.9 + 0.1 * float(k))
		var pts: Array = [a + side, b + side, b - side, a - side]
		var v: Array = []
		for q in pts:
			var qq: Vector2 = q
			v.append(Vector3(qq.x, maxf(height_at(qq.x, qq.y) + 0.15, wl if k == 0 else -100.0), qq.y))
		g.quad("water_river", v[0], v[3], v[2], v[1])
	# -- a ruined tower: a broken round wall, a fallen block, rubble
	var tw: Vector2 = dress.tower
	var ty := height_at(tw.x, tw.y)
	for k in 14:
		var a := TAU * float(k) / 14.0
		var hgt := 9.0 * (0.35 + 0.65 * absf(sin(a * 1.5 + 0.7))) if k % 5 != 0 else 1.2
		var c := Vector3(tw.x + cos(a) * 3.2, ty + hgt * 0.5 - 0.3, tw.y + sin(a) * 3.2)
		g.box("ruin_stone", c, Vector3(1.6, hgt, 1.1), 0.05, Basis(Vector3.UP, -a + PI * 0.5))
	for k in 9:
		var a := rng.randf_range(0.0, TAU)
		var rr := rng.randf_range(4.0, 7.5)
		var c := Vector3(tw.x + cos(a) * rr, 0.0, tw.y + sin(a) * rr)
		c.y = height_at(c.x, c.z) + 0.3
		g.box("ruin_stone", c, Vector3(rng.randf_range(0.6, 1.4), 0.7, rng.randf_range(0.6, 1.2)), 0.05, Basis(Vector3.UP, rng.randf() * TAU))
	# -- standing stones: a ring of eleven and a lintel pair
	var st: Vector2 = dress.stones
	for k in 11:
		var a := TAU * float(k) / 11.0
		var c := Vector3(st.x + cos(a) * 6.5, 0.0, st.y + sin(a) * 6.5)
		var hgt := rng.randf_range(2.6, 3.8)
		c.y = height_at(c.x, c.z) + hgt * 0.5 - 0.3
		g.box("moss_rock", c, Vector3(1.1, hgt, 0.7), 0.08, Basis(Vector3.UP, -a).rotated(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP), rng.randf_range(-0.08, 0.08)))
	g.box("moss_rock", Vector3(st.x, height_at(st.x, st.y) + 0.4, st.y), Vector3(2.2, 0.8, 1.2), 0.08)
	# -- tree clusters and outcrops
	for cd in dress.clusters:
		var cl: Dictionary = cd
		var cp: Vector2 = cl.p
		for k in int(cl.n):
			var a := rng.randf_range(0.0, TAU)
			var rr := sqrt(rng.randf()) * float(cl.r)
			var p := Vector3(cp.x + cos(a) * rr, 0.0, cp.y + sin(a) * rr)
			p.y = height_at(p.x, p.z)
			var ti := rng.randf_range(0.8, 1.1)
			if rng.randf() < 0.55:
				HHGenUtil.conifer(g, "conifer", "bark", p, rng.randf_range(7.0, 12.0), rng.randf_range(1.6, 2.6), Color(ti, ti, ti))
			else:
				HHGenUtil.broadleaf(g, "leaf_young" if rng.randf() < 0.5 else "leaf_shade", "bark", p, rng.randf_range(6.0, 9.0), rng.randf_range(3.0, 4.2), rng, Color(ti, ti, ti), 4)
	for od in dress.outcrops:
		var o: Dictionary = od
		var op: Vector2 = o.p
		for k in int(o.n):
			var a := rng.randf_range(0.0, TAU)
			var rr := rng.randf_range(0.0, float(o.r))
			var rad := rng.randf_range(1.2, 2.6)
			var c := Vector3(op.x + cos(a) * rr, 0.0, op.y + sin(a) * rr)
			c.y = height_at(c.x, c.z) + rad * 0.3
			g.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c))
			g.sphere("moss_rock", Vector3.ZERO, rad, 6, Vector3(1.2, rng.randf_range(0.7, 1.2), 0.9))
			g.pop()
	# -- the region's edge: a forest wall on the hills just past the playable square
	var half := HHHuntKit.t("map_span_m") * 0.5
	for k in 260:
		var u := float(k) / 260.0 * 4.0                # walk the square's perimeter
		var side_i := int(u)
		var f := (u - float(side_i)) * 2.0 - 1.0
		var out := half + 6.0 + rng.randf_range(0.0, 22.0)
		var along := f * (half + 20.0)
		var p := Vector2.ZERO
		match side_i:
			0: p = Vector2(along, -out)
			1: p = Vector2(out, along)
			2: p = Vector2(-along, out)
			_: p = Vector2(-out, -along)
		var base := Vector3(p.x, height_at(p.x, p.y), p.y)
		var ti := rng.randf_range(0.7, 1.05)
		if rng.randf() < 0.7:
			HHGenUtil.conifer(g, "conifer", "bark", base, rng.randf_range(10.0, 17.0), rng.randf_range(2.2, 3.4), Color(ti, ti, ti))
		else:
			HHGenUtil.broadleaf(g, "leaf_shade", "bark", base, rng.randf_range(8.0, 12.0), rng.randf_range(3.6, 5.0), rng, Color(ti, ti, ti), 4)
	var mi := MeshInstance3D.new()
	mi.name = "Landmarks"
	mi.mesh = g.commit()
	GKMaterials.apply(mi)
	add_child(mi)


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
		camera.follow(hunter.position)
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
		camera.follow(hunter.position, true)


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
