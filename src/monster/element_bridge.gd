class_name HHElementBridge
extends RefCounted
## Lane M (H400-H389): the ONE place the NORMAL-tier monster mechanics touch
## the element rules. Everything in HHTierBrain that paints, quenches,
## detonates, siphons or asks "is this a block?" goes through here, so the
## integrator can repoint these few functions at Lane EL's reaction API after
## the merge without reading the director.
##
## What each call does TODAY (dev at 455e2ef, the old charge grid) and what it
## should call AFTER Lane EL lands (spec 2-3):
##
##   paint_own(sim, u, hexes, element, tier)
##     today: writes the monster's own element straight into HHCharge.entries,
##       replacing whatever was there (no reaction: this is an OVERRIDE, spec
##       7.2), source = the monster (H33: it never hurts itself). Axis
##       elements set h / v to +-tier; ice = water tier under a glaze (frozen
##       ground); thunder = an armed fuse; wind = a gale marker. Authored
##       permanent cells (pond water, vents, lava, shade) are left alone.
##     after EL: the same override (EL has no "override" rule), but ice should
##       become EL's Crystal at that tier if EL keeps a crystal entry shape.
##   quench(sim, u, hexes, steps)
##     today: sim.paint(hexes, "water", u.id, steps, fresh = false): fire is
##       doused (erased), other cells gain water; fresh = false is the old
##       grid's containment (no marker fires, glazed cells skipped, no
##       overheat / overfreeze), so nothing chains in the same action.
##     after EL: EL's "quench all charge in a radius as one contained action"
##       hook, which evaporates / douses tier-1 contact and erupts bigger
##       contact as Steam (DECIDE-A, H260), with the 3.3 who-gets-hurt rule.
##   discharge(sim, u, hexes)
##     today: HHCharge.apply(charged hexes, "thunder", u.id): every charged
##       hex fuses (the old Fuse) in one apply, so detonations cannot chain.
##       The old grid credits a fuse to whoever lays the thunder (the
##       monster: it would be spared and hunters hit at full), so the blasts
##       are landed here by hand, `detonate` events tagged contained: the
##       monster takes each hunter-laid blast at that hunter's reaction
##       strength (its own paint spares it, H33); every hunter on a blast
##       (full) or its ring (ring share) takes reaction_unit_other x mult x
##       tier_roar_player_mult, chained like _land_reactions, never below
##       1 HP, no interrupt (DECIDE-C, H262).
##     after EL: EL's "detonate all charge in a radius as one contained
##       action" hook with the monster as the trigger; the 3.3 rule decides
##       who is hurt and how much (drop the hand-made DECIDE-C pass).
##   siphon(sim, u, hexes, element) -> points
##     today: sums `element` intensity on the hexes and clears them.
##     after EL: unchanged unless EL adds entries that carry more than h / v.
##   is_block(sim, hex) / block_hexes(sim, hexes) / hit_block(sim, hex)
##     today: a hunter holding the lance's E Guard (guard > 0) and arena rock,
##       pillar and tree cells. No water wall exists. hit_block on a pillar
##       damages the cell (sim.damage_cells), on a guard does nothing (the
##       telegraph's guard rule already answers it).
##     after EL: add EL's crystal-as-block query (an ice Crystal / W-swap
##       pillar) and break it through EL's shatter when its hits run out.
##   carries(sim, hex, element) / foreign(sim, hex, u)
##     plain HHCharge reads; unchanged after EL.

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


## The Quench Wave's water (spec 7.3): contained.
static func quench(sim: HHSim, u: Dictionary, hexes: Array, steps: int) -> Dictionary:
	return sim.paint(hexes, "water", str(u.id), steps, false)


## The Discharge Roar (spec 7.3): every charged hex in `hexes` detonates as one
## contained action. Returns { detonated: [hex], players: { id: amount }, monster: amount }.
static func discharge(sim: HHSim, u: Dictionary, hexes: Array) -> Dictionary:
	var charged: Array = []
	var owner := {}
	for h in hexes:
		if sim.charge.charged(h):
			charged.append(h)
			owner[h] = str(sim.charge.at(h).get("source", ""))
	charged.sort()
	var out := { "detonated": [], "players": {}, "monster": 0.0 }
	if charged.is_empty():
		return out
	# the old grid credits a fuse to whoever lays the thunder; here that is the
	# monster, so the blasts are landed by hand below (who is hurt: 3.3 / DECIDE-C)
	var r := sim.charge.apply(charged, "thunder", str(u.id), 1, true)
	sim._emit({ "type": "paint", "id": u.id, "element": "thunder", "hexes": charged.duplicate(), "changed": (r.changed as Array).duplicate(), "contained": true })
	var blasts: Array = []
	for d in r.detonations:
		(out.detonated as Array).append(d.hex)
		var src := str(owner.get(d.hex, ""))
		blasts.append([d.hex, float(d.mult), src])
		sim._emit({ "type": "detonate", "hex": d.hex, "mult": float(d.mult), "pct": float(d.mult), "mix": d.mix, "source": src, "by": u.id, "contained": true })
	# the monster: a hunter's setup hurts it at that hunter's reaction strength (the old
	# rule for a hunter's own detonation); its own paint does not (H33)
	var mon: Array = []
	for b in blasts:
		if str(b[2]) == str(u.id):
			continue
		var k := _share(sim.footprint(u), b[0], float(b[1]))
		if k > 0.0:
			mon.append(k * sim.reaction_unit(str(b[2])))
	var mt := _chain(mon) * (1.0 - sim.resist_of(u, "thunder") / 100.0)
	if mt > 0.0:
		sim.hurt(u, mt, "discharge_roar", 0.0, "", false)
		out.monster = mt
	# DECIDE-C (H262) until EL's 3.3: the hunters caught take a share, never below 1 HP
	var unit := HHTune.value("reaction_unit_other") * HHTierBrain.t("roar_player_mult")
	for p in sim.standing_players():
		var list: Array = []
		for b in blasts:
			var k := _share([p.hex], b[0], float(b[1]))
			if k > 0.0:
				list.append(k)
		var amount := minf(_chain(list) * unit * (1.0 - sim.resist_of(p, "thunder") / 100.0), float(p.hp) - 1.0)
		if amount > 0.0:
			sim.hurt(p, amount, "discharge_roar", 0.0, str(u.id), false)
			out.players[p.id] = amount
	return out


## A blast at `hex` on a unit covering `cells`: the full mult on its hex, the ring share next to it.
static func _share(cells: Array, hex: Vector2i, mult: float) -> float:
	var best := 0.0
	for c in cells:
		var d := HHHex.distance(c, hex)
		if d == 0:
			return mult
		if d == 1:
			best = float(HHFormulas.detonation_ring_pct(mult).value)
	return best


## The sim's chain rule (_land_reactions): the strongest in full + reaction_chain_frac of the rest.
static func _chain(list: Array) -> float:
	if list.is_empty():
		return 0.0
	var l := list.duplicate()
	l.sort()
	l.reverse()
	var total := float(l[0])
	for i in range(1, l.size()):
		total += float(l[i]) * HHTune.value("reaction_chain_frac")
	return total


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


## A hex that stops a sweep (spec 8.2): rock / pillar / tree, or a hunter
## holding the lance's Guard. (EL: + crystals / W-swap pillars.)
static func is_block(sim: HHSim, hex: Vector2i) -> bool:
	if sim.arena.exists(hex) and str(sim.arena.kind(hex)) in BLOCK_KINDS:
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
static func break_block(sim: HHSim, hex: Vector2i) -> bool:
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
