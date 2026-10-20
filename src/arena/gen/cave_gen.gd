class_name HHCaveGen
extends GKDef
## The Cave (kickoff Lane D: "plenty of elevation changes, no ceiling is
## fine. Noticeably dark. Plenty of rocks and pillars as obstacles"; Lane C:
## "destructible rock pillars"). Rimeslithe's arena (H10): shade cells in the
## cold corners. One seeded layout feeds arena(p) and build(p) (H200 pattern).
##
## Elevation: the floor is hex-terraced. Every hex has a terrace level (a
## smooth seeded field quantised to `terraces` levels, STEP_M apart, which is
## more than HHTune max_step_m, so a terrace edge is a cliff). A ramp is one
## hex set to a half level: two 0.7 m steps instead of one 1.4 m cliff, and
## the mesh slopes across that hex. Ramps are added by a deterministic repair
## pass until the player can reach at least REACH_TARGET of the walkable
## floor, plus a few seeded extra ramps for alternative routes (H209).
##
## Cells: "floor", "edge" (H17), "rock" (boulder, impassable, no charge),
## "pillar" (stalagmite column, impassable, `hp` and `kind_after: "floor"`),
## "shade" (walkable, authored water 1 + glaze: Rimeslithe chills there).
## Authored rows go to arena.spawns["authored"] (HHGenUtil).
##
## Roles: ROLES below in GKMaterials.ROLES shape (Request: merge); role()
## falls back to existing roles with colour overrides until then.

const STEP_M := 1.4             ## terrace rise; > max_step_m (1.0) so a terrace edge is a cliff
const RAMP_M := STEP_M * 0.5    ## a ramp hex sits halfway: two steps of 0.7
const SKIRT_M := 8.0            ## cave walls rise steeply beyond the floor
const HF_STEP := 0.5            ## fine enough that a hex's own samples lie inside it (inradius 0.866)
const WALL_M := 22.0            ## wall height at the skirt's reach
const PILLAR_HP := 300.0        ## a stalagmite's hit points (kind_after "floor")
const REACH_TARGET := 0.92      ## the repair pass stops here
const MAX_REPAIRS := 24
const TORCHES := 6

const ROLES := {
	"cave_floor": { "a": "#4a4440", "b": "#3a3531", "c": "#5a534c", "rough": 0.95, "pat": "cobble", "scale": 0.6, "amt": 0.35, "world": true },
	"cave_wall": { "a": "#2e2b29", "b": "#232120", "c": "#3c3836", "rough": 0.95, "pat": "blocks", "scale": 0.9, "amt": 0.4, "world": true },
	"stalagmite": { "a": "#8c7d6a", "b": "#6f6254", "c": "#a69684", "rough": 0.85, "pat": "stipple", "scale": 1.2, "amt": 0.35, "world": true },
	"cave_boulder": { "a": "#555049", "b": "#433f3a", "c": "#67625a", "rough": 0.92, "pat": "blocks", "scale": 0.5, "amt": 0.35, "world": true },
	"frost": { "a": "#cfeaf2", "b": "#a9cfdd", "c": "#e8f6fa", "rough": 0.3, "spec": 0.9, "pat": "speckle", "scale": 2.0, "amt": 0.25, "world": true },
	"torch_flame": { "a": "#ffb040", "b": "#ff7a18", "c": "#fff0a0", "rough": 0.2, "pat": "plain", "scale": 4.0, "amt": 0.2 },
	"torch_post": { "a": "#4a3626", "b": "#352618", "rough": 0.95, "pat": "grain", "scale": 3.0, "amt": 0.4, "axis": [0, 1, 0] },
}
const FALLBACK := {
	"cave_floor": "pond_bed:#4a4440",
	"cave_wall": "pond_bed:#2e2b29",
	"stalagmite": "pond_bed:#8c7d6a",
	"cave_boulder": "pond_bed:#555049",
	"frost": "sign_white:#cfeaf2",
	"torch_flame": "orange_tip:#ffb040",
	"torch_post": "wood_old",
}


static func role(name: String) -> String:
	return HHGenUtil.role(FALLBACK, name)


func id() -> String:
	return "cave"


func title() -> String:
	return "Cave"


func kind() -> String:
	return "env"


func version() -> int:
	return 1


func schema() -> Array[Dictionary]:
	return [
		pi("seed", "Seed", "Layout", 1, 1, 99999),
		pf("radius_m", "Floor radius (m)", "Layout", 25.0, 15.0, 30.0, 0.5),
		pi("terraces", "Terrace levels", "Layout", 3, 1, 5),
		pi("pillar_count", "Pillars", "Obstacles", 12, 0, 40),
		pi("rock_count", "Rocks", "Obstacles", 16, 0, 60),
		pi("shade_count", "Shade corners", "Cells", 4, 0, 8),
		pf("darkness", "Darkness", "Light", 0.7, 0.0, 1.0, 0.05),
	]


func presets() -> Dictionary:
	return {
		"default": {},
		"open": { "terraces": 2, "pillar_count": 6, "rock_count": 8, "shade_count": 3, "darkness": 0.55 },
		"maze": { "terraces": 4, "pillar_count": 24, "rock_count": 30, "shade_count": 5, "darkness": 0.8 },
	}


static func _validated(p: Dictionary) -> Dictionary:
	return HHCaveGen.new().validate(p)


# ------------------------------------------------------------------ layout

## The continuous terrace field before scaling: a seeded tilt plus blobs.
static func _t_raw(L: Dictionary, x: float, z: float) -> float:
	var R: float = L.R
	var tilt: float = L.tilt
	var ang: float = L.tilt_ang
	return tilt * (cos(ang) * x + sin(ang) * z) / R + HHGenUtil.blobs_at(L.blobs, x, z)


## The terrace field scaled to [0, terraces].
static func t_at(L: Dictionary, x: float, z: float) -> float:
	return (_t_raw(L, x, z) - float(L.t_min)) / float(L.t_span) * float(L.terraces)


static func level_at(L: Dictionary, h: Vector2i) -> int:
	var w := HHHex.to_world(h, HHArena.HEX)
	return clampi(int(floor(t_at(L, w.x, w.y))), 0, int(L.terraces) - 1)


## Height (m) at a world point: the hex's terrace, a ramp hex's slope, the
## walls beyond the floor.
static func height(L: Dictionary, x: float, z: float) -> float:
	var R: float = L.R
	var r := sqrt(x * x + z * z)
	var hx := HHHex.from_world(Vector2(x, z), HHArena.HEX)
	var levels: Dictionary = L.levels
	var ramps: Dictionary = L.ramps
	var h: float
	if ramps.has(hx):
		var rp: Dictionary = ramps[hx]
		var c := HHHex.to_world(hx, HHArena.HEX)
		var dir: Vector2 = rp.dir
		var along := (Vector2(x, z) - c).dot(dir)
		h = float(rp.lo) * STEP_M + STEP_M * smoothstep(-0.8, 0.8, along)
	elif levels.has(hx):
		h = float(levels[hx]) * STEP_M
	else:
		h = float(clampi(int(floor(t_at(L, x, z))), 0, int(L.terraces) - 1)) * STEP_M
	if r > R:
		var u := (r - R) / float(L.skirt)
		h += pow(u, 1.5) * WALL_M + sin(atan2(z, x) * 9.0 + float(L.wall_ph)) * u * 1.5
	return h


## Every random number in one fixed order, so arena() and _build() agree.
static func layout(q: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(q.seed)
	var R: float = q.radius_m
	var T: int = int(q.terraces)
	var L := { "R": R, "terraces": T, "skirt": SKIRT_M }
	L["tilt_ang"] = rng.randf_range(0.0, TAU)
	L["tilt"] = rng.randf_range(0.6, 1.2)
	L["blobs"] = HHGenUtil.make_blobs(rng, 5, R, 7.0, 13.0, 0.9)
	L["wall_ph"] = rng.randf_range(0.0, TAU)
	# scale the field over the floor's hex centres
	var a := HHArena.new()
	a.id = "cave"
	a.seed = int(q.seed)
	a.radius_m = R
	a.skirt_m = SKIRT_M
	a._lay_cells()
	L["t_min"] = 0.0
	L["t_span"] = 1.0
	var lo := INF
	var hi := -INF
	for key in a.cells:
		var w := HHHex.to_world(key, HHArena.HEX)
		var t := _t_raw(L, w.x, w.y)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	L["t_min"] = lo
	L["t_span"] = maxf(hi - lo, 1e-3) * 1.0001
	var levels := {}
	var keys := a.cells.keys()
	keys.sort()
	for key in keys:
		levels[key] = level_at(L, key)
	L["levels"] = levels
	L["ramps"] = {}
	# obstacles on floor hexes away from the spawn hints
	var p_hint := Vector2(0.0, R * 0.72)
	var m_hint := Vector2(0.0, -R * 0.72)
	var avoid: Array = [HHHex.from_world(p_hint, HHArena.HEX), HHHex.from_world(m_hint, HHArena.HEX)]
	var floor_hexes := HHGenUtil.cells_of_kind(a, "floor")
	var pillars := HHGenUtil.pick_spaced(rng, floor_hexes, int(q.pillar_count), 3, avoid, 4)
	var taken: Array = avoid.duplicate()
	taken.append_array(pillars)
	var rocks := HHGenUtil.pick_spaced(rng, floor_hexes, int(q.rock_count), 2, taken, 2)
	for h in pillars:
		var c: Dictionary = a.cells[h]
		c.kind = "pillar"
		c.walkable = false
		c["hp"] = PILLAR_HP
		c["kind_after"] = "floor"
	for h in rocks:
		var c: Dictionary = a.cells[h]
		c.kind = "rock"
		c.walkable = false
	var pillar_look: Array = []
	for h in pillars:
		pillar_look.append({ "h": rng.randf_range(3.2, 5.6), "r": rng.randf_range(0.5, 0.72), "lean": rng.randf_range(-0.12, 0.12),
			"ph": rng.randf_range(0.0, TAU), "tint": rng.randf_range(0.85, 1.1) })
	L["pillar_look"] = pillar_look
	var rock_look: Array = []
	for h in rocks:
		rock_look.append({ "r": rng.randf_range(0.8, 1.05), "sq": rng.randf_range(0.55, 0.8), "rot": rng.randf_range(0.0, TAU), "tint": rng.randf_range(0.8, 1.1) })
	L["rock_look"] = rock_look
	# shade: clusters on the lowest terrace near the rim (cold air pools there)
	var cold: Array[Vector2i] = []
	for h in floor_hexes:
		if int(levels[h]) == 0 and str((a.cells[h] as Dictionary).kind) == "floor" and HHHex.to_world(h, HHArena.HEX).length() > R * 0.45:
			cold.append(h)
	if cold.size() < 12:
		cold = []
		for h in floor_hexes:
			if str((a.cells[h] as Dictionary).kind) == "floor" and HHHex.to_world(h, HHArena.HEX).length() > R * 0.45:
				cold.append(h)
	var shade_centres := HHGenUtil.pick_spaced(rng, cold, int(q.shade_count), 6, taken, 3)
	var shade: Array = []
	for sc in shade_centres:
		var n := rng.randi_range(2, 4)
		var ring := HHHex.ring(sc, 1)
		var cluster: Array = [sc]
		var start := rng.randi_range(0, 5)
		for i in 6:
			if cluster.size() > n:
				break
			var nb: Vector2i = ring[(start + i) % 6]
			if a.cells.has(nb) and str((a.cells[nb] as Dictionary).kind) == "floor" and int(levels[nb]) == int(levels[sc]):
				cluster.append(nb)
		for h in cluster:
			(a.cells[h] as Dictionary).kind = "shade"
			shade.append(h)
	L["shade"] = shade
	# ramps: repair until the floor is connected, then a few extra routes
	var ph := HHGenUtil.nearest_walkable_hex(a, HHHex.from_world(p_hint, HHArena.HEX))
	L["player_hint"] = p_hint
	L["monster_hint"] = m_hint
	HHGenUtil.fill_hf(a, func(x: float, z: float) -> float: return height(L, x, z), HF_STEP)
	var repairs := 0
	while repairs < MAX_REPAIRS and HHGenUtil.reach_fraction(a, ph) < REACH_TARGET:
		if not _add_ramp(L, a, rng, ph):
			break
		repairs += 1
		HHGenUtil.fill_hf(a, func(x: float, z: float) -> float: return height(L, x, z), HF_STEP)
	L["repairs"] = repairs
	var extra := 0
	for i in 3:
		if _add_ramp(L, a, rng, ph, true):
			extra += 1
	if extra > 0:
		HHGenUtil.fill_hf(a, func(x: float, z: float) -> float: return height(L, x, z), HF_STEP)
	L["extra_ramps"] = extra
	# torches on the rim, evenly spaced with a jitter
	var torches: Array = []
	for i in TORCHES:
		var ang := TAU * float(i) / float(TORCHES) + rng.randf_range(-0.25, 0.25)
		var rr := R - 1.0
		var x := cos(ang) * rr
		var z := sin(ang) * rr
		torches.append({ "x": x, "z": z, "h": rng.randf_range(1.6, 2.1) })
	L["torches"] = torches
	# wall spires on the skirt, pebbles on the floor
	var spires: Array = []
	for i in 36:
		var ang := TAU * float(i) / 36.0 + rng.randf_range(-0.08, 0.08)
		var rr := R + rng.randf_range(2.5, 6.5)
		spires.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "h": rng.randf_range(2.5, 6.5), "r": rng.randf_range(0.5, 1.1), "tint": rng.randf_range(0.7, 1.0) })
	L["spires"] = spires
	var pebbles: Array = []
	for i in 70:
		var ang := rng.randf_range(0.0, TAU)
		var rr := sqrt(rng.randf()) * (R - 2.5)
		pebbles.append({ "x": cos(ang) * rr, "z": sin(ang) * rr, "r": rng.randf_range(0.12, 0.3), "tint": rng.randf_range(0.7, 1.1) })
	L["pebbles"] = pebbles
	# spawns and authored charge
	HHGenUtil.pick_spawns(a, p_hint, m_hint, 10)
	var authored: Array = []
	for h in shade:
		authored.append(HHGenUtil.author_row(h, -1, 0, "", true))
	a.spawns["authored"] = authored
	L["arena"] = a
	return L


## One more ramp hex. Repair mode: the largest unreached component, a hex in
## it next to a reached hex one terrace away. Extra mode: any random boundary
## pair of walkable hexes one terrace apart that is not a ramp yet.
static func _add_ramp(L: Dictionary, a: HHArena, rng: RandomNumberGenerator, ph: Vector2i, extra: bool = false) -> bool:
	var levels: Dictionary = L.levels
	var ramps: Dictionary = L.ramps
	var seen := HHGenUtil.reach(a, ph)
	var cands: Array = []
	if extra:
		var keys := a.cells.keys()
		keys.sort()
		for key in keys:
			var h: Vector2i = key
			if not a.walkable(h) or ramps.has(h):
				continue
			for n in HHHex.neighbors(h):
				if a.walkable(n) and not ramps.has(n) and int(levels[n]) == int(levels[h]) - 1:
					cands.append({ "u": h, "r": n })
					break
	else:
		var unreached: Dictionary = {}
		for key in a.cells:
			if a.walkable(key) and not seen.has(key):
				unreached[key] = true
		# components of the unreached set, largest first
		var comps: Array = []
		var done := {}
		var ukeys := unreached.keys()
		ukeys.sort()
		for key in ukeys:
			if done.has(key):
				continue
			var comp: Array = [key]
			done[key] = true
			var qi := 0
			while qi < comp.size():
				var h: Vector2i = comp[qi]
				qi += 1
				for n in a.walk_neighbors(h):
					if unreached.has(n) and not done.has(n):
						done[n] = true
						comp.append(n)
			comps.append(comp)
		comps.sort_custom(func(x: Array, y: Array) -> bool: return x.size() > y.size())
		for comp in comps:
			for h in comp:
				if ramps.has(h):
					continue
				for n in HHHex.neighbors(h):
					if seen.has(n) and not ramps.has(n) and absi(int(levels[n]) - int(levels[h])) == 1:
						cands.append({ "u": h, "r": n })
						break
			if not cands.is_empty():
				break
	if cands.is_empty():
		return false
	var pick: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var u: Vector2i = pick.u
	var r: Vector2i = pick.r
	var lo := mini(int(levels[u]), int(levels[r]))
	var low_side: Vector2i = r if int(levels[r]) == lo else u
	var high_side: Vector2i = u if low_side == r else r
	var dir := (HHHex.to_world(high_side, HHArena.HEX) - HHHex.to_world(low_side, HHArena.HEX)).normalized()
	ramps[u] = { "lo": lo, "dir": dir }
	return true


# ------------------------------------------------------------------ arena

## The logical underlay: cells with kinds floor / edge / rock / pillar (hp,
## kind_after) / shade, the terraced heightfield, spawns, authored rows.
static func arena(p: Dictionary) -> HHArena:
	return layout(_validated(p)).arena


static func build_both(p: Dictionary) -> Dictionary:
	var g := HHCaveGen.new()
	return { "arena": arena(p), "asset": g.build(p) }


static func export_dict(p: Dictionary) -> Dictionary:
	var q := _validated(p)
	return HHGenUtil.export_dict(arena(q), "cave", 1, q)


static func export_json(p: Dictionary, path: String = "res://arenas/cave.json") -> bool:
	return HHGenUtil.write_json(export_dict(p), path)


# ------------------------------------------------------------------ asset

func _build(q: Dictionary) -> GKAsset:
	var asset := GKAsset.new()
	var L := layout(q)
	var a: HHArena = L.arena
	var R: float = q.radius_m
	var T: int = int(q.terraces)
	# -- floor: terraces lighter the higher they are, cliff faces and walls darker
	var g := GKMesh.new()
	var floor_role := role("cave_floor")
	var wall_role := role("cave_wall")
	var hf: Dictionary = a.hf
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var ox: float = hf.origin[0]
	var oz: float = hf.origin[1]
	var data: PackedFloat32Array = hf.data
	for j in rows - 1:
		for i in cols - 1:
			var x0 := ox + i * step
			var z0 := oz + j * step
			var h00 := data[j * cols + i]
			var h10 := data[j * cols + i + 1]
			var h01 := data[(j + 1) * cols + i]
			var h11 := data[(j + 1) * cols + i + 1]
			var lo := minf(minf(h00, h10), minf(h01, h11))
			var hi := maxf(maxf(h00, h10), maxf(h01, h11))
			var cx := x0 + step * 0.5
			var cz := z0 + step * 0.5
			var r := sqrt(cx * cx + cz * cz)
			var rname := floor_role
			if r > R + 0.5:
				rname = wall_role
				g.tint = Color.WHITE.lerp(Color(0.55, 0.5, 0.48), clampf((r - R) / 6.0, 0.0, 1.0))
			elif hi - lo > 0.45:
				# a cliff face: lighter and warmer than the floors so every terrace edge reads
				rname = wall_role
				g.tint = Color(1.7, 1.5, 1.3)
			else:
				var lvl := clampf(lo / (STEP_M * maxf(float(T - 1), 1.0)), 0.0, 1.0)
				g.tint = Color(0.85, 0.84, 0.86).lerp(Color(1.6, 1.5, 1.35), lvl)
			g.quad(rname, Vector3(x0, h00, z0), Vector3(x0 + step, h10, z0), Vector3(x0 + step, h11, z0 + step), Vector3(x0, h01, z0 + step))
	g.tint = Color.WHITE
	var floor_mesh := g.commit()
	asset.add_part("floor", floor_mesh)
	asset.add_trimesh_collider(floor_mesh)
	# -- pillars: stalagmite columns, hex-snapped
	var pg := GKMesh.new()
	var pr := role("stalagmite")
	var pillars := HHGenUtil.cells_of_kind(a, "pillar")
	for i in pillars.size():
		var h := pillars[i]
		var look: Dictionary = L.pillar_look[i]
		var base := a.world(h)
		var ht := float(look.h)
		var rad := float(look.r)
		var lean := float(look.lean)
		var ti := float(look.tint)
		pg.tint = Color(ti, ti * 0.98, ti * 0.95)
		var pts: Array = [base - Vector3(0, 0.3, 0), base + Vector3(0, ht * 0.12, 0), base + Vector3(lean * ht * 0.3, ht * 0.4, 0),
			base + Vector3(lean * ht * 0.55, ht * 0.62, 0), base + Vector3(lean * ht * 0.8, ht * 0.82, 0), base + Vector3(lean * ht, ht, 0)]
		pg.tube(pr, pts, [rad * 1.4, rad * 1.05, rad * 0.9, rad * 0.95, rad * 0.5, 0.06], 9, true)
		# a drip ring and a few small spikes at the foot
		pg.tube(pr, [base + Vector3(0, ht * 0.3, 0), base + Vector3(0, ht * 0.36, 0)], [rad * 0.95, rad * 0.8], 9, true)
		for k in 3:
			var ang := float(look.ph) + TAU * float(k) / 3.0
			var foot := base + Vector3(cos(ang) * rad * 1.1, -0.1, sin(ang) * rad * 1.1)
			pg.tube(pr, [foot, foot + Vector3(cos(ang) * 0.1, 0.55 + 0.2 * float(k), sin(ang) * 0.1)], [0.22, 0.0], 6, false)
	pg.tint = Color.WHITE
	asset.add_part("pillars", pg.commit())
	# -- rocks: boulders on their hex, pebbles anywhere
	var rg := GKMesh.new()
	var br := role("cave_boulder")
	var rocks := HHGenUtil.cells_of_kind(a, "rock")
	for i in rocks.size():
		var h := rocks[i]
		var look: Dictionary = L.rock_look[i]
		var c := a.world(h)
		var rad := float(look.r)
		var sq := float(look.sq)
		var ti := float(look.tint)
		rg.tint = Color(ti, ti, ti)
		rg.push(Transform3D(Basis(Vector3.UP, float(look.rot)), c + Vector3(0, rad * sq * 0.55, 0)))
		rg.sphere(br, Vector3.ZERO, rad, 7, Vector3(1.0, sq, 0.85))
		rg.sphere(br, Vector3(rad * 0.5, -rad * sq * 0.3, rad * 0.3), rad * 0.55, 6, Vector3(1.0, 0.7, 1.0))
		rg.pop()
	for pb in L.pebbles:
		var p: Dictionary = pb
		var x := float(p.x)
		var z := float(p.z)
		var ti := float(p.tint)
		rg.tint = Color(ti, ti, ti)
		rg.sphere(br, Vector3(x, a.height_at(x, z) + float(p.r) * 0.3, z), float(p.r), 5, Vector3(1.0, 0.6, 0.8))
	rg.tint = Color.WHITE
	asset.add_part("rocks", rg.commit())
	# -- shade: frost patches with a few ice crystals
	var sg := GKMesh.new()
	var fr := role("frost")
	for sh in L.shade:
		var h: Vector2i = sh
		var c := a.world(h) + Vector3(0, 0.03, 0)
		var corners := HHHex.corners(c, HHArena.HEX * 0.92)
		var pts := PackedVector3Array()
		for k in 6:
			pts.append(corners[k])
		sg.tint = Color(0.95, 1.0, 1.0)
		sg.poly(fr, pts)
		for k in 3:
			var ang := TAU * float(k) / 3.0 + float(h.x) * 0.7
			var foot := c + Vector3(cos(ang) * 0.4, 0.0, sin(ang) * 0.4)
			sg.tube(fr, [foot, foot + Vector3(cos(ang) * 0.08, 0.45 + 0.15 * float(k), sin(ang) * 0.08)], [0.14, 0.0], 5, false)
	sg.tint = Color.WHITE
	asset.add_part("shade", sg.commit())
	# -- torches on the rim (markers torch_N carry the point lights)
	var tg := GKMesh.new()
	var post := role("torch_post")
	var flame := role("torch_flame")
	for i in L.torches.size():
		var t: Dictionary = L.torches[i]
		var x := float(t.x)
		var z := float(t.z)
		var y := a.height_at(x, z)
		var top := Vector3(x, y + float(t.h), z)
		tg.tint = Color.WHITE
		tg.cyl(post, Vector3(x, y - 0.2, z), top, 0.07, 6)
		tg.cyl(post, top - Vector3(0, 0.25, 0), top, 0.13, 6)
		tg.sphere(flame, top + Vector3(0, 0.2, 0), 0.2, 8, Vector3(1.0, 1.6, 1.0))
		asset.markers["torch_%d" % i] = Transform3D(Basis.IDENTITY, top + Vector3(0, 0.45, 0))
	asset.add_part("torches", tg.commit())
	# -- wall spires on the skirt
	var wg := GKMesh.new()
	for sp in L.spires:
		var s: Dictionary = sp
		var x := float(s.x)
		var z := float(s.z)
		var y := a.height_at(x, z) - 0.5
		var ti := float(s.tint)
		wg.tint = Color(ti, ti, ti)
		wg.tube(wall_role, [Vector3(x, y, z), Vector3(x, y + float(s.h) * 0.6, z), Vector3(x, y + float(s.h), z)], [float(s.r), float(s.r) * 0.6, 0.05], 6, false)
	wg.tint = Color.WHITE
	asset.add_part("spires", wg.commit())
	# -- markers and lights: dim cool light from the open top, warm torches
	HHGenUtil.markers(asset, a, R * 0.95, R + 15.0)
	var dark: float = q.darkness
	asset.lights = { "sun_dir_deg": [-38.0, 20.0], "sun_energy": lerpf(1.1, 0.2, dark), "sun_color": "#8fa6c8",
		"sky_top": "#0a0d13", "sky_horizon": "#1b2129", "ground_horizon": "#15181c", "ground_bottom": "#08090b", "ambient": lerpf(0.9, 0.24, dark),
		"points": { "torch": { "color": "#ffb060", "energy": lerpf(2.0, 6.0, dark), "range": 20.0 } } }
	asset.meta = { "terraces": T, "ramps": (L.ramps as Dictionary).size(), "repairs": L.repairs, "pillars": pillars.size(), "rocks": rocks.size(),
		"shade": (L.shade as Array).size(), "walkable": a.walkable_count(), "cells": a.cells.size(),
		"reach": HHGenUtil.reach_fraction(a, a.spawns.player[0]) }
	if a.path(a.spawns.player[0], a.spawns.monster).is_empty():
		asset.warnings.append("no path from the player spawn to the monster spawn")
	return asset
