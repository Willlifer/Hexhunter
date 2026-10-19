class_name HHTune
## The feel numbers, in one place (the MmoTune / FpsTune pattern from Gamers
## Gauntlet). Every value here is read at run time by the sim, the charge grid
## and the view, so the F1 panel (Lane P) can change them live. Tests read the
## defaults. Nothing else in the project hard-codes a feel number.
##
## Ticks are 30 Hz (HHSim.TICK). "pct" means percent of max HP.

const DEFAULTS := {
	# movement
	"walk_ticks": 10.0,          # ticks per hex when walking (3 hexes/s; author 2026-10-19: faster, H22)
	"run_ticks": 7.0,            # ticks per hex when running
	"max_step_m": 1.0,           # a neighbour more than this much higher or lower is a cliff
	# charge grid (Black | White's cycles mapped onto ticks)
	"charge_step_ticks": 270.0,  # one step of axis decay every 9 s (author 2026-10-19: 3x longer, H24)
	"charge_mark_ticks": 450.0,  # an unfired marker lasts 15 s
	"charge_glaze_ticks": 360.0, # a glaze holds 12 s, decay paused under it
	"charge_gale_ticks": 135.0,  # a gale's copies last 4.5 s
	# ground effects (per second while standing)
	"fire_stand_pct": 3.0,       # per fire tier
	"fire_cross_pct": 1.5,       # per fire tier, once per hex entered
	"light_heal_pct": 2.0,       # per light tier
	"dark_drain_pct": 2.0,       # dark 3 only
	"water_slow": [1.0, 1.0, 0.85, 0.7],   # speed multiplier by water tier
	# detonations and bursts
	"detonate_ring_frac": 0.5,   # neighbours take this fraction of the centre blast
	# statuses
	"burn_pct_per_s": 2.0,
	"poison_pct_per_s": 1.5,
	"stagger_max_ticks": 45.0,   # a full-strength hit holds you 1.5 s
	# hp
	"player_hp": 1000.0,
	"ground_tick_every": 30.0,   # standing effects apply once a second
}

static var _v := {}


static func value(key: String) -> float:
	if _v.has(key):
		return float(_v[key])
	return float(DEFAULTS[key])


static func list(key: String) -> Array:
	if _v.has(key):
		return _v[key]
	return DEFAULTS[key]


static func set_value(key: String, v: Variant) -> void:
	_v[key] = v


static func reset() -> void:
	_v = {}


static func keys() -> Array:
	return DEFAULTS.keys()
