class_name HHPondGen
extends GKDef
## The Shallow Lilypad Pond (kickoff Lane D: "a nice shallow lake easily
## walkable; lilypads decorate the arena, a beautiful sunny day in the
## background. Add some flowers and such. Maybe a lilypad or two to hide
## behind"). One seeded layout feeds two outputs that must agree:
##   arena(p)  -> HHArena   the logical underlay (cells, heightfield, spawns)
##   build(p)  -> GKAsset   the look (bed, water, pads, reeds, flowers, trees)
##
## Water level is y = 0. The heightfield is the pond BED, so a water cell's
## hex height is below the surface and `depth` is how far (H201). The player
## wades where depth <= DEEP_M; deeper is "deep": unwalkable, the monster's
## dive pools (H202). Lilypad hexes ("pad") are walkable whatever the depth
## under them, so a pad over a pool is a stepping stone; `cover` marks the
## tall rolled pads you can hide behind (H203).
##
## Roles: ROLES below are the pond's own material roles in GKMaterials.ROLES
## shape (Request: merge them). Until merged, role() maps each to an existing
## role so renders work today.

const DEEP_M := 0.6             ## water deeper than this is unwalkable
const SKIRT_M := 12.0           ## scenery beyond the floor (HHArena.skirt_m)
const EDGE_M := 1.8             ## H17 edge band width
const HF_STEP := 1.0            ## heightfield step (m); hole-scale relief needs it finer than round_flat's 3 m
const HOLES := 3                ## dive pools

const ROLES := {
	"pond_bed": { "a": "#9c8a62", "b": "#7e6d4a", "c": "#6a5a3c", "rough": 0.95, "pat": "stipple", "scale": 1.5, "amt": 0.4, "world": true },
	"water_shallow": { "a": "#2f6f8e", "b": "#285f7a", "rough": 0.08, "spec": 1.0, "pat": "plain", "scale": 2.0, "amt": 0.1, "world": true, "alpha": 0.45 },
	"lilypad": { "a": "#4f8a2e", "b": "#3a6a22", "c": "#7aa43a", "rough": 0.7, "spec": 0.5, "pat": "grass", "scale": 1.6, "amt": 0.3, "world": true },
	"lilypad_tall": { "a": "#3f7a2a", "b": "#2c5a1e", "c": "#6a9a3a", "rough": 0.75, "pat": "grass", "scale": 1.6, "amt": 0.3, "world": true },
	"reed": { "a": "#6f8a3a", "b": "#55702a", "c": "#8aa44a", "rough": 0.9, "pat": "plain", "scale": 2.0, "amt": 0.2, "world": true },
	"cattail": { "a": "#5a3e26", "b": "#3e2a18", "rough": 0.95, "pat": "stipple", "scale": 40.0, "amt": 0.3, "world": true },
	"pond_flower": { "a": "#e8c020", "b": "#c89a10", "c": "#f2d84a", "rough": 0.8, "pat": "plain", "scale": 4.0, "amt": 0.2, "world": true },
	"meadow_grass": { "a": "#7a9a3e", "b": "#5e7e30", "c": "#9ab050", "rough": 1.0, "pat": "grass", "scale": 0.35, "amt": 0.45, "world": true },
}
## role -> existing GKMaterials role used until ROLES is merged
const FALLBACK := {
	"pond_bed": "sandstone_trim:#8a7650",
	"water_shallow": "polymer_clear:#2a78a8",
	"lilypad": "foliage",
	"lilypad_tall": "hedge",
	"reed": "foliage",
	"cattail": "wood_old",
	"pond_flower": "foliage_gold",
	"meadow_grass": "grass",
}


static func role(name: String) -> String:
	if GKMaterials.has(name):
		return name
	return str(FALLBACK.get(name, name))


func id() -> String:
	return "pond"


func title() -> String:
	return "Shallow Lilypad Pond"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pi("seed", "Seed", "Layout", 1, 1, 99999),
		pf("radius_m", "Floor radius (m)", "Layout", 25.0, 15.0, 30.0, 0.5),
		pf("shore_width", "Shore width (m)", "Layout", 5.0, 2.5, 10.0, 0.5),
		pf("water_depth", "Pool depth (m)", "Water", 0.9, 0.0, 1.2, 0.05),
		pf("bumps", "Bed relief", "Water", 0.3, 0.0, 1.0, 0.05),
		pi("lilypad_count", "Lilypads", "Pads", 60, 0, 200),
		pf("lilypad_cover", "Tall cover pads (fraction)", "Pads", 0.08, 0.0, 1.0, 0.01),
		pf("flower_density", "Flowers", "Dressing", 0.4, 0.0, 1.0, 0.05),
		pf("grass_height", "Grass height (m)", "Dressing", 0.5, 0.0, 1.5, 0.05),
	]


func presets() -> Dictionary:
	return {
		"default": {},
		"sparse": { "lilypad_count": 25, "lilypad_cover": 0.08, "flower_density": 0.15, "grass_height": 0.35, "bumps": 0.2 },
		"dense": { "lilypad_count": 120, "lilypad_cover": 0.15, "flower_density": 0.9, "grass_height": 0.8, "bumps": 0.45 },
	}


# ------------------------------------------------------------------ layout
## Everything seeded, in one fixed draw order, so arena() and _build() agree.

static func layout(q: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(q.seed)
	var R: float = q.radius_m
	var shore: float = q.shore_width
	var r_lake: float = R - shore
	var depth_max: float = q.water_depth
	var base: float = minf(0.35, depth_max * 0.4)
	# shoreline wobble: three harmonics, never more than a third of the shore
	var wob: Array = []
	var amps: Array = [1.2, 0.9, 0.5]
	var ks: Array = [2, 3, 5]
	for i in 3:
		wob.append({ "k": int(ks[i]), "a": float(amps[i]) * rng.randf_range(0.5, 1.0) * minf(1.0, shore / 5.0), "ph": rng.randf_range(0.0, TAU) })
	# dive pools
	var holes: Array = []
	var th0 := rng.randf_range(0.0, TAU)
	for i in HOLES:
		var th := th0 + TAU * float(i) / float(HOLES) + rng.randf_range(-0.4, 0.4)
		var rr := rng.randf_range(4.0, maxf(5.0, r_lake - 7.0))
		holes.append({ "x": cos(th) * rr, "z": sin(th) * rr, "s": rng.randf_range(2.2, 3.2) })
	# bed relief blobs
	var blobs: Array = []
	for i in 6:
		blobs.append({ "x": rng.randf_range(-R, R), "z": rng.randf_range(-R, R), "s": rng.randf_range(3.0, 6.0), "a": rng.randf_range(-0.25, 0.25) * float(q.bumps) })
	var L := { "R": R, "shore": shore, "r_lake": r_lake, "depth_max": depth_max, "base": base, "wob": wob, "holes": holes, "blobs": blobs }
	# the player starts on the south shore, the monster at the pool farthest from them
	var ps_r := lake_radius(L, PI * 0.5) + 1.0
	var player_pos := Vector2(0.0, ps_r)
	L["player_pos"] = player_pos
	var best := 0
	var best_d := -1.0
	for i in holes.size():
		var h: Dictionary = holes[i]
		var d := Vector2(float(h.x), float(h.z)).distance_to(player_pos)
		if d > best_d:
			best_d = d
			best = i
	L["monster_hole"] = best
	# lilypads: big ones snap to a hex (walkable), small ones are dressing
	var pads: Array = []
	var want: int = int(q.lilypad_count)
	var tries := 0
	while pads.size() < want and tries < want * 30 + 30:
		tries += 1
		var big := rng.randf() < 0.55
		var rad := rng.randf_range(0.72, 0.98) if big else rng.randf_range(0.3, 0.6)
		var a := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (r_lake - 1.5)
		var x := cos(a) * rr
		var z := sin(a) * rr
		var notch := rng.randf_range(0.0, TAU)
		var tint := rng.randf_range(0.8, 1.1)
		if rr > lake_radius(L, a) - 2.0:
			continue
		if big:
			var hx := HHHex.from_world(Vector2(x, z), HHArena.HEX)
			var w := HHHex.to_world(hx, HHArena.HEX)
			x = w.x
			z = w.y
			if -bed_height(L, x, z) < 0.12:
				continue
		if Vector2(x, z).distance_to(player_pos) < 3.0:
			continue
		var clash := false
		for o in pads:
			var od: Dictionary = o
			if Vector2(x, z).distance_to(Vector2(float(od.x), float(od.z))) < rad + float(od.r) + 0.35:
				clash = true
				break
		if clash:
			continue
		pads.append({ "x": x, "z": z, "r": rad, "big": big, "notch": notch, "tint": tint, "tall": false })
	# tall cover pads: a fraction of the big ones, in draw order
	var big_idx: Array = []
	for i in pads.size():
		if bool((pads[i] as Dictionary).big):
			big_idx.append(i)
	var n_tall := int(ceil(float(q.lilypad_cover) * float(big_idx.size()) - 1e-6))
	for i in mini(n_tall, big_idx.size()):
		(pads[int(big_idx[i])] as Dictionary)["tall"] = true
	L["pads"] = pads
	# water flowers (yellow pond lilies), shore flowers, reeds, grass, trees, boulders
	var wf: Array = []
	for i in int(round(float(q.flower_density) * 70.0)):
		var a := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (r_lake - 2.0)
		if rr > lake_radius(L, a) - 2.5:
			continue
		wf.append({ "x": cos(a) * rr, "z": sin(a) * rr, "r": rng.randf_range(0.12, 0.2), "hue": rng.randf() })
	L["water_flowers"] = wf
	var sf: Array = []
	for i in int(round(float(q.flower_density) * 110.0)):
		var a := rng.randf_range(0.0, TAU)
		var rr := lake_radius(L, a) + rng.randf_range(1.0, maxf(1.5, shore + 4.0))
		sf.append({ "x": cos(a) * rr, "z": sin(a) * rr, "h": rng.randf_range(0.25, 0.5), "hue": rng.randf() })
	L["shore_flowers"] = sf
	var reeds: Array = []
	for i in 44:
		var a := rng.randf_range(0.0, TAU)
		var rr := lake_radius(L, a) + rng.randf_range(-0.9, 1.0)
		var stems: Array = []
		for k in rng.randi_range(4, 7):
			stems.append({ "dx": rng.randf_range(-0.35, 0.35), "dz": rng.randf_range(-0.35, 0.35), "h": rng.randf_range(1.0, 1.9),
				"lean": rng.randf_range(-0.2, 0.2), "head": rng.randf() < 0.4 })
		reeds.append({ "x": cos(a) * rr, "z": sin(a) * rr, "stems": stems })
	L["reeds"] = reeds
	var tufts: Array = []
	for i in 520:
		var a := rng.randf_range(0.0, TAU)
		var rr := lake_radius(L, a) + rng.randf_range(0.6, shore + 7.0) * sqrt(rng.randf())
		tufts.append({ "x": cos(a) * rr, "z": sin(a) * rr, "h": rng.randf_range(0.5, 1.3), "tint": rng.randf_range(0.8, 1.15) })
	L["tufts"] = tufts
	var trees: Array = []
	for i in 22:
		var a := TAU * float(i) / 22.0 + rng.randf_range(-0.1, 0.1)
		var rr := R + rng.randf_range(3.5, 9.5)
		trees.append({ "x": cos(a) * rr, "z": sin(a) * rr, "h": rng.randf_range(5.0, 8.0), "w": rng.randf_range(1.8, 2.8), "tint": rng.randf_range(0.85, 1.1) })
	L["trees"] = trees
	var rocks: Array = []
	for i in 7:
		var a := rng.randf_range(0.0, TAU)
		var rr := lake_radius(L, a) + rng.randf_range(0.5, shore + 3.0)
		rocks.append({ "x": cos(a) * rr, "z": sin(a) * rr, "r": rng.randf_range(0.35, 0.8), "sq": rng.randf_range(0.5, 0.8), "rot": rng.randf_range(0.0, TAU) })
	L["rocks"] = rocks
	return L


## The shoreline radius at angle `th` (the lake is a wobbled disc).
static func lake_radius(L: Dictionary, th: float) -> float:
	var r: float = L.r_lake
	for w in L.wob:
		var wd: Dictionary = w
		r += float(wd.a) * sin(float(wd.k) * th + float(wd.ph))
	return r


## 1 inside the lake, 0 on the shore, blended over 1.5 m.
static func lake_mask(L: Dictionary, x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var rl := lake_radius(L, atan2(z, x))
	return 1.0 - smoothstep(rl - 1.0, rl + 0.5, r)


## Bed height (water level is 0): pools dip, shore rises, skirt bowls up.
static func bed_height(L: Dictionary, x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var th := atan2(z, x)
	var rl := lake_radius(L, th)
	var lake := 1.0 - smoothstep(rl - 1.0, rl + 0.5, r)
	var depth: float = L.base
	for h in L.holes:
		var hd: Dictionary = h
		var dx := x - float(hd.x)
		var dz := z - float(hd.z)
		var s := float(hd.s)
		depth += (float(L.depth_max) - float(L.base)) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
	depth = minf(depth, float(L.depth_max))
	var bump := 0.0
	for b in L.blobs:
		var bd: Dictionary = b
		var dx := x - float(bd.x)
		var dz := z - float(bd.z)
		var s := float(bd.s)
		bump += float(bd.a) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
	var h := -depth * lake + bump * (0.3 + 0.7 * (1.0 - lake))
	var R: float = L.R
	if r > rl:
		h += clampf((r - rl) / maxf(float(L.shore), 1.0), 0.0, 1.0) * 0.3
	if r > R:
		h += (r - R) * 0.55
	return h


# ------------------------------------------------------------------ arena

static func _validated(p: Dictionary) -> Dictionary:
	return HHPondGen.new().validate(p)


## The logical underlay for these params. Cells: "water" (depth, walkable
## while depth <= DEEP_M), "pad" (walkable, cover flag), "floor" (shore),
## "edge" (H17). Heightfield = the bed, from the same seed.
static func arena(p: Dictionary) -> HHArena:
	var q := _validated(p)
	var L := layout(q)
	var a := HHArena.new()
	a.id = "pond"
	a.seed = int(q.seed)
	a.radius_m = float(q.radius_m)
	a.skirt_m = SKIRT_M
	var reach := a.radius_m + a.skirt_m
	var n := int(ceil(2.0 * reach / HF_STEP)) + 2
	var origin := -reach - HF_STEP
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			data[j * n + i] = bed_height(L, origin + i * HF_STEP, origin + j * HF_STEP)
	a.hf = { "cols": n, "rows": n, "step": HF_STEP, "origin": [origin, origin], "data": data }
	a._lay_cells()
	for key in a.cells:
		var h: Vector2i = key
		var c: Dictionary = a.cells[h]
		var w := HHHex.to_world(h, HHArena.HEX)
		var d := maxf(0.0, -a.hex_height(h)) * (1.0 if lake_mask(L, w.x, w.y) > 0.05 else 0.0)
		if d <= 0.04:
			d = 0.0                      # a damp hex is shore, not water
		c.depth = d
		if str(c.kind) == "edge":
			continue
		if d > 0.0:
			c.kind = "water"
			c.walkable = d <= DEEP_M
	for pd in L.pads:
		var pad: Dictionary = pd
		if not bool(pad.big):
			continue
		var h := HHHex.from_world(Vector2(float(pad.x), float(pad.z)), HHArena.HEX)
		if not a.cells.has(h) or str((a.cells[h] as Dictionary).kind) == "edge":
			continue
		var c: Dictionary = a.cells[h]
		c.kind = "pad"
		c.walkable = true
		c["cover"] = bool(pad.tall)
	# spawns: player on the south shore, monster on the rim of the far pool
	var pp: Vector2 = L.player_pos
	var ph := _nearest_walkable_hex(a, HHHex.from_world(pp, HHArena.HEX))
	var hole: Dictionary = L.holes[int(L.monster_hole)]
	var hh := HHHex.from_world(Vector2(float(hole.x), float(hole.z)), HHArena.HEX)
	var mh := hh
	var best := -1
	for cand in a.area(hh, 5):
		if not a.walkable(cand) or a.kind(cand) == "pad":
			continue
		var score := HHHex.distance(cand, ph) * 10 - HHHex.distance(cand, hh)
		if score > best and not a.path(ph, cand).is_empty():
			best = score
			mh = cand
	if best < 0:
		mh = _nearest_walkable_hex(a, hh)
	a.spawns = { "player": [ph], "monster": mh }
	return a


static func _nearest_walkable_hex(a: HHArena, from: Vector2i) -> Vector2i:
	if a.walkable(from):
		return from
	for r in range(1, 8):
		for h in HHHex.ring(from, r):
			if a.walkable(h):
				return h
	return from


## Hexes flagged as cover (tall pads); HHArena.to_dict drops the flag, so
## the JSON export carries this list beside it (Request: keep `cover` in core).
static func cover_hexes(a: HHArena) -> Array:
	var out: Array = []
	var keys := a.cells.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = a.cells[k]
		if bool(c.get("cover", false)):
			out.append([(k as Vector2i).x, (k as Vector2i).y])
	return out


## Both outputs of one param set.
static func build_both(p: Dictionary) -> Dictionary:
	var g := HHPondGen.new()
	return { "arena": arena(p), "asset": g.build(p) }


## What arenas/pond.json holds: the arena plus how to rebuild it.
static func export_dict(p: Dictionary) -> Dictionary:
	var q := _validated(p)
	var a := arena(q)
	var d := a.to_dict()
	d["cover"] = cover_hexes(a)
	d["gen"] = { "id": "pond", "version": 1, "params": q }
	return d


static func export_json(p: Dictionary, path: String = "res://arenas/pond.json") -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("HHPondGen: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(export_dict(p)))
	f.close()
	return true


# ------------------------------------------------------------------ asset

func _build(q: Dictionary) -> GKAsset:
	var asset := GKAsset.new()
	var L := layout(q)
	var a := arena(q)
	var R: float = q.radius_m
	# -- bed: the heightfield as quads, roles by region
	var g := GKMesh.new()
	var hf: Dictionary = a.hf
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var ox: float = hf.origin[0]
	var oz: float = hf.origin[1]
	var bed_role := role("pond_bed")
	var grass_role := role("meadow_grass")
	for j in rows - 1:
		for i in cols - 1:
			var x0 := ox + i * step
			var z0 := oz + j * step
			var cx := x0 + step * 0.5
			var cz := z0 + step * 0.5
			var r := sqrt(cx * cx + cz * cz)
			var rl := lake_radius(L, atan2(cz, cx))
			var rname := bed_role if r < rl - 0.3 else grass_role
			if r < rl - 0.3:
				# the bed goes blue-green and dark with depth, so the pools read through the sheet
				var deep_t := clampf(-a.height_at(cx, cz) / maxf(float(q.water_depth), 0.1), 0.0, 1.0)
				g.tint = Color(0.85, 0.92, 0.9).lerp(Color(0.1, 0.22, 0.36), pow(deep_t, 1.4))
			else:
				# the meadow darkens into the tree line instead of switching role on a jagged ring
				g.tint = Color.WHITE.lerp(Color(0.55, 0.62, 0.45), clampf((r - R - 3.0) / 8.0, 0.0, 1.0))
			g.quad(rname, Vector3(x0, a.height_at(x0, z0), z0), Vector3(x0 + step, a.height_at(x0 + step, z0), z0),
				Vector3(x0 + step, a.height_at(x0 + step, z0 + step), z0 + step), Vector3(x0, a.height_at(x0, z0 + step), z0 + step))
	g.tint = Color.WHITE
	var bed := g.commit()
	asset.add_part("bed", bed)
	asset.add_trimesh_collider(bed)
	# -- water: a see-through sheet at y = 0, fanned to follow the shoreline
	var wg := GKMesh.new()
	var segs := 96
	var wr := role("water_shallow")
	for k in segs:
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var r0 := lake_radius(L, a0) + 0.6
		var r1 := lake_radius(L, a1) + 0.6
		# two rings so the sheet has a few more vertices for the clear shader's grazing term
		var m0 := r0 * 0.5
		var m1 := r1 * 0.5
		wg.tri(wr, Vector3.ZERO, Vector3(cos(a0) * m0, 0, sin(a0) * m0), Vector3(cos(a1) * m1, 0, sin(a1) * m1), Vector3.UP, Vector3.UP, Vector3.UP)
		wg.quad(wr, Vector3(cos(a0) * m0, 0, sin(a0) * m0), Vector3(cos(a0) * r0, 0, sin(a0) * r0),
			Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a1) * m1, 0, sin(a1) * m1), [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	asset.add_part("water", wg.commit(), Transform3D.IDENTITY, false)
	# -- lilypads
	var pg := GKMesh.new()
	var pad_role := role("lilypad")
	var tall_role := role("lilypad_tall")
	for pd in L.pads:
		var pad: Dictionary = pd
		var c := Vector3(float(pad.x), 0.03, float(pad.z))
		pg.tint = Color(float(pad.tint), 1.0, float(pad.tint) * 0.95)
		_pad(pg, pad_role, c, float(pad.r), float(pad.notch))
		if bool(pad.tall):
			_tall_pad(pg, tall_role, c, float(pad.r), float(pad.notch))
	pg.tint = Color.WHITE
	asset.add_part("lilypads", pg.commit())
	# -- flowers: yellow pond lilies on the water, mixed blooms on the shore
	var fg := GKMesh.new()
	var fl := role("pond_flower")
	for wfd in L.water_flowers:
		var f: Dictionary = wfd
		var c := Vector3(float(f.x), 0.06, float(f.z))
		fg.tint = Color(1.0, 0.95, 0.7) if float(f.hue) < 0.7 else Color(1.0, 1.0, 1.0)
		_pad(fg, pad_role, c - Vector3(0, 0.03, 0), float(f.r) * 1.6, 0.0)
		_bloom(fg, fl, c, float(f.r))
	for sfd in L.shore_flowers:
		var f: Dictionary = sfd
		var y := a.height_at(float(f.x), float(f.z))
		var base := Vector3(float(f.x), y, float(f.z))
		var top := base + Vector3(0, float(f.h), 0)
		fg.tint = Color.WHITE
		fg.tube(role("reed"), [base, top], [0.015, 0.012], 4, false)
		var hue: float = f.hue
		var brole := fl if hue < 0.45 else ("sign_white" if hue < 0.75 else "sign_red")
		fg.tint = Color.WHITE
		fg.sphere(brole, top, 0.08, 6, Vector3(1.0, 0.6, 1.0))
	fg.tint = Color.WHITE
	asset.add_part("flowers", fg.commit())
	# -- reeds at the waterline, cattail heads on some
	var rg := GKMesh.new()
	var reed_role := role("reed")
	var head_role := role("cattail")
	for rd in L.reeds:
		var cl: Dictionary = rd
		for sd in cl.stems:
			var s: Dictionary = sd
			var x := float(cl.x) + float(s.dx)
			var z := float(cl.z) + float(s.dz)
			var y := a.height_at(x, z)
			var h := float(s.h)
			var base := Vector3(x, y, z)
			var top := Vector3(x + float(s.lean) * h, y + h, z + float(s.lean) * 0.5 * h)
			rg.tint = Color(0.9, 1.0, 0.8)
			rg.tube(reed_role, [base, base.lerp(top, 0.5), top], [0.035, 0.025, 0.008], 5, false)
			if bool(s.head):
				rg.tint = Color.WHITE
				rg.cyl(head_role, top - Vector3(0, 0.22, 0), top - Vector3(0, 0.02, 0), 0.045, 6)
	rg.tint = Color.WHITE
	asset.add_part("reeds", rg.commit())
	# -- grass tufts on the shore and the skirt
	var gh: float = q.grass_height
	if gh > 0.0:
		var tg := GKMesh.new()
		var tuft_role := "hedge"
		for td in L.tufts:
			var t: Dictionary = td
			var x := float(t.x)
			var z := float(t.z)
			var y := a.height_at(x, z) - 0.02
			var h := gh * float(t.h)
			var ti := float(t.tint)
			tg.tint = Color(ti, ti, ti * 0.9)
			for b in 3:
				var ba := TAU * float(b) / 3.0 + float(t.h)
				var bx := x + cos(ba) * 0.14
				var bz := z + sin(ba) * 0.14
				var bh := h * (0.7 + 0.3 * float(b) / 2.0)
				tg.tube(tuft_role, [Vector3(bx, y, bz), Vector3(bx + cos(ba) * 0.12, y + bh, bz + sin(ba) * 0.12)], [0.13, 0.0], 4, false)
		tg.tint = Color.WHITE
		asset.add_part("grass", tg.commit())
	# -- a ring of trees on the bowl, a few boulders on the shore
	var sg := GKMesh.new()
	for trd in L.trees:
		var t: Dictionary = trd
		var x := float(t.x)
		var z := float(t.z)
		var y := a.height_at(x, z) - 0.3
		var h := float(t.h)
		var w := float(t.w)
		var ti := float(t.tint)
		sg.tint = Color.WHITE
		sg.cyl("bark", Vector3(x, y, z), Vector3(x, y + h * 0.4, z), 0.28, 7)
		sg.tint = Color(ti, ti, ti)
		sg.tube("foliage", [Vector3(x, y + h * 0.3, z), Vector3(x, y + h * 0.75, z)], [w, 0.0], 8, true)
		sg.tube("hedge", [Vector3(x, y + h * 0.55, z), Vector3(x, y + h, z)], [w * 0.75, 0.0], 8, true)
	sg.tint = Color.WHITE
	for rkd in L.rocks:
		var rk: Dictionary = rkd
		var x := float(rk.x)
		var z := float(rk.z)
		var y := a.height_at(x, z)
		sg.sphere("stone_grey", Vector3(x, y + float(rk.r) * float(rk.sq) * 0.6, z), float(rk.r), 10, Vector3(1.0, float(rk.sq), 0.85))
	asset.add_part("scenery", sg.commit())
	# -- markers
	var ps := a.world(a.spawns.player[0])
	var ms := a.world(a.spawns.monster)
	asset.markers["spawn_player"] = Transform3D(Basis.looking_at((Vector3(ms.x, 0, ms.z) - Vector3(ps.x, 0, ps.z)).normalized(), Vector3.UP), ps)
	asset.markers["spawn_monster"] = Transform3D(Basis.looking_at((Vector3(ps.x, 0, ps.z) - Vector3(ms.x, 0, ms.z)).normalized(), Vector3.UP), ms)
	var cam_pos := Vector3(0.0, R * 0.95, R + 15.0)
	var cam_at := Vector3(0.0, 0.0, -R * 0.1)
	asset.markers["ref_cam"] = Transform3D(Basis.looking_at(cam_at - cam_pos, Vector3.UP), cam_pos)   # Camera3D.transform = this looks at the pond
	# -- a sunny day
	asset.lights = { "sun_dir_deg": [-55.0, 32.0], "sun_energy": 1.5, "sun_color": "#fff3dc",
		"sky_top": "#3f82de", "sky_horizon": "#d2e6f6", "ground_horizon": "#9fb27c", "ground_bottom": "#4a5a38", "ambient": 1.0 }
	asset.meta = { "deep_m": DEEP_M, "water_level": 0.0, "lake_radius": L.r_lake, "pads": L.pads.size(), "cover": cover_hexes(a).size(),
		"walkable": a.walkable_count(), "cells": a.cells.size() }
	if a.path(a.spawns.player[0], a.spawns.monster).is_empty():
		asset.warnings.append("no path from the player spawn to the monster spawn")
	return asset


## A lilypad: a flat disc with a V notch, its rim turned up a touch.
static func _pad(g: GKMesh, r_role: String, c: Vector3, rad: float, notch: float) -> void:
	var segs := 14
	var half := 0.32            # the notch half angle (rad)
	var inner := rad * 0.78
	var lift := rad * 0.05
	var th := 0.025
	var pts_in: Array[Vector3] = []
	var pts_out: Array[Vector3] = []
	for k in segs + 1:
		var a := notch + half + (TAU - 2.0 * half) * float(k) / float(segs)
		pts_in.append(c + Vector3(cos(a) * inner, 0.0, sin(a) * inner))
		pts_out.append(c + Vector3(cos(a) * rad, lift, sin(a) * rad))
	for k in segs:
		# top: fan from the centre to the inner ring, then the lifted rim
		g.tri(r_role, c, pts_in[k], pts_in[k + 1], Vector3.UP, Vector3.UP, Vector3.UP)
		g.quad(r_role, pts_in[k], pts_out[k], pts_out[k + 1], pts_in[k + 1])
		# underside (faces down, hidden from above but closes the pad at grazing angles)
		var dn := Vector3(0, -th, 0)
		g.tri(r_role, c + dn, pts_in[k + 1] + dn, pts_in[k] + dn, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
		g.quad(r_role, pts_in[k + 1] + dn, pts_out[k + 1] + dn, pts_out[k] + dn, pts_in[k] + dn)
		# rim side
		g.quad(r_role, pts_out[k], pts_out[k] + dn, pts_out[k + 1] + dn, pts_out[k + 1])
	# the notch walls
	var dn2 := Vector3(0, -th, 0)
	g.quad(r_role, c, c + dn2, pts_out[0] + dn2, pts_out[0])
	g.quad(r_role, pts_out[segs], pts_out[segs] + dn2, c + dn2, c)


## A tall rolled leaf standing on the pad's far rim: cover to hide behind.
static func _tall_pad(g: GKMesh, r_role: String, c: Vector3, rad: float, notch: float) -> void:
	var back := notch + PI
	var foot := c + Vector3(cos(back) * rad * 0.45, 0.0, sin(back) * rad * 0.45)
	var h := 1.7
	var pts: Array = [foot, foot + Vector3(cos(back) * 0.15, h * 0.45, sin(back) * 0.15), foot + Vector3(cos(back) * 0.35, h * 0.8, sin(back) * 0.35),
		foot + Vector3(cos(back) * 0.6, h, sin(back) * 0.6)]
	g.tube(r_role, pts, [0.55, 0.5, 0.36, 0.1], 10, true, Vector3.UP, 0.55)
	# a second, shorter curl beside it
	var side := back + 0.9
	var foot2 := c + Vector3(cos(side) * rad * 0.55, 0.0, sin(side) * rad * 0.55)
	g.tube(r_role, [foot2, foot2 + Vector3(cos(side) * 0.2, h * 0.6, sin(side) * 0.2)], [0.35, 0.08], 8, true, Vector3.UP, 0.55)
	# a closed pink bud on the main curl's tip
	var tip: Vector3 = pts[3]
	g.tint = Color(1.0, 0.85, 0.9)
	g.sphere("sign_red:#e07a9a", tip + Vector3(0, 0.12, 0), 0.17, 8, Vector3(0.8, 1.3, 0.8))


## A pond-lily bloom: a squashed sphere with a few petal fins.
static func _bloom(g: GKMesh, r_role: String, c: Vector3, rad: float) -> void:
	g.sphere(r_role, c + Vector3(0, rad * 0.5, 0), rad, 8, Vector3(1.0, 0.75, 1.0))
	for k in 5:
		var a := TAU * float(k) / 5.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var p0 := c + d * rad * 0.4
		var p1 := c + d * rad * 1.5 + Vector3(0, rad * 0.5, 0)
		g.tube(r_role, [p0, p1], [rad * 0.25, 0.0], 4, false)
