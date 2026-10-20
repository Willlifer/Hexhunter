class_name HHCharge
extends RefCounted
## Elements on the ground: Black | White's charge grid (BWTiles, ELEMENTS.md
## §2-§6) rebuilt for a real-time arena. Pure state and rules. It reports what
## happened (detonations, eruptions, bursts) and HHSim turns those into damage,
## because only the sim knows the units.
##
## A hex with nothing on it has no entry. An entry:
##   { h, v, marker, glaze, timer, source, permanent }
## h: water(-3)..fire(+3), v: dark(-3)..light(+3). marker: "" | "fuse" (thunder)
## | "stasis" (ice) | "gale" (wind). glaze: ticks of ice left on a charged hex.
## timer: ticks until the next decay step (or until an unfired marker fades).
##
## What carried over from Black | White, unchanged in rule if not in units:
##   Douse (D421 there): fire meets water, both clear, nothing lingers.
##   Fuse: thunder on charge detonates it (5% + 4%/point + 2%/water point),
##         x1.5 on a glaze (Shatter). Any element arriving on an armed fuse
##         sets it off (D405). Thunder on empty ground arms a fuse.
##   Stasis / Glaze: ice on charge freezes it (decay paused); on empty ground
##         arms a stasis marker. Fire melts glaze and is spent; other
##         elements wash off it.
##   Gale: wind copies a hex's charge onto its neighbours; on empty ground
##         arms a gale marker.
##   Overheat (D285): fresh fire on fire 3 erupts: ring +2 fire, 6% to the
##         ring, centre vents to 2.
##   Overfreeze (D312): fresh ice on glazed water shatters: 12% to the hex and
##         ring, the ring glazes (thin ice sheets on empty ground).
## Dropped on purpose: keystones, lava, statics, seeds, pools, brim, eclipse,
## grass spread (Lane C may bring back terrain spread per biome).

const AXIS_MAX := 3
const AXIS := ["fire", "water", "light", "dark"]
const OPERATORS := { "thunder": "fuse", "ice": "stasis", "wind": "gale" }
const MARKER_ELEMENT := { "fuse": "thunder", "stasis": "ice", "gale": "wind" }
const SHATTER_MULT := 1.5
const OVERHEAT_RING_STEPS := 2
const OVERHEAT_VENT_TO := 2

var arena: HHArena
var entries := {}


func _init(p_arena: HHArena) -> void:
	arena = p_arena


# ------------------------------------------------------------------ reading

func at(hex: Vector2i) -> Dictionary:
	return entries.get(hex, {})


func intensity(hex: Vector2i, element: String) -> int:
	var e := at(hex)
	if e.is_empty():
		return 0
	match element:
		"fire": return maxi(int(e.h), 0)
		"water": return maxi(-int(e.h), 0)
		"light": return maxi(int(e.v), 0)
		"dark": return maxi(-int(e.v), 0)
	return 0


func is_glazed(hex: Vector2i) -> bool:
	return int(at(hex).get("glaze", 0)) > 0


func marker(hex: Vector2i) -> String:
	return str(at(hex).get("marker", ""))


func charged(hex: Vector2i) -> bool:
	var e := at(hex)
	return not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0)


func carries(hex: Vector2i, element: String) -> bool:
	var e := at(hex)
	if e.is_empty():
		return false
	match element:
		"fire": return int(e.h) > 0
		"water": return int(e.h) < 0
		"light": return int(e.v) > 0
		"dark": return int(e.v) < 0
		"thunder": return e.marker == "fuse"
		"wind": return e.marker == "gale"
		"ice": return e.marker == "stasis" or int(e.glaze) > 0
	return false


## Speed multiplier for whoever walks here (water slows; glazed water is ice,
## walkable at full speed).
func move_mult(hex: Vector2i, who: String = "") -> float:
	if is_glazed(hex) or (who != "" and owned_by(hex, who)):
		return 1.0
	var slow: Array = HHTune.list("water_slow")
	return float(slow[clampi(intensity(hex, "water"), 0, slow.size() - 1)])


## Per-second standing effects, in pct of max HP.
## Whose element this is (H33: your own never slows or hurts you).
func owned_by(hex: Vector2i, who: String) -> bool:
	return str(at(hex).get("source", "")) == who


func standing(hex: Vector2i) -> Dictionary:
	return {
		"source": str(at(hex).get("source", "")),
		"fire": HHTune.value("fire_stand_pct") * intensity(hex, "fire"),
		"heal": HHTune.value("light_heal_pct") * intensity(hex, "light"),
		"drain": HHTune.value("dark_drain_pct") if intensity(hex, "dark") >= 3 else 0.0,
	}


func crossing_pct(hex: Vector2i) -> float:
	return HHTune.value("fire_cross_pct") * intensity(hex, "fire")


func can_hold(hex: Vector2i) -> bool:
	return arena.exists(hex) and not arena.kind(hex) in ["rock", "pillar", "tree"]


static func blast_mix(e: Dictionary) -> Dictionary:
	var out := {}
	var h := int(e.get("h", 0))
	var v := int(e.get("v", 0))
	if h != 0:
		out["fire" if h > 0 else "water"] = absi(h)
	if v != 0:
		out["light" if v > 0 else "dark"] = absi(v)
	if int(e.get("glaze", 0)) > 0:
		out["ice"] = 1
	return out


# ------------------------------------------------------------------ writing

## Authored starting state: permanent charge or marker (a biome's lava pool,
## a pond's water).
func author(hex: Vector2i, h: int, v: int, p_marker: String = "", glaze: bool = false) -> void:
	if not can_hold(hex):
		return
	entries[hex] = _entry(clampi(h, -AXIS_MAX, AXIS_MAX), clampi(v, -AXIS_MAX, AXIS_MAX), p_marker, "")
	entries[hex].permanent = true
	if glaze:
		entries[hex].glaze = int(HHTune.value("charge_glaze_ticks"))
		entries[hex].permanent_glaze = true


## Apply an arena's authored rows (H43). `reform` = only re-lay what is missing
## (vents and lava re-form after play changes them, H44).
func author_rows(rows: Array, reform: bool = false) -> void:
	for r in rows:
		var hex := Vector2i(int(r.q), int(r.r))
		if reform and entries.has(hex):
			continue
		author(hex, int(r.get("h", 0)), int(r.get("v", 0)), str(r.get("marker", "")), bool(r.get("glaze", false)))


func clear(hex: Vector2i) -> void:
	entries.erase(hex)


## Apply one action's element to a shape, simultaneously. `fresh` = a cast
## (false = propagated spread: never fires a marker, skips glazed hexes).
## Returns { detonations: [{hex, pct, points, source, mix}], changed: [hex],
##   marker_fired: [hex], gales: [{origin, copies}], doused: [hex],
##   overheat: [{hex, ring}], overfreeze: [{hex, ring, pct}] }
func apply(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	var out := { "detonations": [], "changed": [], "marker_fired": [], "gales": [], "doused": [], "overheat": [], "overfreeze": [] }
	var hot := _overheat_begin(hexes, element, fresh)
	var frz := _overfreeze_begin(hexes, element, fresh)
	var plans := {}
	for hex in hexes:
		if not can_hold(hex) or plans.has(hex):
			continue
		if not fresh and is_glazed(hex):
			continue
		plans[hex] = _route(at(hex), element, fresh, steps, caster)
	var gales: Array = []
	var keys := plans.keys()
	keys.sort()
	for hex in keys:
		var p: Dictionary = plans[hex]
		if p.op == "none":
			continue
		if p.op == "erase":
			entries.erase(hex)
		else:
			entries[hex] = p.entry
		out.changed.append(hex)
		if p.has("detonate"):
			out.detonations.append({ "hex": hex, "mult": float(p.detonate), "pct": float(p.detonate), "source": str(p.get("det_source", caster)),
				"points": int(p.get("det_points", 0)), "mix": p.get("det_mix", {}) })
		if p.has("gale"):
			gales.append([hex, p.gale])
		if p.get("fired", false):
			out.marker_fired.append(hex)
		if p.get("doused", false):
			out.doused.append(hex)
	_overfreeze_finish(frz, caster, out)
	_overheat_finish(hot, caster, out)
	for g in gales:
		var copies := _gale_copy(g[0], g[1], caster, out.changed)
		out.gales.append({ "origin": g[0], "copies": copies })
	return out


## Fire melting glaze: a Shatter hit breaks the glaze (the charge stays).
func break_glaze(hex: Vector2i) -> bool:
	var e := at(hex)
	if e.is_empty() or int(e.get("glaze", 0)) <= 0:
		return false
	e.glaze = 0
	return true


## The per-tick decay. Returns the hexes whose entry vanished this tick.
func tick() -> Array:
	var gone: Array = []
	var step_ticks := int(HHTune.value("charge_step_ticks"))
	for hex in entries.keys():
		var e: Dictionary = entries[hex]
		if e.permanent:
			if bool(e.get("permanent_glaze", false)) and int(e.glaze) <= 0:
				e.glaze = int(HHTune.value("charge_glaze_ticks"))   # authored shade: the frost re-forms
			continue
		if int(e.glaze) > 0:
			e.glaze = int(e.glaze) - 1
			continue
		e.timer = int(e.timer) - 1
		if int(e.timer) > 0:
			continue
		if e.marker != "":
			entries.erase(hex)
			gone.append(hex)
			continue
		var ah := absi(int(e.h))
		var av := absi(int(e.v))
		if ah >= av:
			e.h = int(e.h) - signi(int(e.h))
		if av >= ah:
			e.v = int(e.v) - signi(int(e.v))
		if int(e.h) == 0 and int(e.v) == 0:
			entries.erase(hex)
			gone.append(hex)
		else:
			e.timer = step_ticks
	return gone


# ------------------------------------------------------------------ internals

func _entry(h: int, v: int, p_marker: String, source: String) -> Dictionary:
	return { "h": h, "v": v, "marker": p_marker, "glaze": 0,
		"timer": int(HHTune.value("charge_mark_ticks")) if p_marker != "" else int(HHTune.value("charge_step_ticks")),
		"source": source, "permanent": false }


## Pure: what would `element` arriving do to entry `e`?
func _route(e: Dictionary, element: String, fresh: bool, steps: int, caster: String) -> Dictionary:
	var h: int = int(e.get("h", 0))
	var v: int = int(e.get("v", 0))
	var mk_here: String = str(e.get("marker", ""))
	var glaze: int = int(e.get("glaze", 0))
	var is_charged := h != 0 or v != 0
	var src := str(e.get("source", caster))

	if element in AXIS:
		if glaze > 0:
			if element == "fire":                 # fire melts the glaze, and is spent
				var melted := e.duplicate()
				melted.glaze = 0
				melted.permanent = false
				return { "op": "set", "entry": melted }
			return { "op": "none" }               # everything else washes off
		var nh := h
		var nv := v
		match element:
			"fire": nh += steps
			"water": nh -= steps
			"light": nv += steps
			"dark": nv -= steps
		nh = clampi(nh, -AXIS_MAX, AXIS_MAX)
		nv = clampi(nv, -AXIS_MAX, AXIS_MAX)
		var douse := mk_here == "" and ((element == "fire" and h < 0) or (element == "water" and h > 0))
		if douse:
			if nv == 0:
				return { "op": "erase", "doused": true }
			return { "op": "set", "doused": true, "entry": _entry(0, nv, "", src) }
		if mk_here != "":
			if not fresh:
				return { "op": "none" }           # containment: spread never fires a marker
			var arrived := _entry(nh, nv, "", caster)
			var p := _operate(arrived, mk_here, src)
			p["fired"] = true
			return p
		if nh == 0 and nv == 0:
			return { "op": "erase" }
		return { "op": "set", "entry": _entry(nh, nv, "", caster) }

	var mk: String = OPERATORS.get(element, "")
	if mk == "":
		return { "op": "none" }
	if not is_charged:
		if mk_here == "fuse" and mk != "fuse":
			if not fresh:
				return { "op": "none" }
			var p := _operate(e.duplicate(), "fuse", src)   # ice or wind sets off the empty fuse
			p["fired"] = true
			return p
		return { "op": "set", "entry": _entry(0, 0, mk, caster) }   # arm or replace
	if glaze > 0 and element == "wind":
		return { "op": "none" }
	return _operate(e.duplicate(), mk, caster)


func _operate(e: Dictionary, mk: String, src: String) -> Dictionary:
	match mk:
		"fuse":
			var water := maxi(-int(e.h), 0)
			var pts := absi(int(e.h)) + absi(int(e.v))
			var axes := (1 if int(e.h) != 0 else 0) + (1 if int(e.v) != 0 else 0)
			var mult := HHTune.value("det_mult_per_point") * pts + HHTune.value("det_mult_per_axis") * maxi(axes - 1, 0) \
				+ HHTune.value("det_mult_per_water") * water          # H50: x the caster's auto attack
			if int(e.get("glaze", 0)) > 0:
				mult *= SHATTER_MULT
			return { "op": "erase", "detonate": mult, "det_source": src, "det_points": pts, "det_mix": blast_mix(e) }
		"stasis":
			e.glaze = int(HHTune.value("charge_glaze_ticks"))
			e.permanent = false
			return { "op": "set", "entry": e }
		"gale":
			e.permanent = false
			return { "op": "set", "entry": e, "gale": [int(e.h), int(e.v)] }
	return { "op": "none" }


func _gale_copy(origin: Vector2i, hv: Array, caster: String, changed: Array) -> Array:
	var copies: Array = []
	for n in arena.ring(origin, 1):
		if not can_hold(n) or n in changed:
			continue
		var cur := at(n)
		if not cur.is_empty() and (cur.marker != "" or int(cur.glaze) > 0):
			continue
		var copy := _entry(int(hv[0]), int(hv[1]), "", caster)
		copy.timer = int(HHTune.value("charge_gale_ticks"))
		entries[n] = copy
		changed.append(n)
		copies.append(n)
	return copies


func _overheat_begin(hexes: Array, element: String, fresh: bool) -> Array:
	var out: Array = []
	if not fresh or element != "fire":
		return out
	for h in hexes:
		if h in out or not can_hold(h) or is_glazed(h) or marker(h) != "":
			continue
		if intensity(h, "fire") >= AXIS_MAX:
			out.append(h)
	out.sort()
	return out


func _overheat_finish(centres: Array, caster: String, out: Dictionary) -> void:
	for c in centres:
		var painted: Array = []
		for n in arena.ring(c, 1):
			if n in centres or not can_hold(n) or is_glazed(n) or marker(n) != "":
				continue
			var p := _route(at(n), "fire", false, OVERHEAT_RING_STEPS, caster)
			if p.op == "set":
				entries[n] = p.entry
			elif p.op == "erase":
				entries.erase(n)
			else:
				continue
			painted.append(n)
			if not n in out.changed:
				out.changed.append(n)
		if entries.has(c):
			entries[c].h = OVERHEAT_VENT_TO
		out.overheat.append({ "hex": c, "ring": painted, "mult": HHTune.value("overheat_mult"), "pct": HHTune.value("overheat_mult"), "source": caster })


func _overfreeze_begin(hexes: Array, element: String, fresh: bool) -> Array:
	var out: Array = []
	if not fresh or element != "ice":
		return out
	for h in hexes:
		var e := at(h)
		if h in out or not can_hold(h) or e.is_empty():
			continue
		if int(e.h) < 0 and int(e.glaze) > 0 and str(e.marker) == "":
			out.append(h)
	out.sort()
	return out


func _overfreeze_finish(centres: Array, caster: String, out: Dictionary) -> void:
	var glaze_ticks := int(HHTune.value("charge_glaze_ticks"))
	for c in centres:
		var glazed: Array = []
		for n in arena.ring(c, 1):
			if n in centres or not can_hold(n):
				continue
			var cur := at(n)
			if not cur.is_empty() and (cur.marker != "" or int(cur.glaze) > 0):
				continue
			if cur.is_empty():
				var sheet := _entry(-1, 0, "", caster)
				sheet.glaze = glaze_ticks
				entries[n] = sheet
			else:
				cur.glaze = glaze_ticks
				cur.permanent = false
			glazed.append(n)
			if not n in out.changed:
				out.changed.append(n)
		out.overfreeze.append({ "hex": c, "ring": glazed, "mult": HHTune.value("overfreeze_mult"), "pct": HHTune.value("overfreeze_mult"), "source": caster })
