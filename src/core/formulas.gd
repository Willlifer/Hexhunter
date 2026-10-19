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


## A detonation's split: the centre takes pct, each neighbour a fraction of it.
static func detonation_ring_pct(pct: float) -> Dictionary:
	var v := pct * HHTune.value("detonate_ring_frac")
	return calc("ring blast", v, "pct * detonate_ring_frac", "%.1f * %.2f" % [pct, HHTune.value("detonate_ring_frac")])


## Hexes per second from ticks per hex.
static func hexes_per_second(ticks_per_hex: float) -> float:
	return 30.0 / maxf(ticks_per_hex, 1.0)
