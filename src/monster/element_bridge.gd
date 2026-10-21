class_name HHElementBridge
extends RefCounted
## Lane M (H400-H419): the ONE place the NORMAL-tier monster mechanics touch
## the element rules. Everything in HHTierBrain that paints, quenches,
## detonates, siphons or asks "is this a block?" goes through here.
##
## Repointed at Lane EL's element API by Lane Q (H421, LEDGER L-54 settled):
##
##   paint_own(sim, u, hexes, element, tier)
##     An OVERRIDE (spec 7.2: no reaction), source = the monster (H33: it
##     never hurts itself); authored permanent cells are left alone. Axis
##     elements set h / v to +-tier; thunder = an armed fuse; wind = a gale
##     marker; ice = water at that tier under frost (`glaze`, EL's frozen-ground
##     entry: decay paused, walkable, fire melts it, thunder x det_frost_mult).
##     NOT an EL Crystal (H421): a crystal walls hunters and the monster's own
##     hull crushes it, so a hull pulse would shatter under its own next step
##     and a 2-turn ice sweep would wall the arena.
##   quench(sim, u, hexes, steps)
##     ONE contained action, monster-triggered (sim.charge.begin_action):
##     every plain hunter fire in reach meets the wave's water and erupts as
##     Steam (H420: every fire / water contact; HHFormulas.steam_mult), damage
##     by the 3.3 rule (sim.resolve_ground -> reaction_hit: the monster 25 %,
##     hunters 20 %, never below 1 HP); then water `steps` is laid over the
##     rest like spread (fresh = false): no marker fires, frost and crystals
##     are skipped, nothing chains. EL's react_at(.., "quench") is not used:
##     it erases markers and crystals, and the Quench Wave keeps them (H406).
##   discharge(sim, u, hexes)
##     sim.react_at(charged hexes, monster, "detonate"): EL's contained
##     detonate with the monster as the trigger. Every plain charged hex
##     blasts (H50's fuse multiple), every crystal shatters, markers stay;
##     reaction_hit (3.3) decides who is hurt and how much. No hand-landed
##     damage any more (DECIDE-C's pass and tier_roar_player_mult are gone).
##   siphon(sim, u, hexes, element) -> points
##     sums `element` intensity on foreign hexes and clears them.
##   is_block(sim, hex) / block_hexes(sim, hexes) / break_block(sim, hex, by)
##     A block: a hunter holding the lance's E Guard, arena rock / pillar /
##     tree cells, and EL's crystals (sim.crystal_at). break_block: a pillar
##     takes sim.damage_cells; a crystal shatters (sim.shatter_as, triggered
##     by `by`: 3.3); rock and trees never break.
##   carries(sim, hex, element) / foreign(sim, hex, u)
##     plain HHCharge reads.

const BLOCK_KINDS := ["rock", "pillar", "tree"]


## Override `hexes` with the monster's own element at `tier` (1..3).
static func paint_own(sim: HHSim, u: Dictionary, hexes: Array, element: String, tier: int) -> Array:
	var ch := sim.charge
	var changed: Array = []
	var t := clampi(tier, 1, HHCharge.AXIS_MAX)
	for h in hexes:
		if not ch.can_hold(h):
			continue
		var cur := ch.at(h)
		if not cur.is_empty() and bool(cur.get("permanent", false)):
			continue                                   # the biome's own cells stay (pond, vents, lava, shade)
		if ch.is_crystal(h):
			continue                                   # a crystal is a block: only a crush, a blow or break_block ends it (H421)
		var hv := Vector2i.ZERO
		var mk := ""
		var glaze := false
		match element:
			"fire": hv = Vector2i(t, 0)
			"water": hv = Vector2i(-t, 0)
			"light": hv = Vector2i(0, t)
			"dark": hv = Vector2i(0, -t)
			"ice":
				hv = Vector2i(-t, 0)
				glaze = true
			"thunder": mk = "fuse"
			"wind": mk = "gale"
			_: continue
		var e := { "h": hv.x, "v": hv.y, "marker": mk, "glaze": int(HHTune.value("charge_glaze_ticks")) if glaze else 0,
			"timer": int(HHTune.value("charge_mark_ticks")) if mk != "" else int(HHTune.value("charge_step_ticks")),
			"source": str(u.id), "permanent": false }
		ch.entries[h] = e
		changed.append(h)
	if not changed.is_empty():
		sim._emit({ "type": "paint", "id": u.id, "element": element, "hexes": changed.duplicate(), "changed": changed.duplicate(), "override": true })
	return changed


## The Quench Wave's water (spec 7.3): one contained, monster-triggered action.
## Returns HHCharge's report plus `steam` (the hexes that erupted).
static func quench(sim: HHSim, u: Dictionary, hexes: Array, steps: int) -> Dictionary:
	var ch := sim.charge
	ch.begin_action("%d:%s:quench" % [sim.tick, str(u.id)])
	var hot: Array = []
	for h in hexes:
		var e := ch.at(h)
		if e.is_empty() or bool(e.get("permanent", false)) or ch.is_crystal(h) or ch.is_glazed(h) or str(e.marker) != "":
			continue
		if ch.intensity(h, "fire") > 0 and str(e.get("source", "")) != str(u.id):
			hot.append(h)
	hot.sort()
	var r := ch.apply(hot, "water", str(u.id), steps, true) if not hot.is_empty() else HHCharge._out()
	var rest: Array = hexes.filter(func(h): return not h in hot)
	var r2 := ch.apply(rest, "water", str(u.id), steps, false)
	(r.changed as Array).append_array(r2.changed)
	(r.doused as Array).append_array(r2.doused)
	sim._emit({ "type": "paint", "id": u.id, "element": "water", "hexes": hexes.duplicate(), "changed": (r.changed as Array).duplicate(), "contained": true })
	sim.resolve_ground(r, str(u.id))
	r["steam"] = (r.eruptions as Array).map(func(x): return x.hex)
	ch.begin_action("")
	return r


## The Discharge Roar (spec 7.3): every charged hex in `hexes` detonates (and
## every crystal shatters) as one contained action triggered by the monster.
## Returns { detonated: [hex], players: { id: damage taken }, monster: damage taken }.
static func discharge(sim: HHSim, u: Dictionary, hexes: Array) -> Dictionary:
	var charged: Array = []
	for h in hexes:
		if sim.charge.charged(h) or sim.charge.is_crystal(h):
			charged.append(h)
	charged.sort()
	var out := { "detonated": [], "players": {}, "monster": 0.0 }
	if charged.is_empty():
		return out
	var before := {}
	for p in sim.standing_players():
		before[p.id] = float(p.hp)
	var mhp := float(u.hp)
	var r := sim.react_at(charged, str(u.id), "detonate")
	sim.charge.begin_action("")
	for d in r.detonations:
		(out.detonated as Array).append(d.hex)
	for s in r.shatters:
		(out.detonated as Array).append(s.hex)
	for id in before:
		var took := float(before[id]) - float(sim.unit(str(id)).hp)
		if took > 0.0:
			out.players[id] = took
	out.monster = maxf(0.0, mhp - float(u.hp))
	return out



## Drink `element` off `hexes` (spec 8.3). Returns the intensity points taken.
static func siphon(sim: HHSim, u: Dictionary, hexes: Array, element: String) -> int:
	var pts := 0
	var taken: Array = []
	for h in hexes:
		if not foreign(sim, h, u):
			continue
		var n := sim.charge.intensity(h, element)
		if n > 0:
			pts += n
			sim.charge.clear(h)
			taken.append(h)
	if not taken.is_empty():
		sim._emit({ "type": "paint", "id": u.id, "element": element, "hexes": taken.duplicate(), "changed": taken.duplicate(), "siphon": true })
	return pts


## A hex that stops a sweep (spec 8.2): rock / pillar / tree, a hunter
## holding the lance's Guard, or an Elemental Crystal (EL, H365).
static func is_block(sim: HHSim, hex: Vector2i) -> bool:
	if sim.arena.exists(hex) and str(sim.arena.kind(hex)) in BLOCK_KINDS:
		return true
	if sim.crystal_at(hex):
		return true
	for p in sim.standing_players():
		if p.hex == hex and int(p.get("guard", 0)) > 0 and str(p.get("weapon", "")) == "lance":
			return true
	return false


## The block hexes among `hexes`.
static func block_hexes(sim: HHSim, hexes: Array) -> Dictionary:
	var out := {}
	for h in hexes:
		if is_block(sim, h):
			out[h] = true
	return out


## A block took its last hit: break it if it breaks. Returns true if it broke.
## A crystal shatters as `by`'s action (3.3: a monster's sweep is monster-triggered).
static func break_block(sim: HHSim, hex: Vector2i, by: String = "") -> bool:
	if sim.crystal_at(hex):
		return not (sim.shatter_as([hex], by).shatters as Array).is_empty()
	if sim.arena.exists(hex) and str(sim.arena.kind(hex)) == "pillar":
		return not sim.damage_cells([hex], 1.0e9).is_empty()
	return false


## Does `hex` carry `element` (any tier, any source)?
static func carries(sim: HHSim, hex: Vector2i, element: String) -> bool:
	return sim.charge.carries(hex, element)


## Charge on `hex` that the monster did not lay and the arena did not author.
static func foreign(sim: HHSim, hex: Vector2i, u: Dictionary) -> bool:
	var e := sim.charge.at(hex)
	return not e.is_empty() and not bool(e.get("permanent", false)) and str(e.get("source", "")) != str(u.id)
