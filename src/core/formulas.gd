class_name HHFormulas
## Every combat number, one function each, returning a "calc":
## { value, label, formula, values }, so a tooltip or the tune panel can show
## how a number came to be. The game computes combat numbers nowhere else.
## Pattern from Black | White's BWFormulas.

const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]
const OPPOSITE := {
	"fire": "water", "water": "fire",
	"light": "dark", "dark": "light",
	"thunder": "wind", "wind": "thunder",
}
## Statuses a monster can put on a player (kickoff: burn, poison, paralysis;
## poison is dark's status, H2).
const STATUS_ELEMENT := { "burn": "fire", "poison": "dark", "paralysis": "thunder", "slow": "ice", "freeze": "ice" }
const RESIST_CAP := 75.0


static func calc(label: String, value: float, formula: String, values: String) -> Dictionary:
	return { "value": value, "label": label, "formula": formula, "values": values }


## Damage a tile effect deals: pct of max HP after elemental resistance.
static func tile_damage(max_hp: float, pct: float, resist_pct: float = 0.0, mult: float = 1.0) -> Dictionary:
	var res := minf(resist_pct, RESIST_CAP)
	var v := 0.0
	if pct > 0.0:
		v = maxf(1.0, roundf(max_hp * pct / 100.0 * mult * (1.0 - res / 100.0)))
	return calc("tile damage", v, "max_hp * pct/100 * mult * (1 - res/100)",
		"%.0f * %.1f/100 * %.2f * (1 - %.0f/100)" % [max_hp, pct, mult, res])


## A blow: base * power, cut by the target's resistance to its element.
static func hit(base: float, power: float, resist_pct: float = 0.0) -> Dictionary:
	var res := minf(resist_pct, RESIST_CAP)
	var v := maxf(1.0, roundf(base * power * (1.0 - res / 100.0)))
	return calc("hit", v, "base * power * (1 - res/100)", "%.0f * %.2f * (1 - %.0f/100)" % [base, power, res])


## Stagger from a strike of `strength` 0..1: ticks the victim is held.
static func stagger_ticks(strength: float) -> Dictionary:
	var s := clampf(strength, 0.0, 1.0)
	var v := roundf(HHTune.value("stagger_max_ticks") * s)
	return calc("stagger", v, "stagger_max_ticks * strength", "%.0f * %.2f" % [HHTune.value("stagger_max_ticks"), s])


## Stagger bar (H510): what one hit or reaction adds to a monster's bar:
## stagger x the fill factor of its element / reaction (sb_hit_<element>,
## sb_<reaction>) x frac (sb_monster_trigger_frac for a reaction a monster or
## the arena set off, else 1). `key` is the factor's tune key.
static func stagger_fill(stagger: float, key: String, frac: float = 1.0) -> Dictionary:
	var f := HHTune.value(key) if HHTune.has(key) else 0.0
	var v := maxf(0.0, stagger) * f * frac
	return calc("stagger fill", v, "stagger * %s * frac" % key, "%.2f * %.2f * %.2f" % [stagger, f, frac])


## The fill a monster's bar needs to topple: sb_need x the party (1 +
## sb_party_mult per extra hunter) x the rise (1 + sb_rise per topple so far).
static func stagger_need(hunters: int, topples: int) -> Dictionary:
	var party := 1.0 + HHTune.value("sb_party_mult") * float(maxi(0, hunters - 1))
	var rise := 1.0 + HHTune.value("sb_rise") * float(maxi(0, topples))
	var v := HHTune.value("sb_need") * party * rise
	return calc("stagger need", v, "sb_need * (1 + sb_party_mult * (hunters-1)) * (1 + sb_rise * topples)",
		"%.1f * %.2f * %.2f" % [HHTune.value("sb_need"), party, rise])


## A detonation's split: the centre takes pct, each neighbour a fraction of it.
static func detonation_ring_pct(pct: float) -> Dictionary:
	var v := pct * HHTune.value("detonate_ring_frac")
	return calc("ring blast", v, "pct * detonate_ring_frac", "%.1f * %.2f" % [pct, HHTune.value("detonate_ring_frac")])


## H50 Fuse / Detonate: the multiple of the caster's auto attack a thunder
## blast deals: per point of charge, per extra axis, per water step conducted;
## x1.5 on authored frost (H2's glaze shatter).
static func fuse_mult(points: int, axes: int, water: int, glazed: bool = false) -> Dictionary:
	var v := HHTune.value("det_aa_mult_per_point") * points + HHTune.value("det_aa_mult_per_axis") * maxi(axes - 1, 0) \
		+ HHTune.value("det_aa_mult_per_water") * water
	if glazed:
		v *= HHTune.value("det_frost_mult")
	return calc("fuse", v, "per_point * points + per_axis * (axes - 1) + per_water * water" + (" * det_frost_mult" if glazed else ""),
		"%.1f * %d + %.1f * %d + %.1f * %d" % [HHTune.value("det_aa_mult_per_point"), points, HHTune.value("det_aa_mult_per_axis"), maxi(axes - 1, 0),
		HHTune.value("det_aa_mult_per_water"), water])


## Lane EL (spec 2.3, 2.5): a tier-3 burst's multiple (overheat, geyser,
## glint, flux): "<kind>_aa_mult" (x the auto attack).
static func burst_mult(kind: String) -> Dictionary:
	var key := "%s_aa_mult" % kind
	var v := HHTune.value(key) if HHTune.has(key) else 0.0
	return calc(kind, v, key, "%.2f" % v)


## Lane EL (spec 2.2): Shatter's multiple: per point of stored charge plus per
## ice level.
static func shatter_mult(points: int, ice: int) -> Dictionary:
	var v := HHTune.value("shatter_aa_mult_per_point") * points + HHTune.value("shatter_aa_mult_per_ice") * ice
	return calc("shatter", v, "per_point * points + per_ice * ice",
		"%.2f * %d + %.2f * %d" % [HHTune.value("shatter_aa_mult_per_point"), points, HHTune.value("shatter_aa_mult_per_ice"), ice])


## Lane EL (spec 3.1, 3.2): Steam / Eclipse by the charge consumed (both
## sides of the axis). Steam has its own curve (steam_mult); Eclipse is
## eclipse_aa_mult_per_point x consumed.
static func eruption_mult(kind: String, consumed: int) -> Dictionary:
	if kind == "steam":
		return steam_mult(consumed)
	var per := HHTune.value("%s_aa_mult_per_point" % kind)
	return calc(kind, per * consumed, "%s_aa_mult_per_point * consumed" % kind, "%.2f * %d" % [per, consumed])


## H420 (author): Steam by T = water + fire consumed (2..6), linear from
## steam_aa_mult_min at T = 2 to steam_aa_mult_max at T = 6. Its own keys: it never
## reads thunder's (H423), though today's values match thunder on fire 1 (x2.5)
## and on dark 3 + fire 3 (x18).
static func steam_mult(consumed: int) -> Dictionary:
	var lo := HHTune.value("steam_aa_mult_min")
	var hi := HHTune.value("steam_aa_mult_max")
	var t := clampi(consumed, 2, 6)
	var v := lo + (hi - lo) * float(t - 2) / 4.0
	return calc("steam", v, "min + (max - min) * (T - 2) / 4", "%.2f + (%.2f - %.2f) * (%d - 2) / 4" % [lo, hi, lo, t])


## Lane EL (spec 3.3): one reaction's damage on one unit: the reaction unit
## (an auto attack at the lance's cadence, H50) x the multiple x the 3.3
## fraction (1 for a hunter's own reaction; monster_reaction_frac /
## monster_reaction_player_frac when a monster or the arena triggered it),
## cut by resistance, x a vulnerability (Flux).
static func reaction_damage(unit_dmg: float, mult: float, frac: float, resist_pct: float, vuln: float) -> Dictionary:
	var res := minf(resist_pct, RESIST_CAP)
	var v := maxf(0.0, unit_dmg * mult * frac * (1.0 - res / 100.0) * vuln)
	return calc("reaction", v, "unit * mult * frac * (1 - res/100) * vuln",
		"%.0f * %.2f * %.2f * (1 - %.0f/100) * %.2f" % [unit_dmg, mult, frac, res, vuln])


## Hexes per second from ticks per hex.
static func hexes_per_second(ticks_per_hex: float) -> float:
	return 30.0 / maxf(ticks_per_hex, 1.0)


## H427 (the author: "They should definitely be compared to each other as a
## reference. But I would attach it to basically auto attack damage."): every
## reaction and eruption at its relevant tiers / totals, as a multiple of the
## triggering hunter's auto attack, from the LIVE tune values. Rows
## { reaction, case, mult, anchor } (anchor: "" or what it equals today).
## tools/reaction_table.gd writes design/elements/reaction_table.md from this;
## the F1 panel shows it under the keys.
static func reaction_table() -> Array:
	var rows: Array = []
	rows.append(_row("Detonate", "thunder on fire 1 (1 point)", fuse_mult(1, 1, 0), "anchor: = Steam 1+1"))
	rows.append(_row("Detonate", "thunder on fire 2", fuse_mult(2, 1, 0)))
	rows.append(_row("Detonate", "thunder on fire 3", fuse_mult(3, 1, 0)))
	rows.append(_row("Detonate", "thunder on water 3 (conducts 3)", fuse_mult(3, 1, 3)))
	rows.append(_row("Detonate", "thunder on dark 3 + fire 3", fuse_mult(6, 2, 0), "anchor: = Steam 3+3"))
	rows.append(_row("Detonate", "thunder on the cave's frost (water 1)", fuse_mult(1, 1, 1, true)))
	for t in range(2, 7):
		var note := ""
		if t == 2:
			note = "anchor: = Detonate on fire 1"
		elif t == 6:
			note = "anchor: = Detonate on dark 3 + fire 3"
		rows.append(_row("Steam", "water + fire consumed T = %d" % t, steam_mult(t), note))
	for t in range(3, 7):
		rows.append(_row("Eclipse", "light + dark consumed = %d (+ exposed %.1f s)" % [t, HHTune.value("eclipse_exposed_ticks") / 30.0], eruption_mult("eclipse", t)))
	var own := { "overheat": "fire", "geyser": "water", "glint": "light", "flux": "dark" }
	for k in own:
		rows.append(_row(str(k).capitalize(), "fresh %s on its own tier 3" % own[k], burst_mult(k)))
	rows.append(_row("Shatter", "fire 1 crystal, ice 1", shatter_mult(1, 1)))
	rows.append(_row("Shatter", "fire 3 crystal, ice 1", shatter_mult(3, 1)))
	rows.append(_row("Shatter", "fire 3 + light 3 crystal, ice 3", shatter_mult(6, 3)))
	rows.append({ "reaction": "Swirl", "case": "x swirl_reaction_mult on the reaction it condenses into", "mult": HHTune.value("swirl_reaction_mult"), "anchor": "" })
	return rows


static func _row(reaction: String, case_text: String, c: Dictionary, anchor: String = "") -> Dictionary:
	return { "reaction": reaction, "case": case_text, "mult": float(c.value), "anchor": anchor }
