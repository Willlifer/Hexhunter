class_name HHArena
extends RefCounted
## An arena: the logical hex underlay over a heightfield (H9: 1 m hexes,
## odd-r, 35 m floor with a skirt beyond it). Pure data and queries, no nodes.
## Lane C's generators build these; `round_flat` here is the Phase 0 stand-in.
##
## cells: Vector2i -> { walkable: bool, kind: String ("floor" | "edge" | "rock"
##   | "water"), depth: float (water depth, m) }
## hf: the heightfield { cols, rows, step, origin: [x, z], data: PackedFloat32Array },
##   read through height_at(x, z) (Gauntlet's GKExtractForest.height_at).
## Hex centres carry the heightfield's height; a neighbour more than
## HHTune.max_step_m higher or lower is a cliff (H17: edge hexes unwalkable).

const HEX := 1.0

var id := "round"
var seed := 1
var radius_m := 25.0          ## walkable floor radius (H23: 50 m across)
var skirt_m := 12.0           ## scenery beyond the floor
var cells := {}
var hf := {}
var spawns := { "player": [Vector2i(0, 8)], "monster": Vector2i(0, -6) }


# ------------------------------------------------------------------ building

## A round floor of `radius_m` with a seeded gentle bump field and a rising
## rim beyond it. `bumps` = bump amplitude in metres (0 = flat).
static func round_flat(p_seed: int = 1, p_radius_m: float = 25.0, bumps: float = 0.6) -> HHArena:
	var a := HHArena.new()
	a.id = "round"
	a.seed = p_seed
	a.radius_m = p_radius_m
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var blobs: Array = []
	for i in 7:
		blobs.append([rng.randf_range(-p_radius_m, p_radius_m), rng.randf_range(-p_radius_m, p_radius_m),
			rng.randf_range(3.0, 7.0), rng.randf_range(-1.0, 1.0) * bumps])
	var step := 3.0
	var reach := p_radius_m + a.skirt_m
	var n := int(ceil(2.0 * reach / step)) + 2
	var origin := -reach - step
	var data := PackedFloat32Array()
	data.resize(n * n)
	for j in n:
		for i in n:
			var x := origin + i * step
			var z := origin + j * step
			var h := 0.0
			for b in blobs:
				var dx: float = x - float(b[0])
				var dz: float = z - float(b[1])
				var s: float = float(b[2])
				h += float(b[3]) * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
			var d := sqrt(x * x + z * z)
			if d > p_radius_m:
				h += (d - p_radius_m) * 0.55        # the skirt rises into a bowl wall
			data[j * n + i] = h
	a.hf = { "cols": n, "rows": n, "step": step, "origin": [origin, origin], "data": data }
	a._lay_cells()
	return a


## Fill `cells` from the radius: floor inside, one edge band, nothing beyond.
func _lay_cells() -> void:
	cells = {}
	var r_hex := int(ceil((radius_m + 2.0) / (HEX * 1.5))) + 1
	for row in range(-r_hex, r_hex + 1):
		for col in range(-r_hex - 1, r_hex + 2):
			var h := Vector2i(col, row)
			var w := HHHex.to_world(h, HEX)
			var d := w.length()
			if d > radius_m:
				continue
			var edge := d > radius_m - HEX * 1.8
			cells[h] = { "walkable": not edge, "kind": "edge" if edge else "floor", "depth": 0.0 }


# ------------------------------------------------------------------ queries

func exists(h: Vector2i) -> bool:
	return cells.has(h)


func walkable(h: Vector2i) -> bool:
	return cells.has(h) and bool(cells[h].walkable)


func kind(h: Vector2i) -> String:
	return str(cells.get(h, {}).get("kind", ""))


func depth(h: Vector2i) -> float:
	return float(cells.get(h, {}).get("depth", 0.0))


func height_at(x: float, z: float) -> float:
	if hf.is_empty():
		return 0.0
	var cols: int = hf.cols
	var rows: int = hf.rows
	var step: float = hf.step
	var data: PackedFloat32Array = hf.data
	var fx := clampf((x - float(hf.origin[0])) / step, 0.0, float(cols - 1) - 1e-4)
	var fz := clampf((z - float(hf.origin[1])) / step, 0.0, float(rows - 1) - 1e-4)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var h00 := data[j * cols + i]
	var h10 := data[j * cols + i + 1]
	var h01 := data[(j + 1) * cols + i]
	var h11 := data[(j + 1) * cols + i + 1]
	if v <= u:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h01 - h00) * v + (h11 - h01) * u


func hex_height(h: Vector2i) -> float:
	var w := HHHex.to_world(h, HEX)
	return height_at(w.x, w.y)


func cover(h: Vector2i) -> bool:
	return bool(cells.get(h, {}).get("cover", false))


## Hex centre in world space, on the ground (the bed, under water).
func world(h: Vector2i) -> Vector3:
	var w := HHHex.to_world(h, HEX)
	return Vector3(w.x, height_at(w.x, w.y), w.y)


## Where paint, outlines and telegraphs sit: the water surface (y = 0, H201)
## over water, deep and pad cells, the ground elsewhere.
func surface(h: Vector2i) -> Vector3:
	var p := world(h)
	if kind(h) in ["water", "deep", "pad"]:
		p.y = maxf(p.y, 0.0)
	return p


## Where a unit stands: on a pad at the surface, in water on the bed (wading).
func stand(h: Vector2i) -> Vector3:
	return surface(h) if kind(h) == "pad" else world(h)


func from_world(p: Vector3) -> Vector2i:
	return HHHex.from_world(Vector2(p.x, p.z), HEX)


## Neighbours that exist.
func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in HHHex.neighbors(h):
		if cells.has(n):
			out.append(n)
	return out


## Neighbours you can step onto from `h`: walkable and not a cliff.
func walk_neighbors(h: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var hh := hex_height(h)
	var max_step := HHTune.value("max_step_m")
	for n in HHHex.neighbors(h):
		if not walkable(n) or blocked.has(n):
			continue
		if absf(hex_height(n) - hh) > max_step:
			continue
		out.append(n)
	return out


func area(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in HHHex.area(center, radius):
		if cells.has(h):
			out.append(h)
	return out


func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for h in HHHex.ring(center, radius):
		if cells.has(h):
			out.append(h)
	return out


## Breadth-first path from `from` to `goal` over walkable hexes, excluding
## `from`, including `goal`. Empty when unreachable or from == goal.
## `blocked`: hexes to treat as walls this call (a monster's footprint).
func path(from: Vector2i, goal: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == goal or not walkable(goal) or blocked.has(goal):
		return out
	var prev := { from: from }
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		if h == goal:
			break
		for n in walk_neighbors(h, blocked):
			if not prev.has(n):
				prev[n] = h
				queue.append(n)
	if not prev.has(goal):
		return out
	var cur := goal
	while cur != from:
		out.push_front(cur)
		cur = prev[cur]
	return out


## The reachable walkable hex nearest to `goal` from `from` (goal itself when
## it qualifies). Ties: fewest steps, then lower hex sort.
func nearest_walkable(from: Vector2i, goal: Vector2i, blocked: Dictionary = {}) -> Vector2i:
	if walkable(goal) and not blocked.has(goal) and (from == goal or not path(from, goal, blocked).is_empty()):
		return goal
	var best := from
	var best_d := HHHex.distance(from, goal)
	var seen := { from: true }
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		var d := HHHex.distance(h, goal)
		if d < best_d or (d == best_d and h < best):
			best_d = d
			best = h
		for n in walk_neighbors(h, blocked):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return best


## Path from `from` to the first hex within `reach` of `target` (walk into
## range, OSRS style). Empty when already in reach or none is reachable.
func path_to_reach(from: Vector2i, target: Vector2i, reach: int, blocked: Dictionary = {}) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if HHHex.distance(from, target) <= reach:
		return out
	var prev := { from: from }
	var queue: Array[Vector2i] = [from]
	var qi := 0
	var found := from
	var ok := false
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		if HHHex.distance(h, target) <= reach:
			found = h
			ok = true
			break
		for n in walk_neighbors(h, blocked):
			if not prev.has(n):
				prev[n] = h
				queue.append(n)
	if not ok:
		return out
	var cur := found
	while cur != from:
		out.push_front(cur)
		cur = prev[cur]
	return out


func walkable_count() -> int:
	var n := 0
	for h in cells:
		if cells[h].walkable:
			n += 1
	return n


# ------------------------------------------------------------------ serialisation

func to_dict() -> Dictionary:
	var cl: Array = []
	var keys := cells.keys()
	keys.sort()
	for h in keys:
		var c: Dictionary = cells[h]
		var row := { "q": h.x, "r": h.y, "walkable": c.walkable, "kind": c.kind, "depth": c.depth }
		if bool(c.get("cover", false)):
			row["cover"] = true
		cl.append(row)
	return { "id": id, "seed": seed, "radius_m": radius_m, "skirt_m": skirt_m,
		"hf": { "cols": hf.cols, "rows": hf.rows, "step": hf.step, "origin": hf.origin, "data": Array(hf.data) },
		"cells": cl, "spawns": { "player": spawns.player.map(func(h): return [h.x, h.y]), "monster": [spawns.monster.x, spawns.monster.y] } }


static func from_dict(d: Dictionary) -> HHArena:
	var a := HHArena.new()
	a.id = str(d.get("id", "round"))
	a.seed = int(d.get("seed", 1))
	a.radius_m = float(d.get("radius_m", 25.0))
	a.skirt_m = float(d.get("skirt_m", 12.0))
	var h: Dictionary = d.get("hf", {})
	if not h.is_empty():
		a.hf = { "cols": int(h.cols), "rows": int(h.rows), "step": float(h.step), "origin": h.origin, "data": PackedFloat32Array(h.data) }
	for c in d.get("cells", []):
		a.cells[Vector2i(int(c.q), int(c.r))] = { "walkable": bool(c.walkable), "kind": str(c.kind), "depth": float(c.get("depth", 0.0)), "cover": bool(c.get("cover", false)) }
	var sp: Dictionary = d.get("spawns", {})
	if sp.has("player"):
		a.spawns.player = sp.player.map(func(v): return Vector2i(int(v[0]), int(v[1])))
	if sp.has("monster"):
		a.spawns.monster = Vector2i(int(sp.monster[0]), int(sp.monster[1]))
	return a
