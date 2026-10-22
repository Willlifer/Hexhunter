class_name HHCharge
extends RefCounted
## Elements on the ground: Black | White's charge grid (BWTiles, ELEMENTS.md
## §2-§6) rebuilt for a real-time arena, then the element pass (Lane EL, spec
## sections 1-3, H360-H389). Pure state and rules. It reports what happened
## (detonations, bursts, eruptions, shatters, a Swirl) and HHSim turns those
## into damage through ONE rule (HHSim.reaction_hit, spec 3.3), because only
## the sim knows the units.
##
## A hex with nothing on it has no entry. An entry:
##   { h, v, marker, glaze, timer, source, permanent [, crystal, crystal_t] }
## h: water(-3)..fire(+3), v: dark(-3)..light(+3). marker: "" | "fuse" (thunder)
## | "stasis" (ice) | "gale" (wind). glaze: ticks of authored frost left (the
## cave's shade). timer: ticks until the next decay step (or until an unfired
## marker fades). crystal: the ice level 1..3 of an Elemental Crystal holding
## the hex's charge; crystal_t: ticks until it thaws back into plain charge.
##
## CONTAINMENT (spec 0.3, written before every rule): nothing chain-reacts.
## One ACTION is one caster's paints in one tick (HHSim.paint calls
## begin_action). In an action every hex reacts at most once, and a reaction's
## output (a ring splash, fragments, a Swirl's landing, gale copies) never
## reacts in that action: those hexes are `_reacted` / `_produced` and any
## further element landing on them is laid like spread (it nets, fires no
## marker, bursts and erupts nothing). Direct callers that never declare an
## action get a fresh one per apply().
##
## The rules (who gets hurt and how hard is HHSim's single 3.3 rule):
##   Fuse / Detonate (thunder, H2, unchanged): thunder on charge detonates it
##         (H50: x3 per point, +3 per extra axis, +1 per water conducted); an
##         element arriving on an armed fuse sets it off; thunder on empty
##         ground arms a fuse.
##   Tier-3 bursts (spec 2.3, 2.5, H263): a fresh element landing on its own
##         tier 3 bursts once: fire = Overheat (ring +2 fire, kept), water =
##         Geyser (massive stagger), light = Glint (a dazzle stagger), dark =
##         Flux (the monster vulnerable). Each splashes its element onto the
##         ring (contained) and vents the centre to 2.
##   Steam (spec 3.1, H420, the author): a fresh fire or water meeting its
##         opposite on a hex at steam_min_tier (1: EVERY contact) or more
##         consumes all fire and water there and erupts: HHFormulas.steam_mult
##         by T = consumed (2..6), x2.5 .. x18 today. A fresh cast no longer
##         douses or evaporates (spread and contained output still net).
##   Eclipse (spec 3.2, H362, H425): light meeting dark at eclipse_min_tier
##         (2) or more consumes that axis and erupts (consumed x
##         eclipse_aa_mult_per_point) and exposes the monster; tier 1 only nets.
##   Every reaction reads only its own HHTune keys (H423).
##   Crystal / Shatter (spec 2.2, H261, H264): ice on EMPTY ground still arms a
##         stasis marker (the old tier-1 "glaze"); ice on a CHARGED tile (or an
##         element landing on armed ice) freezes it into a crystal: decay
##         stops, it walls hunters, a monster crushes it. Its own axis and ice
##         feed it up to axis 3 / ice 3; past a cap it shatters, and so does
##         any other element (thunder included), a hunter's weapon hit or a
##         monster walking onto it. Shatter: per_point x stored charge +
##         per_ice x ice, heavy stagger, fragments splash tier 1 of the stored
##         element(s) onto the ring (contained). Wind does nothing to it.
##   Swirl (spec 2.1): wind on empty ground arms a gale marker; an element on
##         a gale marker spreads it to the ring (kept). Wind landing on plain
##         charge pulls every plain charge within the pull radius of the
##         cast's centre (2, or 3 for a wide area) inward: per element sums,
##         opposites meeting erupt (Steam / Eclipse) or net, each axis capped
##         at 3, laid on the centre or the nearest free ring hex; pulled hexes
##         clear. A condensed tier 3 fires that element's burst once without
##         its ring splash ("Swirl's reaction does not spread"); with no
##         reaction the condensed charge spreads tier 1 one ring outward.
##   Authored frost (H43): permanent glaze on the cave's shade: decay paused,
##         fire melts it, other axis elements wash off, thunder detonates it
##         x1.5, ice crystallises it.

const AXIS_MAX := 3
const ICE_MAX := 3
const AXIS := ["fire", "water", "light", "dark"]
const OPPOSITE := { "fire": "water", "water": "fire", "light": "dark", "dark": "light" }
const OPERATORS := { "thunder": "fuse", "ice": "stasis", "wind": "gale" }
const MARKER_ELEMENT := { "fuse": "thunder", "stasis": "ice", "gale": "wind" }
const BURST := { "fire": "overheat", "water": "geyser", "light": "glint", "dark": "flux" }
const ERUPTION := { "fire": "steam", "water": "steam", "light": "eclipse", "dark": "eclipse" }
const BURST_VENT_TO := 2

var arena: HHArena
var entries := {}
var _action := ""                   # the declared action ("" = each apply() is its own)
var _reacted := {}                  # hex -> true: reacted (or a Swirl centre / landing) this action
var _produced := {}                 # hex -> true: reaction output landed here this action


func _init(p_arena: HHArena) -> void:
	arena = p_arena


# ------------------------------------------------------------------ containment

## Declare the action the next apply() / shatter_at() calls belong to. A new
## key starts a clean slate; the same key keeps it (a cast's strength groups).
func begin_action(key: String) -> void:
	if key != _action:
		_action = key
		_reacted = {}
		_produced = {}


func reacted(hex: Vector2i) -> bool:
	return _reacted.has(hex)


func produced(hex: Vector2i) -> bool:
	return _produced.has(hex)


func _held(hex: Vector2i) -> bool:
	return _reacted.has(hex) or _produced.has(hex)


# ------------------------------------------------------------------ reading

func at(hex: Vector2i) -> Dictionary:
	return entries.get(hex, {})


static func amount(h: int, v: int, element: String) -> int:
	match element:
		"fire": return maxi(h, 0)
		"water": return maxi(-h, 0)
		"light": return maxi(v, 0)
		"dark": return maxi(-v, 0)
	return 0


func intensity(hex: Vector2i, element: String) -> int:
	var e := at(hex)
	if e.is_empty():
		return 0
	return amount(int(e.h), int(e.v), element)


func is_glazed(hex: Vector2i) -> bool:
	return int(at(hex).get("glaze", 0)) > 0


## The crystal's ice level on `hex` (0 = no crystal).
func crystal(hex: Vector2i) -> int:
	return int(at(hex).get("crystal", 0))


func is_crystal(hex: Vector2i) -> bool:
	return crystal(hex) > 0


## Every crystal hex, sorted.
func crystals() -> Array:
	var out: Array = []
	for h in entries:
		if int((entries[h] as Dictionary).get("crystal", 0)) > 0:
			out.append(h)
	out.sort()
	return out


func marker(hex: Vector2i) -> String:
	return str(at(hex).get("marker", ""))


func charged(hex: Vector2i) -> bool:
	var e := at(hex)
	return not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0)


## Plain charge a Swirl may pull: charged, no marker, not frozen (crystal or
## authored frost), not the biome's permanent ground, not touched by a
## reaction this action.
func pullable(hex: Vector2i) -> bool:
	var e := at(hex)
	if e.is_empty() or (int(e.h) == 0 and int(e.v) == 0) or str(e.marker) != "":
		return false
	if int(e.get("crystal", 0)) > 0 or int(e.glaze) > 0 or bool(e.get("permanent", false)):
		return false
	return not _held(hex)


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
		"ice": return e.marker == "stasis" or int(e.glaze) > 0 or int(e.get("crystal", 0)) > 0
	return false


## Speed multiplier for whoever walks here (water slows; frozen water is ice,
## walkable at full speed).
func move_mult(hex: Vector2i, who: String = "") -> float:
	if is_glazed(hex) or is_crystal(hex) or (who != "" and owned_by(hex, who)):
		return 1.0
	var slow: Array = HHTune.list("water_slow")
	return float(slow[clampi(intensity(hex, "water"), 0, slow.size() - 1)])


## Whose element this is (H33: your own never slows or hurts you).
func owned_by(hex: Vector2i, who: String) -> bool:
	return str(at(hex).get("source", "")) == who


## Per-second standing effects, in pct of max HP. Charge frozen in a crystal
## is inert.
func standing(hex: Vector2i) -> Dictionary:
	var frozen := is_crystal(hex)
	return {
		"source": str(at(hex).get("source", "")),
		"fire": 0.0 if frozen else HHTune.value("fire_stand_pct") * intensity(hex, "fire"),
		"heal": 0.0 if frozen else HHTune.value("light_heal_pct") * intensity(hex, "light"),
		"drain": HHTune.value("dark_drain_pct") if intensity(hex, "dark") >= 3 and not frozen else 0.0,
	}


func crossing_pct(hex: Vector2i) -> float:
	if is_crystal(hex):
		return 0.0
	return HHTune.value("fire_cross_pct") * intensity(hex, "fire")


func can_hold(hex: Vector2i) -> bool:
	return arena.exists(hex) and not arena.kind(hex) in ["rock", "pillar", "tree"]


## The stronger axis element of a charge (fire / water first on a tie), "" when bare.
static func dominant(h: int, v: int) -> String:
	if h == 0 and v == 0:
		return ""
	if absi(h) >= absi(v):
		return "fire" if h > 0 else "water"
	return "light" if v > 0 else "dark"


static func blast_mix(e: Dictionary) -> Dictionary:
	var out := {}
	var h := int(e.get("h", 0))
	var v := int(e.get("v", 0))
	if h != 0:
		out["fire" if h > 0 else "water"] = absi(h)
	if v != 0:
		out["light" if v > 0 else "dark"] = absi(v)
	if int(e.get("glaze", 0)) > 0 or int(e.get("crystal", 0)) > 0:
		out["ice"] = maxi(1, int(e.get("crystal", 0)))
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


static func _out() -> Dictionary:
	return { "detonations": [], "changed": [], "marker_fired": [], "gales": [], "doused": [], "overheat": [],
		"bursts": [], "eruptions": [], "shatters": [], "crystals": [], "swirl": {} }


## Apply one action's element to a shape, simultaneously. `fresh` = a cast
## (false = propagated spread: never fires a marker, never reacts, skips
## frozen hexes). Returns { detonations: [{hex, mult, points, source, mix}],
## changed: [hex], marker_fired: [hex], gales: [{origin, copies}], doused:
## [hex], bursts: [{hex, ring, painted, element, kind, mult, source, swirl}]
## (overheat: the fire ones), eruptions: [{hex, kind, consumed, mult, source}],
## shatters: [{hex, mult, points, ice, mix, source, ring}], crystals: [hex],
## swirl: {} or { centre, landing, radius, pulled, pulled_el, h, v, reaction,
## copies } }. `source` in a record is whose charge reacted (the 3.3 rule's
## owner); the trigger is `caster`.
func apply(hexes: Array, element: String, caster: String, steps: int = 1, fresh: bool = true) -> Dictionary:
	if _action == "":
		_reacted = {}
		_produced = {}
	var out := _out()
	if element == "wind" and fresh and _swirl(hexes, caster, out):
		return out
	var hot := _burst_begin(hexes, element, fresh)
	var plans := {}
	for hex in hexes:
		if not can_hold(hex) or plans.has(hex):
			continue
		var f := fresh and not _held(hex)
		if not f and (is_glazed(hex) or is_crystal(hex)):
			continue                                    # spread and contained output skip frozen hexes
		plans[hex] = _route(at(hex), element, f, steps, caster)
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
			_reacted[hex] = true
		if p.has("gale"):
			gales.append([hex, p.gale])
		if p.get("fired", false):
			out.marker_fired.append(hex)
		if p.get("doused", false):
			out.doused.append(hex)
		if p.has("erupt"):
			var er: Dictionary = p.erupt
			er["hex"] = hex
			out.eruptions.append(er)
			_reacted[hex] = true
		if p.has("shatter"):
			var sh: Dictionary = p.shatter
			sh["hex"] = hex
			out.shatters.append(sh)
			_reacted[hex] = true
		if p.get("crystal", false):
			out.crystals.append(hex)
	for sh in out.shatters:
		_fragments(sh, caster, out)
	_burst_finish(hot, element, caster, out)
	for g in gales:
		var copies := _gale_copy(g[0], g[1], caster, out.changed)
		out.gales.append({ "origin": g[0], "copies": copies })
	return out


## Fire melting glaze (the authored frost): the charge stays.
func break_glaze(hex: Vector2i) -> bool:
	var e := at(hex)
	if e.is_empty() or int(e.get("glaze", 0)) <= 0:
		return false
	e.glaze = 0
	return true


## Shatter every crystal in `hexes` as `caster`'s action (a weapon hit, a
## monster's crush, a monster's purge). Contained like apply().
func shatter_at(hexes: Array, caster: String) -> Dictionary:
	if _action == "":
		_reacted = {}
		_produced = {}
	var out := _out()
	var list := hexes.duplicate()
	list.sort()
	for hex in list:
		if not is_crystal(hex) or _held(hex):
			continue
		var sh: Dictionary = _shatter_plan(at(hex)).shatter
		sh["hex"] = hex
		entries.erase(hex)
		out.changed.append(hex)
		out.shatters.append(sh)
		_reacted[hex] = true
	for sh in out.shatters:
		_fragments(sh, caster, out)
	return out


## Sections 7-8 hook: every plain charged hex in `hexes` blasts as if thunder
## hit it (a fuse, H50's multiple), every crystal shatters, markers stay. One
## contained action.
func detonate_at(hexes: Array, caster: String) -> Dictionary:
	var out := shatter_at(hexes, caster)
	var list := hexes.duplicate()
	list.sort()
	for hex in list:
		if not charged(hex) or _held(hex) or str(at(hex).marker) != "":
			continue
		var p := _operate(at(hex).duplicate(), "fuse", str(at(hex).get("source", caster)))
		entries.erase(hex)
		out.changed.append(hex)
		out.detonations.append({ "hex": hex, "mult": float(p.detonate), "pct": float(p.detonate), "source": str(p.det_source),
			"points": int(p.det_points), "mix": p.det_mix })
		_reacted[hex] = true
	return out


## Sections 7-8 hook: clear everything in `hexes` (charge, markers, crystals,
## frost) with no reaction. Returns the hexes cleared.
func quench(hexes: Array) -> Array:
	var gone: Array = []
	for hex in hexes:
		if entries.has(hex):
			entries.erase(hex)
			gone.append(hex)
	gone.sort()
	return gone


## The per-tick decay. Returns the hexes whose entry vanished this tick.
func tick() -> Array:
	var gone: Array = []
	var step_ticks := int(HHTune.value("charge_step_ticks"))
	var glaze_ticks := int(HHTune.value("charge_glaze_ticks"))
	for hex in entries.keys():
		if not age_entry(entries[hex], step_ticks, glaze_ticks):
			entries.erase(hex)
			gone.append(hex)
	return gone


## One tick of decay on one entry, in place; false = it is gone. Static so a
## co-op mirror (HHSnapshot.age_charge) ages the grid by the very same rule.
static func age_entry(e: Dictionary, step_ticks: int, glaze_ticks: int) -> bool:
	if bool(e.get("permanent", false)):
		if bool(e.get("permanent_glaze", false)) and int(e.glaze) <= 0:
			e.glaze = glaze_ticks                   # authored shade: the frost re-forms
		return true
	if int(e.get("crystal", 0)) > 0:
		e.crystal_t = int(e.get("crystal_t", 0)) - 1
		if int(e.crystal_t) > 0:
			return true                             # decay paused inside the crystal
		e.erase("crystal")                          # it thaws back into plain charge
		e.erase("crystal_t")
		e.timer = step_ticks
		return int(e.h) != 0 or int(e.v) != 0
	if int(e.glaze) > 0:
		e.glaze = int(e.glaze) - 1
		return true
	e.timer = int(e.timer) - 1
	if int(e.timer) > 0:
		return true
	if str(e.marker) != "":
		return false
	var ah := absi(int(e.h))
	var av := absi(int(e.v))
	if ah >= av:
		e.h = int(e.h) - signi(int(e.h))
	if av >= ah:
		e.v = int(e.v) - signi(int(e.v))
	if int(e.h) == 0 and int(e.v) == 0:
		return false
	e.timer = step_ticks
	return true


# ------------------------------------------------------------------ internals

func _entry(h: int, v: int, p_marker: String, source: String) -> Dictionary:
	return { "h": h, "v": v, "marker": p_marker, "glaze": 0,
		"timer": int(HHTune.value("charge_mark_ticks")) if p_marker != "" else int(HHTune.value("charge_step_ticks")),
		"source": source, "permanent": false }


static func _add(h: int, v: int, element: String, steps: int) -> Vector2i:
	match element:
		"fire": h += steps
		"water": h -= steps
		"light": v += steps
		"dark": v -= steps
	return Vector2i(clampi(h, -AXIS_MAX, AXIS_MAX), clampi(v, -AXIS_MAX, AXIS_MAX))


## Pure: what would `element` arriving do to entry `e`?
func _route(e: Dictionary, element: String, fresh: bool, steps: int, caster: String) -> Dictionary:
	var h: int = int(e.get("h", 0))
	var v: int = int(e.get("v", 0))
	var mk_here: String = str(e.get("marker", ""))
	var glaze: int = int(e.get("glaze", 0))
	var is_charged := h != 0 or v != 0
	var src := str(e.get("source", caster))

	if int(e.get("crystal", 0)) > 0:
		return _crystal_route(e, element, steps)       # (only fresh elements get here)

	if element in AXIS:
		if glaze > 0:
			if element == "fire":                 # fire melts the authored frost, and is spent
				var melted := e.duplicate()
				melted.glaze = 0
				melted.permanent = false
				melted.erase("permanent_glaze")
				return { "op": "set", "entry": melted }
			return { "op": "none" }               # everything else washes off
		var opp: String = OPPOSITE[element]
		var t_opp := amount(h, v, opp)
		if mk_here == "" and t_opp > 0 and fresh and t_opp >= int(HHTune.value("%s_min_tier" % ERUPTION[element])):
			# Steam / Eclipse (H360s): the whole axis is consumed and erupts
			var consumed := t_opp + mini(steps, AXIS_MAX)
			var kind: String = ERUPTION[element]
			var nh2 := 0 if element in ["fire", "water"] else h
			var nv2 := 0 if element in ["light", "dark"] else v
			var er := { "kind": kind, "element": element, "consumed": consumed, "source": src,
				"mult": float(HHFormulas.eruption_mult(kind, consumed).value) }
			if nh2 == 0 and nv2 == 0:
				return { "op": "erase", "erupt": er }
			return { "op": "set", "erupt": er, "entry": _entry(nh2, nv2, "", src) }
		var n := _add(h, v, element, steps)
		var doused := mk_here == "" and t_opp > 0 and element in ["fire", "water"]   # H260: evaporated / doused, no reaction
		if mk_here != "":
			if not fresh:
				return { "op": "none" }           # containment: spread never fires a marker
			var arrived := _entry(n.x, n.y, "", caster)
			var p := _operate(arrived, mk_here, src)
			p["fired"] = true
			return p
		if n.x == 0 and n.y == 0:
			return { "op": "erase", "doused": doused }
		return { "op": "set", "entry": _entry(n.x, n.y, "", caster), "doused": doused }

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
		if not fresh and mk_here != "":
			return { "op": "none" }
		return { "op": "set", "entry": _entry(0, 0, mk, caster) }   # arm or replace
	if not fresh:
		return { "op": "none" }                   # containment: output is never operated on again
	if element == "ice":
		return _crystallise(e, steps, caster)
	if glaze > 0 and element == "wind":
		return { "op": "none" }
	return _operate(e.duplicate(), mk, caster)


## Ice on a charged tile (or a charge arriving on armed ice): an Elemental
## Crystal holding the charge. Never permanent; the authored frost goes.
func _crystallise(e: Dictionary, ice: int, caster: String) -> Dictionary:
	var ne := e.duplicate()
	ne.crystal = clampi(ice, 1, ICE_MAX)
	ne.crystal_t = int(HHTune.value("crystal_ticks"))
	ne.glaze = 0
	ne.permanent = false
	ne.erase("permanent_glaze")
	ne.source = caster
	return { "op": "set", "entry": ne, "crystal": true }


## H471 (Lane IC): what `element` landing on crystal entry `e` would do,
## read from the very rule apply() uses (_crystal_route), so the view and the
## HUD can say "this breaks it, x7" before the player acts. kind: "shatter",
## "feed" or "none" (wind); mult: the Shatter multiple it would fire (the
## overcharge case counts its capped ice), points / ice: what it stores now.
static func crystal_response(e: Dictionary, element: String, steps: int = 1) -> Dictionary:
	var pts := mini(absi(int(e.get("h", 0))), AXIS_MAX) + mini(absi(int(e.get("v", 0))), AXIS_MAX)
	var ice := clampi(int(e.get("crystal", 1)), 1, ICE_MAX)
	var out := { "kind": "none", "mult": 0.0, "points": pts, "ice": ice }
	if int(e.get("crystal", 0)) <= 0:
		return out
	var p := _crystal_route(e, element, steps)
	if p.has("shatter"):
		out.kind = "shatter"
		out.mult = float((p.shatter as Dictionary).mult)
	elif str(p.op) == "set":
		out.kind = "feed"
	return out


## The Shatter multiple a crystal entry holds right now (its size, H471).
static func crystal_mult(e: Dictionary) -> float:
	return float((_shatter_plan(e).shatter as Dictionary).mult)


## An element landing on a crystal: its own axis and ice feed it (past a cap
## it shatters, DECIDE-E); wind passes; anything else breaks it.
static func _crystal_route(e: Dictionary, element: String, steps: int) -> Dictionary:
	if element == "wind":
		return { "op": "none" }
	var h := int(e.h)
	var v := int(e.v)
	var cr := int(e.crystal)
	if element == "ice":
		if cr + steps > ICE_MAX:
			var capped := e.duplicate()
			capped.crystal = ICE_MAX
			return _shatter_plan(capped)
		var fed := e.duplicate()
		fed.crystal = cr + steps
		fed.crystal_t = int(HHTune.value("crystal_ticks"))
		return { "op": "set", "entry": fed }
	if element in AXIS and amount(h, v, element) > 0:
		if amount(h, v, element) + steps > AXIS_MAX:
			return _shatter_plan(e)
		var n := _add(h, v, element, steps)
		var fed2 := e.duplicate()
		fed2.h = n.x
		fed2.v = n.y
		return { "op": "set", "entry": fed2 }
	return _shatter_plan(e)


static func _shatter_plan(e: Dictionary) -> Dictionary:
	var pts := mini(absi(int(e.h)), AXIS_MAX) + mini(absi(int(e.v)), AXIS_MAX)
	var ice := clampi(int(e.get("crystal", 1)), 1, ICE_MAX)
	return { "op": "erase", "shatter": { "mult": float(HHFormulas.shatter_mult(pts, ice).value), "points": pts, "ice": ice,
		"mix": blast_mix(e), "source": str(e.get("source", "")), "ring": [] } }


## Shatter's fragments: tier 1 of each stored element onto the ring, still
## the crystal owner's charge (a monster crushing a hunter's crystal scatters
## the hunter's fire, which never burns that hunter, H33). Contained: a
## splash, never a reaction, never another Shatter.
func _fragments(sh: Dictionary, caster: String, out: Dictionary) -> void:
	var steps := int(HHTune.value("shatter_splash_steps"))
	var owner := str(sh.get("source", ""))           # the fragments are the crystal's own charge: its owner's
	if owner == "":
		owner = caster
	var ring: Array = []
	for n in arena.ring(sh.hex, 1):
		var hit := false
		for el in ["fire", "water", "light", "dark"]:
			if int((sh.mix as Dictionary).get(el, 0)) > 0 and _splash(n, el, steps, owner, out):
				hit = true
		if hit:
			ring.append(n)
	sh.ring = ring


func _operate(e: Dictionary, mk: String, src: String) -> Dictionary:
	match mk:
		"fuse":
			var water := maxi(-int(e.h), 0)
			var pts := absi(int(e.h)) + absi(int(e.v))
			var axes := (1 if int(e.h) != 0 else 0) + (1 if int(e.v) != 0 else 0)
			var mult: float = HHFormulas.fuse_mult(pts, axes, water, int(e.get("glaze", 0)) > 0).value   # H50: x the caster's auto attack
			return { "op": "erase", "detonate": mult, "det_source": src, "det_points": pts, "det_mix": blast_mix(e) }
		"stasis":
			return _crystallise(e, 1, str(e.get("source", src)))
		"gale":
			e.permanent = false
			return { "op": "set", "entry": e, "gale": [int(e.h), int(e.v)] }
	return { "op": "none" }


func _gale_copy(origin: Vector2i, hv: Array, caster: String, changed: Array) -> Array:
	var copies: Array = []
	for n in arena.ring(origin, 1):
		if not can_hold(n) or n in changed or _held(n):
			continue
		var cur := at(n)
		if not cur.is_empty() and (cur.marker != "" or int(cur.glaze) > 0 or int(cur.get("crystal", 0)) > 0):
			continue
		var copy := _entry(int(hv[0]), int(hv[1]), "", caster)
		copy.timer = int(HHTune.value("charge_gale_ticks"))
		entries[n] = copy
		changed.append(n)
		copies.append(n)
		_produced[n] = true
	return copies


## A contained write (reaction output): add `steps` of `element` to `hex` by
## plain netting. Skips markers, crystals and frost; never reacts. True when
## the hex changed.
func _splash(hex: Vector2i, element: String, steps: int, caster: String, out: Dictionary) -> bool:
	if not can_hold(hex) or steps <= 0:
		return false
	var e := at(hex)
	if not e.is_empty() and (str(e.marker) != "" or int(e.glaze) > 0 or int(e.get("crystal", 0)) > 0):
		return false
	var n := _add(int(e.get("h", 0)), int(e.get("v", 0)), element, steps)
	if n.x == 0 and n.y == 0:
		if e.is_empty():
			return false
		entries.erase(hex)
	else:
		entries[hex] = _entry(n.x, n.y, "", caster)
	_produced[hex] = true
	if not hex in out.changed:
		out.changed.append(hex)
	return true


# ------------------------------------------------------------------ tier-3 bursts

func _burst_begin(hexes: Array, element: String, fresh: bool) -> Array:
	var out: Array = []
	if not fresh or not element in AXIS:
		return out
	for h in hexes:
		if h in out or not can_hold(h) or is_glazed(h) or is_crystal(h) or marker(h) != "" or _held(h):
			continue
		if intensity(h, element) >= AXIS_MAX:
			out.append(h)
	out.sort()
	return out


func _burst_finish(centres: Array, element: String, caster: String, out: Dictionary) -> void:
	for c in centres:
		var e := at(c)
		if e.is_empty() or amount(int(e.h), int(e.v), element) <= 0:
			continue
		var owner := str(e.get("source", caster))
		var painted: Array = []
		var steps := int(HHTune.value("%s_splash_steps" % BURST[element]))
		for n in arena.ring(c, 1):
			if n in centres:
				continue
			if _splash(n, element, steps, caster, out):
				painted.append(n)
		_vent(c, element)
		_reacted[c] = true
		_record_burst(c, element, owner, caster, painted, false, out)


func _vent(c: Vector2i, element: String) -> void:
	if not entries.has(c):
		return
	var e: Dictionary = entries[c]
	if element in ["fire", "water"]:
		e.h = BURST_VENT_TO * signi(int(e.h))
	else:
		e.v = BURST_VENT_TO * signi(int(e.v))


func _record_burst(c: Vector2i, element: String, owner: String, caster: String, painted: Array, swirl: bool, out: Dictionary) -> void:
	var kind: String = BURST[element]
	var ring: Array = []
	for n in arena.ring(c, 1):
		if arena.exists(n):
			ring.append(n)
	var mult := float(HHFormulas.burst_mult(kind).value) * (HHTune.value("swirl_reaction_mult") if swirl else 1.0)
	var rec := { "hex": c, "ring": ring, "painted": painted, "element": element, "kind": kind, "swirl": swirl,
		"mult": mult, "pct": mult, "source": owner, "trigger": caster }
	out.bursts.append(rec)
	if element == "fire":
		out.overheat.append(rec)


# ------------------------------------------------------------------ Swirl (spec 2.1)

## The cast's centre: the shape hex nearest the shape's mean position (ties: row, then column).
func centre_of(shape: Array) -> Vector2i:
	var sum := Vector2.ZERO
	for h in shape:
		sum += HHHex.to_world(h)
	var mean := sum / float(maxi(1, shape.size()))
	var best: Vector2i = shape[0]
	var bk := []
	for h in shape:
		var k := [snappedf(HHHex.to_world(h).distance_squared_to(mean), 1e-4), h.y, h.x]
		if bk.is_empty() or HHSim._key_less(k, bk):
			bk = k
			best = h
	return best


## Pull radius: swirl_radius_area for a wide, compact area (at least
## swirl_area_min_hexes hexes filling most of the disk round its centre),
## else swirl_radius_line (a basic, a line, a band).
func swirl_radius(shape: Array, centre: Vector2i) -> int:
	var spread := 0
	for h in shape:
		spread = maxi(spread, HHHex.distance(centre, h))
	var disk := 1 + 3 * spread * (spread + 1)
	var wide := shape.size() >= int(HHTune.value("swirl_area_min_hexes")) and float(shape.size()) >= 0.6 * float(disk)
	return int(HHTune.value("swirl_radius_area" if wide else "swirl_radius_line"))


## Wind cast on `hexes`: Swirl when any of them holds plain charge. True when
## the wind was spent here (a Swirl, or a centre already swirled this action).
func _swirl(hexes: Array, caster: String, out: Dictionary) -> bool:
	var shape: Array = []
	for h in hexes:
		if can_hold(h) and not h in shape:
			shape.append(h)
	if shape.is_empty() or not shape.any(func(h): return pullable(h)):
		return false
	var centre := centre_of(shape)
	if _reacted.has(centre):
		return true                                   # containment: a Swirl centre is not swirled again this action
	var r := swirl_radius(shape, centre)
	var area := arena.area(centre, r)
	area.sort()
	var sums := { "fire": 0, "water": 0, "light": 0, "dark": 0 }
	var pulled: Array = []
	var pulled_el := {}
	for h in area:
		if not pullable(h):
			continue
		var e := at(h)
		for el in sums:
			sums[el] = int(sums[el]) + amount(int(e.h), int(e.v), el)
		pulled.append(h)
		pulled_el[h] = dominant(int(e.h), int(e.v))
	if pulled.is_empty():
		return false
	for h in pulled:
		entries.erase(h)
		out.changed.append(h)
	var landing := _landing(centre)
	_reacted[centre] = true
	if landing == HHSim.NO_HEX:
		out.swirl = { "centre": centre, "landing": centre, "radius": r, "pulled": pulled, "pulled_el": pulled_el, "h": 0, "v": 0, "reaction": "", "copies": [] }
		return true
	_reacted[landing] = true
	# condense: per axis, opposites meeting at tier 2+ erupt, else they net; capped at 3
	var f := int(sums.fire)
	var w := int(sums.water)
	var li := int(sums.light)
	var d := int(sums.dark)
	var min_steam := int(HHTune.value("steam_min_tier"))
	var min_ecl := int(HHTune.value("eclipse_min_tier"))
	var h_net := clampi(f - w, -AXIS_MAX, AXIS_MAX)
	var v_net := clampi(li - d, -AXIS_MAX, AXIS_MAX)
	var cands: Array = []                             # [mult, order, kind, data]
	if f > 0 and w > 0 and maxi(f, w) >= min_steam:
		var cs := mini(f + w, 2 * AXIS_MAX)
		cands.append([float(HHFormulas.eruption_mult("steam", cs).value), 0, "steam", cs])
	if li > 0 and d > 0 and maxi(li, d) >= min_ecl:
		var ce := mini(li + d, 2 * AXIS_MAX)
		cands.append([float(HHFormulas.eruption_mult("eclipse", ce).value), 1, "eclipse", ce])
	if absi(h_net) >= AXIS_MAX:
		var el_h := "fire" if h_net > 0 else "water"
		cands.append([float(HHFormulas.burst_mult(BURST[el_h]).value), 2, "burst", el_h])
	if absi(v_net) >= AXIS_MAX:
		var el_v := "light" if v_net > 0 else "dark"
		cands.append([float(HHFormulas.burst_mult(BURST[el_v]).value), 3, "burst", el_v])
	var pick: Array = []
	for cd in cands:
		if pick.is_empty() or float(cd[0]) > float(pick[0]) + 1e-9:
			pick = cd
	var nh := h_net
	var nv := v_net
	var kind := ""
	if not pick.is_empty():
		kind = str(pick[2])
		if kind == "steam":
			nh = 0
		elif kind == "eclipse":
			nv = 0
	if nh != 0 or nv != 0:
		entries[landing] = _entry(nh, nv, "", caster)
		out.changed.append(landing)
	var copies: Array = []
	if kind == "steam" or kind == "eclipse":
		out.eruptions.append({ "hex": landing, "kind": kind, "element": "fire" if kind == "steam" else "light", "consumed": int(pick[3]),
			"mult": float(pick[0]) * HHTune.value("swirl_reaction_mult"), "source": caster, "swirl": true })
	elif kind == "burst":
		var el: String = pick[3]
		kind = str(BURST[el])
		_vent(landing, el)
		_record_burst(landing, el, caster, caster, [], true, out)
	elif nh != 0 or nv != 0:
		# no reaction: spread the condensed charge one ring outward, tier 1
		var ch := signi(nh)
		var cv := signi(nv)
		copies = _gale_copy(landing, [ch, cv], caster, [])
		for n in copies:
			if not n in out.changed:
				out.changed.append(n)
	out.swirl = { "centre": centre, "landing": landing, "radius": r, "pulled": pulled, "pulled_el": pulled_el, "h": nh, "v": nv,
		"reaction": kind, "copies": copies }
	return true


## Where a Swirl lays the condensed charge: the centre when it is free (bare,
## or just emptied), else the first free hex of its ring.
func _landing(centre: Vector2i) -> Vector2i:
	if can_hold(centre) and at(centre).is_empty():
		return centre
	var ring := arena.ring(centre, 1)
	ring.sort()
	for n in ring:
		if can_hold(n) and at(n).is_empty() and not _held(n):
			return n
	return HHSim.NO_HEX
