class_name HHSnapshot
extends RefCounted
## H52: the host's HHSim as plain data, and back. Node-free.
##
## capture(sim) -> a deep, serialisable copy of everything a mirror needs:
##   { t: tick, o: over, ord: unit order, u: { id: unit }, c: { hex: charge entry },
##     tg: telegraphs, pr: projectiles, env: [next_tick, count], cells: { hex: cell } }
## Callables (leap.on_land, windup.on_done) and Objects become null: a mirror
## never resolves them, it only shows them. Vector2i / Vector3 survive as
## themselves (var_to_bytes keeps them; see encode()).
##
## apply(sim, snap) overwrites a mirror in place (unit dictionaries and
## charge.entries keep their identity, so bodies and views that hold a
## reference keep working). After it, mirror.state_hash() == host.state_hash().
##
## delta(prev, cur) -> what changed between two captures; apply_delta(sim, d)
## turns a mirror holding `prev` into one holding `cur`. Countdowns that tick
## every step are PREDICTED, not shipped: the charge grid is aged with a copy
## of HHCharge.tick's decay rule (the host's numbers ride in the delta), and
## telegraph / projectile `left` drop by one. Only what differs from that
## prediction travels. If the rule ever changes in charge.gd the prediction
## just misses more and the delta grows: it never goes wrong, only bigger.

const CELL_KEYS := ["kind", "walkable", "hp"]


# ------------------------------------------------------------------ capture / apply

static func capture(sim: HHSim) -> Dictionary:
	var u := {}
	for id in sim.order:
		u[id] = clean(sim.units[id])
	var c := {}
	for h in sim.charge.entries:                   # entries are flat primitives (charge.gd): a shallow copy is a full copy
		c[h] = (sim.charge.entries[h] as Dictionary).duplicate()
	var cells := {}
	for h in _destructible(sim.arena):             # H44 pillars: the only cells that change in a fight
		cells[h] = _cell(sim.arena.cells[h])
	return {
		"t": sim.tick, "o": sim.over, "ord": sim.order.duplicate(), "u": u, "c": c,
		"tg": clean(sim.telegraphs), "pr": clean(sim.projectiles),
		"env": [sim.env.next_tick, sim.env.count] if sim.env != null else [],
		"cells": cells,
	}


static func apply(sim: HHSim, snap: Dictionary) -> void:
	sim.tick = int(snap.t)
	sim.over = str(snap.o)
	var ord: Array = snap.ord
	for id in ord:
		_set_unit(sim, str(id), snap.u[id])
	for id in sim.units.keys():
		if not id in ord:
			sim.units.erase(id)
	sim.order = ord.duplicate()
	sim.charge.entries.clear()
	for h in snap.c:
		sim.charge.entries[h] = clean(snap.c[h])
	sim.telegraphs = clean(snap.tg)
	sim.projectiles = clean(snap.pr)
	_set_env(sim, snap.env)
	for h in snap.cells:
		_set_cell(sim, h, snap.cells[h])


## A deep copy with every Callable and Object replaced by null.
static func clean(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out := {}
			for k in d:
				out[k] = clean(d[k])
			return out
		TYPE_ARRAY:
			var a: Array = v
			if a.is_typed() and a.get_typed_builtin() != TYPE_OBJECT and a.get_typed_builtin() != TYPE_CALLABLE:
				return a.duplicate()                  # Array[Vector2i] paths: plain values, keep the type
			var out: Array = []
			out.resize(a.size())
			for i in a.size():
				out[i] = clean(a[i])
			return out
		TYPE_CALLABLE, TYPE_OBJECT, TYPE_SIGNAL, TYPE_RID:
			return null
	return v


## True when two captures hold the same state (stronger than state_hash).
static func same(a: Dictionary, b: Dictionary) -> bool:
	return _deep_eq(a, b)


# ------------------------------------------------------------------ deltas

static func delta(prev: Dictionary, cur: Dictionary) -> Dictionary:
	var d := { "t": int(cur.t), "b": int(prev.t),
		"ag": [int(HHTune.value("charge_step_ticks")), int(HHTune.value("charge_glaze_ticks"))] }
	if str(cur.o) != str(prev.o):
		d.o = cur.o
	if cur.ord != prev.ord:
		d.ord = cur.ord
	var ud := {}
	for id in cur.u:
		var cu: Dictionary = cur.u[id]
		if not prev.u.has(id):
			ud[id] = { "@new": cu }
			continue
		var f := _fields(prev.u[id], cu)
		if not f.is_empty():
			ud[id] = f
	if not ud.is_empty():
		d.u = ud
	var aged := age_charge(prev.c, int(d.ag[0]), int(d.ag[1]))
	var cd := {}
	for h in cur.c:
		if not aged.has(h) or aged[h] != cur.c[h]:
			cd[h] = cur.c[h]
	var cx: Array = []
	for h in aged:
		if not cur.c.has(h):
			cx.append(h)
	if not cd.is_empty():
		d.c = cd
	if not cx.is_empty():
		d.cx = cx
	var tg := _list_delta(prev.tg, cur.tg, "left")
	if not tg.is_empty():
		d.tg = tg
	var pr := _list_delta(prev.pr, cur.pr, "left")
	if not pr.is_empty():
		d.pr = pr
	if cur.env != prev.env:
		d.env = cur.env
	var cells := {}
	for h in cur.cells:
		if not prev.cells.has(h) or prev.cells[h] != cur.cells[h]:
			cells[h] = cur.cells[h]
	if not cells.is_empty():
		d.cells = cells
	return d


## Turns a mirror at d.b into one at d.t. Returns false (and changes
## nothing) when the mirror is not at the delta's base tick.
static func apply_delta(sim: HHSim, d: Dictionary) -> bool:
	if sim.tick != int(d.b):
		return false
	sim.tick = int(d.t)
	if d.has("o"):
		sim.over = str(d.o)
	var ud: Dictionary = d.get("u", {})
	for id in ud:
		var f: Dictionary = ud[id]
		if f.has("@new"):
			_set_unit(sim, str(id), f["@new"])
			if not id in sim.order:
				sim.order.append(id)
			continue
		var u: Dictionary = sim.units.get(id, {})
		for k in f:
			if str(k) == "@gone":
				for g in f[k]:
					u.erase(g)
			else:
				u[k] = _own(k, f[k])
	if d.has("ord"):
		sim.order = (d.ord as Array).duplicate()
	var aged := age_charge(sim.charge.entries, int(d.ag[0]), int(d.ag[1]))
	sim.charge.entries.clear()
	sim.charge.entries.merge(aged)
	var cd: Dictionary = d.get("c", {})
	for h in cd:
		sim.charge.entries[h] = clean(cd[h])
	for h in d.get("cx", []):
		sim.charge.entries.erase(h)
	sim.telegraphs = _list_apply(sim.telegraphs, d.get("tg", {}), "left")
	sim.projectiles = _list_apply(sim.projectiles, d.get("pr", {}), "left")
	if d.has("env"):
		_set_env(sim, d.env)
	var cells: Dictionary = d.get("cells", {})
	for h in cells:
		_set_cell(sim, h, cells[h])
	return true


## HHCharge.tick() on a copy: what one tick of decay does to `entries`.
static func age_charge(entries: Dictionary, step_ticks: int, glaze_ticks: int) -> Dictionary:
	var out := {}
	for hex in entries:
		var e: Dictionary = (entries[hex] as Dictionary).duplicate()
		if bool(e.get("permanent", false)):
			if bool(e.get("permanent_glaze", false)) and int(e.glaze) <= 0:
				e.glaze = glaze_ticks
			out[hex] = e
			continue
		if int(e.glaze) > 0:
			e.glaze = int(e.glaze) - 1
			out[hex] = e
			continue
		e.timer = int(e.timer) - 1
		if int(e.timer) > 0:
			out[hex] = e
			continue
		if str(e.marker) != "":
			continue
		var ah := absi(int(e.h))
		var av := absi(int(e.v))
		if ah >= av:
			e.h = int(e.h) - signi(int(e.h))
		if av >= ah:
			e.v = int(e.v) - signi(int(e.v))
		if int(e.h) == 0 and int(e.v) == 0:
			continue
		e.timer = step_ticks
		out[hex] = e
	return out


# ------------------------------------------------------------------ wire

## Bytes on the wire: var_to_bytes (no objects), zstd above 160 bytes.
## Header byte 0 = raw; 1 = zstd, followed by the raw size as u32.
static func encode(v: Variant) -> PackedByteArray:
	var raw := var_to_bytes(v)
	if raw.size() <= 160:
		var out := PackedByteArray([0])
		out.append_array(raw)
		return out
	var z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var out := PackedByteArray([1, 0, 0, 0, 0])
	out.encode_u32(1, raw.size())
	out.append_array(z)
	return out


static func decode(b: PackedByteArray) -> Variant:
	if b.is_empty():
		return null
	if b[0] == 0:
		return bytes_to_var(b.slice(1))
	if b[0] == 1 and b.size() > 5:
		var n := b.decode_u32(1)
		if n > 16 * 1024 * 1024:
			return null
		return bytes_to_var(b.slice(5).decompress(n, FileAccess.COMPRESSION_ZSTD))
	return null


# ------------------------------------------------------------------ internals

## Value equality that also tells int from float and 1 from true.
static func _deep_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for k in da:
				if not db.has(k) or not _deep_eq(da[k], db[k]):
					return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if not _deep_eq(aa[i], ab[i]):
					return false
			return true
	return a == b


static func _fields(a: Dictionary, b: Dictionary) -> Dictionary:
	var f := {}
	for k in b:
		if not a.has(k) or typeof(a[k]) != typeof(b[k]) or a[k] != b[k]:
			f[k] = b[k]
	var gone: Array = []
	for k in a:
		if not b.has(k):
			gone.append(k)
	if not gone.is_empty():
		f["@gone"] = gone
	return f


## A list of dictionaries keyed by "id" (telegraphs, projectiles). `aging`
## names a countdown that drops by one every tick: predicted, not shipped.
static func _list_delta(a: Array, b: Array, aging: String) -> Dictionary:
	var by := {}
	for x in a:
		by[x.id] = _aged(x, aging)
	var out := {}
	var add: Array = []
	var mod := {}
	for x in b:
		if not by.has(x.id):
			add.append(x)
			continue
		var f := _fields(by[x.id], x)
		if not f.is_empty():
			mod[x.id] = f
	var bids: Array = b.map(func(x): return x.id)
	var gone: Array = []
	for x in a:
		if not x.id in bids:
			gone.append(x.id)
	if not add.is_empty():
		out.a = add
	if not mod.is_empty():
		out.m = mod
	if not gone.is_empty():
		out.x = gone
	var rebuilt: Array = a.map(func(x): return x.id).filter(func(i): return not i in gone)
	rebuilt.append_array(add.map(func(x): return x.id))
	if rebuilt != bids:
		out.ids = bids
	return out


static func _list_apply(list: Array, d: Dictionary, aging: String) -> Array:
	var gone: Array = d.get("x", [])
	var mod: Dictionary = d.get("m", {})
	var by := {}
	var out: Array = []
	for x in list:
		if x.id in gone:
			continue
		var y := _aged(x, aging)
		if mod.has(x.id):
			var f: Dictionary = mod[x.id]
			for k in f:
				if str(k) == "@gone":
					for g in f[k]:
						y.erase(g)
				else:
					y[k] = clean(f[k])
		by[y.id] = y
		out.append(y)
	for x in d.get("a", []):
		var y: Dictionary = clean(x)
		by[y.id] = y
		out.append(y)
	if d.has("ids"):
		out = (d.ids as Array).map(func(i): return by[i])
	return out


static func _aged(x: Dictionary, key: String) -> Dictionary:
	var y := x.duplicate(true)
	if y.has(key):
		y[key] = int(y[key]) - 1
	return y


static func _set_unit(sim: HHSim, id: String, src: Dictionary) -> void:
	if not sim.units.has(id):
		sim.units[id] = {}
	var u: Dictionary = sim.units[id]
	for k in u.keys():
		if not src.has(k):
			u.erase(k)
	for k in src:
		u[k] = _own(k, src[k])


## A field value the mirror owns (a deep copy); `path` keeps its Array[Vector2i] type.
static func _own(k: Variant, v: Variant) -> Variant:
	if str(k) == "path" and v is Array:
		var p: Array[Vector2i] = []
		p.assign(v)
		return p
	return clean(v)


static func _set_env(sim: HHSim, e: Array) -> void:
	if sim.env != null and e.size() == 2:
		sim.env.next_tick = int(e[0])
		sim.env.count = int(e[1])


## The hexes of cells that can break, found once per arena (cached as meta).
static func _destructible(a: HHArena) -> Array:
	if a.has_meta("hh_net_destructible"):
		return a.get_meta("hh_net_destructible")
	var out: Array = []
	for h in a.cells:
		if (a.cells[h] as Dictionary).has("kind_after"):
			out.append(h)
	a.set_meta("hh_net_destructible", out)
	return out


static func _cell(cell: Dictionary) -> Dictionary:
	var out := {}
	for k in CELL_KEYS:
		if cell.has(k):
			out[k] = cell[k]
	return out


static func _set_cell(sim: HHSim, h: Vector2i, src: Dictionary) -> void:
	var cell: Dictionary = sim.arena.cells.get(h, {})
	if cell.is_empty():
		return
	for k in CELL_KEYS:
		if src.has(k):
			cell[k] = src[k]
		else:
			cell.erase(k)
