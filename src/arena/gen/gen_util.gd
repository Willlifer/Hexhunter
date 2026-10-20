class_name HHGenUtil
extends RefCounted
## Shared by the biome generators (Lane C/D): heightfield fill from a height
## function, spawn picking, BFS reach, the extra cell keys (hp, kind_after,
## sun) and the authored-charge rows that HHArena.to_dict does not carry,
## and the JSON export with the `gen` block (H206 shape).
##
## Cell kind contract (the monster lanes build against these names):
##   floor, edge, water, deep, pad (cover) ....... pond (H200-H204)
##   rock       impassable boulder, holds no charge (HHCharge.can_hold)
##   pillar     destructible column: impassable until broken; `hp: float`,
##              `kind_after: "floor"` (the sim flips kind and walkable on 0 hp)
##   vent       heat vent: walkable; authored fire 1 that re-forms
##   lava       lava pool: impassable; authored fire 3, permanent
##   sun        sunlit patch: walkable floor, `sun: true` (Spirewalker recharges)
##   shade      cave shade / cold vent: walkable; authored water 1 + glaze
##   tree       obstacle: impassable, holds no charge
## Authored charge: `arena.spawns["authored"]` = [{ q, r, h, v, marker, glaze }]
## (h: fire +, water -; v: light +, dark -), applied by the integrator at fight
## start through HHCharge.author (Request: `authored` belongs on HHArena).

const EDGE_M := 1.8                 ## H17 edge band (HHArena._lay_cells uses HEX * 1.8)
const IMPASSABLE := ["rock", "pillar", "lava", "tree", "edge"]
const NO_CHARGE := ["rock", "pillar", "tree"]
const EXTRA_KEYS := ["hp", "kind_after", "sun"]


## Fill `a.hf` on a square grid of `step` covering radius + skirt, from
## `height.call(x, z) -> float`.
static func fill_hf(a: HHArena, height: Callable, step: float = 1.0) -> void:
	var reach := a.radius_m + a.skirt_m
	var n := int(ceil(2.0 * reach / step)) + 2
	var origin := -reach - step
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		var z := origin + j * step
		for i in n:
			data[j * n + i] = float(height.call(origin + i * step, z))
	a.hf = { "cols": n, "rows": n, "step": step, "origin": [origin, origin], "data": data }


## Every hex reachable on foot from `from` (walkable, cliff rule), as a set.
static func reach(a: HHArena, from: Vector2i) -> Dictionary:
	var seen := { from: true }
	if not a.walkable(from):
		return {}
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		for n in a.walk_neighbors(h):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## Fraction of the walkable cells reachable from `from`.
static func reach_fraction(a: HHArena, from: Vector2i) -> float:
	var w := a.walkable_count()
	if w == 0:
		return 0.0
	return float(reach(a, from).size()) / float(w)


static func nearest_walkable_hex(a: HHArena, from: Vector2i, max_r: int = 10) -> Vector2i:
	if a.walkable(from):
		return from
	for r in range(1, max_r + 1):
		var ring := HHHex.ring(from, r)
		ring.sort()
		for h in ring:
			if a.walkable(h):
				return h
	return from


## Sorted hexes of one kind.
static func cells_of_kind(a: HHArena, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var keys := a.cells.keys()
	keys.sort()
	for k in keys:
		if str((a.cells[k] as Dictionary).kind) == kind:
			out.append(k)
	return out


## Spawns: the player at the walkable hex nearest `player_at`; the monster at
## the reachable hex nearest `monster_at` that is at least `min_apart` hexes
## away (else the farthest reachable hex). Both end up connected by a path.
static func pick_spawns(a: HHArena, player_at: Vector2, monster_at: Vector2, min_apart: int = 10) -> void:
	var ph := nearest_walkable_hex(a, HHHex.from_world(player_at, HHArena.HEX))
	var want := HHHex.from_world(monster_at, HHArena.HEX)
	var seen := reach(a, ph)
	var keys := seen.keys()
	keys.sort()
	var best := ph
	var best_d := 1 << 30
	var far := ph
	var far_d := -1
	for k in keys:
		var h: Vector2i = k
		if h == ph:
			continue
		var apart := HHHex.distance(h, ph)
		if apart > far_d:
			far_d = apart
			far = h
		if apart < min_apart:
			continue
		var d := HHHex.distance(h, want)
		if d < best_d:
			best_d = d
			best = h
	if best == ph:
		best = far
	a.spawns["player"] = [ph]
	a.spawns["monster"] = best


## Cells carrying keys HHArena.to_dict drops, as rows for the JSON.
static func extras(a: HHArena) -> Array:
	var out: Array = []
	var keys := a.cells.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = a.cells[k]
		var row := {}
		for key in EXTRA_KEYS:
			if c.has(key):
				row[key] = c[key]
		if not row.is_empty():
			row["q"] = (k as Vector2i).x
			row["r"] = (k as Vector2i).y
			out.append(row)
	return out


static func authored(a: HHArena) -> Array:
	return a.spawns.get("authored", [])


## One authored-charge row (h: fire +, water -; v: light +, dark -).
static func author_row(h: Vector2i, fire_water: int, light_dark: int, marker: String = "", glaze: bool = false) -> Dictionary:
	return { "q": h.x, "r": h.y, "h": fire_water, "v": light_dark, "marker": marker, "glaze": glaze }


## What arenas/<id>.json holds: HHArena.to_dict plus `gen` (rebuild), `extras`
## (hp / kind_after / sun per cell) and `authored` (charge rows).
static func export_dict(a: HHArena, gen_id: String, version: int, q: Dictionary) -> Dictionary:
	var d := a.to_dict()
	d["gen"] = { "id": gen_id, "version": version, "params": q }
	d["extras"] = extras(a)
	d["authored"] = authored(a)
	return d


## HHArena.from_dict plus the extras and authored rows put back (what boot
## should do when it loads a biome JSON; Request).
static func from_dict(d: Dictionary) -> HHArena:
	var a := HHArena.from_dict(d)
	for row in d.get("extras", []):
		var r: Dictionary = row
		var h := Vector2i(int(r.q), int(r.r))
		if not a.cells.has(h):
			continue
		var c: Dictionary = a.cells[h]
		for key in EXTRA_KEYS:
			if r.has(key):
				c[key] = r[key]
	if d.has("authored"):
		a.spawns["authored"] = d.authored
	return a


static func write_json(d: Dictionary, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("HHGenUtil: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true


## A generator's own role once merged into GKMaterials, else its fallback.
static func role(fallback: Dictionary, name: String) -> String:
	if GKMaterials.has(name):
		return name
	return str(fallback.get(name, name))


## The heightfield as quads; `pick.call(cx, cz) -> [role, tint]` per quad.
static func hf_quads(g: GKMesh, a: HHArena, pick: Callable) -> void:
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
			var rt: Array = pick.call(x0 + step * 0.5, z0 + step * 0.5)
			g.tint = rt[1]
			g.quad(str(rt[0]), Vector3(x0, data[j * cols + i], z0), Vector3(x0 + step, data[j * cols + i + 1], z0),
				Vector3(x0 + step, data[(j + 1) * cols + i + 1], z0 + step), Vector3(x0, data[(j + 1) * cols + i], z0 + step))
	g.tint = Color.WHITE


## Spawn and camera markers shared by every biome.
static func markers(asset: GKAsset, a: HHArena, cam_height: float, cam_back: float) -> void:
	var ps := a.world(a.spawns.player[0])
	var ms := a.world(a.spawns.monster)
	var to_m := (Vector3(ms.x, 0, ms.z) - Vector3(ps.x, 0, ps.z)).normalized()
	asset.markers["spawn_player"] = Transform3D(Basis.looking_at(to_m, Vector3.UP), ps)
	asset.markers["spawn_monster"] = Transform3D(Basis.looking_at(-to_m, Vector3.UP), ms)
	var cam_pos := Vector3(0.0, cam_height, cam_back)
	var cam_at := Vector3(0.0, 0.0, -a.radius_m * 0.1)
	asset.markers["ref_cam"] = Transform3D(Basis.looking_at(cam_at - cam_pos, Vector3.UP), cam_pos)


## A gaussian bump field: blobs = [{ x, z, s, a }].
static func blobs_at(blobs: Array, x: float, z: float) -> float:
	var h := 0.0
	for b in blobs:
		var bd: Dictionary = b
		var dx := x - float(bd.x)
		var dz := z - float(bd.z)
		var s := float(bd.s)
		h += float(bd.a) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
	return h


## Seeded blobs over a disc of `r`.
static func make_blobs(rng: RandomNumberGenerator, count: int, r: float, s_lo: float, s_hi: float, amp: float) -> Array:
	var out: Array = []
	for i in count:
		out.append({ "x": rng.randf_range(-r, r), "z": rng.randf_range(-r, r), "s": rng.randf_range(s_lo, s_hi), "a": rng.randf_range(-1.0, 1.0) * amp })
	return out


## Hexes of the floor (not edge) at least `keep` hexes from every hex in
## `avoid` and from each other, drawn seeded from `pool` (sorted), up to `count`.
static func pick_spaced(rng: RandomNumberGenerator, pool: Array[Vector2i], count: int, spacing: int, avoid: Array, keep: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if pool.is_empty() or count <= 0:
		return out
	var tries := 0
	while out.size() < count and tries < count * 40 + 40:
		tries += 1
		var h := pool[rng.randi_range(0, pool.size() - 1)]
		var ok := true
		for o in avoid:
			if HHHex.distance(h, o) < keep:
				ok = false
				break
		if ok:
			for o in out:
				if HHHex.distance(h, o) < spacing:
					ok = false
					break
		if ok:
			out.append(h)
	return out
