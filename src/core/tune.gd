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
	"run_mps": 6.0,              # ... and running (H56, H950: 8.0 -> 6.0, "slow run speed by 25%")
	"walk_ticks": 10.0,          # legacy hex pace (tests, tools); players no longer use it
	"run_ticks": 7.0,
	"max_step_m": 1.0,           # a neighbour more than this much higher or lower is a cliff
	# dash (H56, Lane W H950-): Shift dashes toward the cursor; charges recharge one at a time
	"dash_m": 3.5,               # metres covered by one dash (two hexes)
	"dash_ticks": 6.0,           # ... over this many ticks (0.2 s: 17.5 m/s)
	"dash_charges": 2.0,         # dashes banked
	"dash_recharge_s": 3.5,      # one charge comes back every this many seconds (one at a time)
	"dash_recover_ticks": 9.0,   # after a dash lands: this long before the next dash (no instant chain)
	"dash_iframe_ticks": 5.0,    # from the dash's start: hits in this window are dodged (0.17 s)
	# commit feel (H57, H58, Lane W)
	"recovery_ticks": 9.0,
	"basic_recovery_melee_ticks": 5.0, # H59: lance / daggers string hit 1 (0.15 s asked; 5 ticks = 0.17 s at 30 Hz)
	"basic_recovery_bow_ticks": 6.0,   # H59: every bow basic, 0.2 s       # 0.3 s rooted after every hunter action (basics, Q/E/R, W, the potion throw); combo hits carry their own
	"recovery_turn_dps": 180.0,  # turning speed during a recovery (none during a wind-up: aim is fixed at its start)
	"exchange_windup": 5.0,      # W gets a very short wind-up so you can see it go off
	"combo_window_ticks": 20.0,  # lance / daggers: the next basic continues the string if it starts within this long after the last hit's recovery
	"input_buffer_ticks": 9.0,   # a cast / swap / potion pressed during a wind-up or recovery fires when it ends, if within this long
	"flinch_ticks": 8.0,         # a landed monster attack interrupts the hunter and holds it this long (stagger wins when longer)
	"exposed_dmg_mult": 1.25,    # a monster recovering from a big attack takes this much more damage from hunters (its own recovery, no added idle)
	"exposed_min_hexes": 10.0,   # "big": a damaging monster telegraph at least this many hexes ...
	"exposed_min_stagger": 0.4,  # ... or with at least this stagger
	# charged Q (H56, Lane W): hold Q to charge, release to fire; "strength" = element steps
	"charge_l2_s": 1.5,          # held this long: level 2
	"charge_l3_s": 3.0,          # held this long: level 3, which fires on its own
	"charge_move_mult": 0.5,     # bow and daggers move at this fraction of their speed while charging
	"lance_charge_guard": 0.4,   # H59: and a charging lance is never interrupted or staggered (super armour)   # the lance braces while charging: damage taken is cut by this fraction (it cannot move)
	# charge grid (Black | White's cycles mapped onto ticks)
	"charge_step_ticks": 810.0,  # one step of axis decay every 27 s (author: 3x longer again, H35)
	"charge_mark_ticks": 1350.0, # an unfired marker lasts 45 s
	"charge_glaze_ticks": 1080.0,# a glaze holds 36 s, decay paused under it
	"charge_gale_ticks": 405.0,  # a gale's copies last 13.5 s
	# ground effects (per second while standing)
	"fire_stand_pct": 1.2,       # per fire tier (gate L-10: 3.0 "way too strong")
	"fire_cross_pct": 0.6,       # per fire tier, once per hex entered
	"light_heal_pct": 2.0,       # per light tier
	"dark_drain_pct": 2.0,       # dark 3 only
	"water_slow": [1.0, 1.0, 0.85, 0.7],   # speed multiplier by water tier
	# detonations and bursts
	"detonate_ring_frac": 0.5,   # neighbours take this fraction of the centre blast
	# reactions (H50, author: "an auto attack does 1x, electric setting off a t1 dark 3x, t3 dark + t3 fire ~21x"):
	# damage = the caster's auto attack (at lance cadence) x a multiplier; never pct of max HP.
	"det_mult_per_point": 3.0,   # fuse: x per charge point on the hex (t1 = 1 point, t3 = 3)
	"det_mult_per_axis": 3.0,    # fuse: x per extra element axis mixed on the hex (fire/water + light/dark)
	"det_mult_per_water": 1.0,   # fuse: x per water step conducted
	"overheat_mult": 3.0,        # fresh fire on fire 3: the eruption ring (a fire basic re-triggers it every 2nd swing: fire 3 vents to 2)
	"overfreeze_mult": 9.0,      # fresh ice on glazed water: the burst
	"reaction_chain_frac": 0.15, # one cast's blasts on one unit: the strongest in full + this x each other one
	"reaction_unit_other": 40.0, # the "auto attack" for reactions a monster or the arena sets off (a hunter has 3000 HP)
	# the arena's own events (H51): one per biome, telegraphed, hits everyone, lays its element
	"env_on": 1.0,               # 0 switches them off
	"env_warn_s": 1.8,           # telegraph before each event lands
	"env_pond_every": 15.0,      # seconds between swells ("pulse water every 15 s or so, because it's water")
	"env_pond_radius": 4.0,      # the swell's disk (61 hexes)
	"env_pond_dmg_pct": 1.0,
	"env_caldera_every": 12.0,   # vents erupt
	"env_caldera_vents": 3.0,
	"env_caldera_dmg_pct": 4.0,
	"env_cave_every": 14.0,      # rockfalls
	"env_cave_rocks": 4.0,
	"env_cave_dmg_pct": 4.0,
	"env_glade_every": 12.0,     # alternates a healing sunbreak and a gust of wind # a monster: a big body covers ~19 hexes, so one fuse used to land a dozen blasts
	# statuses
	"burn_pct_per_s": 1.0,
	"monster_ground_mult": 0.33, # H54: monsters take ground fire / drain / burn / poison against a third of their unscaled HP
	"poison_pct_per_s": 1.5,
	"stagger_max_ticks": 45.0,   # a full-strength hit holds you 1.5 s
	"slow_mult": 0.6,            # the `slow` status (overfreeze, pollen, spores) cuts speed to this
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
	"lance_basic_dmg": 220.0,    # H50: was 90 ("basic attacks deal more")
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
	# potions (H40, H56): T throws one at the cursor; a heal zone the ground can fight
	"potion_count": 5.0,
	"potion_windup": 12.0,       # 0.4 s throw wind-up (a commitment; was a 0.5 s drink)
	"potion_range": 8.0,         # hexes: the throw clamps along the line to the cursor
	"potion_radius": 3.0,        # the heal zone: 37 hexes; every hunter standing in it heals
	"potion_heal_pct": 40.0,     # healed over potion_seconds by a hunter standing in the zone the whole time
	"potion_seconds": 6.0,
	"potion_cd": 240.0,          # 8 s between potions
	"dark_heal_cut": 0.3,        # each dark tier under you cuts healing by this (dark 3 = 10%)
	"light_heal_bonus": 0.25,    # each light tier under you adds this
	# hp
	"player_hp": 3000.0,         # H36: 3x
	"ground_tick_every": 30.0,   # standing effects apply once a second
	# co-op (H53, Lane S H875-): a party of 1-4 hunters
	"party_hp_mult": 0.6,        # monster HP x (1 + this per extra hunter): x1.6 for two, x2.8 for four
	"party_spawn_min": 2.0,      # hunters 2..4 spawn at least this many hexes from every other hunter ...
	"party_spawn_max": 3.0,      # ... and at most this far from the nearest one (the party stands 2-3 apart)
	"party_friendly_fire": 0.0,  # 1 = hunters' blows, telegraphs, reactions and ground hurt each other (H33 extended to the party when 0)
	"revive_ticks": 90.0,        # an ally standing within 1 hex this long (no damage taken) revives a downed hunter (3 s)
	"revive_hp_pct": 30.0,       # ... back at this pct of max HP
	"revive_decay": 0.5,         # revive progress lost per tick while nobody stands by the downed hunter
	"revive_event_every": 10.0,  # a revive_progress event every this many ticks of progress
	"aggro_hit_bonus_hexes": 3.0,# the hunter who last hit a monster counts as this many hexes closer when it picks a target ...
	"aggro_commit_ticks": 60.0, # H54: a monster holds its target 2 s before it may switch
	"revive_hit_setback": 30.0, # H54: a hit on a reviver costs 1 s of progress (was a full reset)
	"aggro_memory_ticks": 150.0, # ... for this long after the hit (5 s)
	# monster hull (H250-H259, Lane H): occupancy, the Attack Ring, push-out
	"attack_spot_claimed_steps": 3.0, # an attack spot another hunter holds or heads for costs this many extra steps (the party spreads round the ring)
	"push_out_max_rings": 6.0,   # push-out searches the Attack Ring, then this many rings further out, before it gives up (never in practice)
	# push-out hurts, leaps splash (H268-H270, Lane P H271-H279)
	"push_land_pct": 20.0,       # the monster arrived on you (a leap landing; a charge or walk that ended on you): pct of max HP. Replaces the leaps' own landing damage
	"push_self_pct": 5.0,        # you caused it: you were moving into the hull when it first covered you, and it stopped on you
	"push_land_stagger": 0.8,    # stagger strength of a "landed on" push (the leaps it replaces staggered 0.8)
	"push_self_stagger": 0.0,    # ... and of a self-caused one
	"push_hit_grace_ticks": 10.0, # that monster's telegraph hit you within this many ticks: no push-out damage on top (a charge's last segment can land a tick before the body stops)
	"leap_splash_steps": 1.0,    # a monster leap paints its element at this tier on the open Attack Ring hexes round the landing (contained: no reaction)
	"range_ring_alpha": 0.12,    # the hunter's reach ring (H56): opacity of the thin outline (was 0.62, daggers 0.45; H270 "much more transparent"); daggers x0.75
	# look (H84-H85, Lane Y): the comic ink outline on the hunters and the monsters (HHInk)
	"ink_on": 1.0,               # 1 = outline on (author, 2026-10-20: wanted, default on), 0 = off
	"ink_px": 2.4,               # line width in pixels on a 1080-line screen (constant on screen: no fat lines up close)
	"ink_max_m": 0.05,           # ... capped at this many metres (bites only on small or far views)
	# web look (Lane Z, H90-H92): the Compatibility renderer only; desktop ignores these
	"web_ambient": 1.0,          # the sky ambient the *_web GK shaders add (x the sky's irradiance estimate)
	"web_reflection": 0.5,       # the sky a glossy GK surface mirrors (water)
	"web_fog": 1.0,              # x the arena's fog density, drawn by the *_web GK shaders
	"web_glow_whiten": 0.45,     # additive light pools (torches, lava) pulled toward warm white, as Filmic does on desktop
	"web_glow_gain": 1.1,        # ... and scaled
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
