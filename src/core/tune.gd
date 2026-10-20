class_name HHTune
## The feel numbers, in one place (the MmoTune / FpsTune pattern from Gamers
## Gauntlet). Every value here is read at run time by the sim, the charge grid
## and the view, so the F1 panel (Lane P) can change them live. Tests read the
## defaults. Nothing else in the project hard-codes a feel number.
##
## Ticks are 30 Hz (HHSim.TICK). "pct" means percent of max HP.

const DEFAULTS := {
	# movement
	"walk_mps": 5.5,             # players move freely (H31): metres per second walking
	"run_mps": 8.0,              # ... and running
	"walk_ticks": 10.0,          # legacy hex pace (tests, tools); players no longer use it
	"run_ticks": 7.0,
	"max_step_m": 1.0,           # a neighbour more than this much higher or lower is a cliff
	# charge grid (Black | White's cycles mapped onto ticks)
	"charge_step_ticks": 810.0,  # one step of axis decay every 27 s (author: 3x longer again, H35)
	"charge_mark_ticks": 1350.0, # an unfired marker lasts 45 s
	"charge_glaze_ticks": 1080.0,# a glaze holds 36 s, decay paused under it
	"charge_gale_ticks": 405.0,  # a gale's copies last 13.5 s
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
	"detonate_stagger": 0.35,    # a blast under you staggers this much (0..1)
	"overfreeze_slow_ticks": 90.0,
	# monsters
	"monster_hp": 20000.0,
	"monster_walk_ticks": 14.0,  # ticks per hex for a monster on the move (slow, weighty; H13)
	"monster_stagger_mult": 0.5, # monsters are held half as long as players
	# guard / leap
	"guard_reduce": 0.7,         # Guard cuts a blocked hit by this fraction
	"leap_height_m": 3.0,        # a vault's arc apex
	# lance (H5): numbers for the first weapon
	"lance_reach": 2.0,
	"lance_basic_dmg": 90.0,
	"lance_basic_ticks": 36.0,   # 1.2 s between basics (H34: heavier)
	"lance_basic_windup": 12.0,  # 0.4 s of wind-up before a basic lands
	"basic_stagger": 0.12,       # a landed basic rocks the monster
	"lance_q_cd": 90.0,          # Pierce 3 s
	"lance_q_len": 4.0,
	"lance_q_dmg": 160.0,
	"lance_q_windup": 10.0,      # Pierce plants, then stabs
	"lance_q_stagger": 0.3,
	"exchange_cd": 30.0,         # W 1 s
	"lance_e_cd": 240.0,         # Guard 8 s
	"lance_e_ticks": 60.0,       # Guard lasts 2 s
	"lance_counter_mult": 2.0,
	"lance_r_cd": 450.0,         # Eruption 15 s
	"lance_r_range": 6.0,
	"lance_r_air_ticks": 26.0,
	"lance_r_radius": 2.0,
	"lance_r_dmg": 260.0,
	"lance_r_steps": 2.0,
	"lance_r_stagger": 0.6,
	# biome cells (H43-H44)
	"authored_reform_every": 150.0,  # vents / lava / shade re-form every 5 s
	"pillar_hp": 300.0,
	"pillar_paint_dmg": 60.0,        # a cast or blow that lands on a pillar hex chips this much per element step
	# potions (H40): T drinks one; a slow heal the ground can fight
	"potion_count": 5.0,
	"potion_windup": 15.0,       # 0.5 s to drink (a commitment)
	"potion_heal_pct": 40.0,     # healed over potion_seconds
	"potion_seconds": 6.0,
	"potion_cd": 240.0,          # 8 s between potions
	"dark_heal_cut": 0.3,        # each dark tier under you cuts healing by this (dark 3 = 10%)
	"light_heal_bonus": 0.25,    # each light tier under you adds this
	# hp
	"player_hp": 3000.0,         # H36: 3x
	"ground_tick_every": 30.0,   # standing effects apply once a second
}

static var _v := {}
static var _ext := {}        # registered tables: "<prefix>_<key>" -> default (weapons, monsters)


## A weapon or monster registers its TUNE dictionary under a prefix so the
## F1 panel can edit it live and value("<prefix>_<key>") reads it.
static func register(prefix: String, table: Dictionary) -> void:
	for k in table:
		var v: Variant = table[k]
		if v is float or v is int:
			_ext["%s_%s" % [prefix, k]] = float(v)


static func value(key: String) -> float:
	if _v.has(key):
		return float(_v[key])
	if _ext.has(key):
		return float(_ext[key])
	return float(DEFAULTS[key])


static func has(key: String) -> bool:
	return DEFAULTS.has(key) or _ext.has(key)


static func list(key: String) -> Array:
	if _v.has(key):
		return _v[key]
	return DEFAULTS[key]


static func set_value(key: String, v: Variant) -> void:
	_v[key] = v


static func reset() -> void:
	_v = {}


static func keys() -> Array:
	var out: Array = DEFAULTS.keys()
	var ek := _ext.keys()
	ek.sort()
	out.append_array(ek)
	return out


static func default_of(key: String) -> Variant:
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return _ext.get(key, 0.0)
