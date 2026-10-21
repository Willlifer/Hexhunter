class_name HHSpirewalker
extends RefCounted
## Spirewalker's brain (kickoff "Spire", H11; the glade monster, H10):
## node-free, seeded from sim.rng, one `tick()` per sim tick (the integrator
## keeps `sim.brains[id] = brain`; HHSim.step calls it after orders). The
## HHSwampfang pattern: TUNE, phases(), rear_mult(), tick(sim, u), every
## attack a telegraph (H29) started on the same tick as its clip with a
## window of contact_tick x windup_mult (H38) and the clip slowed to match.
##
## Calm: sits motionless with the reeds raised, soaking static from the sky.
## A charge meter `u.charge` (0..1) rises every tick, three times as fast on
## "sun" cells; past TUNE.pollen_threshold it is "charged" (violet arcs: the
## tell) and may shake pollen, which spends the charge.
## Aggravated (a player within TUNE.aggro_hexes of its edge, or damage):
## jumps to squash (a radius-2 area at the player's hex, telegraphed ~2 s;
## the unit flies there with sim.begin_leap so it lands as the shape
## resolves), forearm punches (cone), bites, throws barbs (three single-hex
## thunder projectiles: fuse markers where they land), lashes with the reeds
## (a 6-hex thunder line), drags the tail (half ring behind), breathes
## thunder (paralysis) or dark (poison), spreads spores (wind: gale markers
## copy the dark). Signature: pollen shake, a radius-3 cloud: slow + dark 1 +
## poison; whoever is still in it at the next pulse (within 3 s) is paralysed.
## Weak point: the reeds. A hit from the rear arc while charge > 0.5 cuts
## them: no pollen for 20 s, charge stops, every hit takes x1.5 (rear_mult).
## Enraged below 0.25: shorter gaps, more squashes.
##
## Contracts (guide/02): sim.telegraph(owner, hexes, ticks, payload) with
## payload { dmg_pct, element, paint_steps, status, status_ticks, stagger,
## clip, name, flagged }; sim.monster_move(u, goal); sim.begin_leap(u, to,
## ticks, on_land); sim.units_in(hexes, skip). The brain writes u.charge,
## u.reeds_burnt, u.allowed_kinds, u.walk_ticks, u.untargetable (none in
## state_hash, H316). Events: monster_anim { id, clip, speed },
## monster_state { id, state } for aggravated / enraged / charged / pollen /
## reeds_burnt / reeds_regrown.

## Every feel number in one place (ticks are 30 Hz; pct = percent of max HP).
const TUNE := {
	"aggro_hexes": 7,                 # calm -> aggravated when a player is this close (edge to edge)
	"attack_gap_ticks": 36,           # 1.2 s from the end of one attack clip to the next telegraph
	"windup_mult": 1.8,               # H38: telegraph window = contact tick x this; the clip slows to match
	"telegraph_min_ticks": 40,        # telegraph windows 1.3-3.0 s
	"telegraph_max_ticks": 90,
	"reposition_chance": 0.7,         # H39: between attacks, move to a new spot around the player this often
	"reposition_min": 2,              # ... this many hexes beyond the footprint ...
	"reposition_max": 4,              # ... up to this many
	"walk_ticks": 12.0,               # ticks per hex (u.walk_ticks): planted, heavy
	"turn_deg_per_tick": 3.0,         # how fast it turns to face a player while standing
	"charge_per_tick": 0.00167,       # static soaked per tick: full in ~20 s
	"charge_sun_mult": 3.0,           # on a "sun" cell it charges this much faster
	"pollen_threshold": 0.6,          # charged (arcs) above this; pollen allowed, spends it all
	"reed_hit_charge": 0.5,           # a rear hit while charge > this cuts the reeds
	"reeds_burnt_ticks": 600,         # 20 s without pollen, charge frozen at 0
	"burnt_mult": 1.5,                # damage multiplier from anywhere while the reeds are cut
	"rear_arc_deg": 120.0,            # the reed arc, centred on the tail
	"rear_mult": 1.5,                 # damage multiplier from inside that arc
	"close_range": 1,                 # hexes beyond the footprint: in its jaws
	"punch_range": 3,                 # forearm reach beyond the footprint
	"punch_cone_deg": 40.0,           # half-angle of the punch cone
	"punch_dmg_pct": 14.0,
	"punch_stagger": 0.5,
	"bite_range": 2,                  # bite cone length beyond the footprint
	"bite_cone_deg": 32.0,
	"bite_dmg_pct": 18.0,
	"bite_stagger": 0.4,
	"squash_min": 2,                  # edge distance band for a leaping squash ...
	"squash_max": 7,
	"squash_radius": 2,               # the area at the player (its own footprint radius: it lands there)
	"squash_air_ticks": 12,           # the flight itself (the rest of the window is the crouch tell)
	# H268/H276: the squash's own damage (28%) is gone: the telegraph marks the landing hull, the
	# hunters under it take the push-out's push_land_pct (HHTune), and the ring gets the splash
	"squash_splash": "thunder",       # H269: the static it soaks: fuses armed on its Attack Ring as it lands
	"squash_chance": 0.35,            # at mid range, squash vs a ranged move (enrage raises it)
	"barb_range": 8,                  # barbs reach this far from the centre
	"barb_count": 3,                  # single-hex projectiles along the line through the player
	"barb_dmg_pct": 8.0,
	"barb_paint_steps": 1,            # thunder: a fuse marker where each lands
	"lash_len": 6,                    # reed lash line beyond the footprint
	"lash_dmg_pct": 12.0,
	"lash_stagger": 0.3,
	"lash_paint_steps": 1,            # thunder
	"tail_reach": 3,                  # a player behind, this close, draws the tail drag
	"tail_ring": 2,                   # the half ring reaches this far beyond the footprint
	"tail_arc_deg": 90.0,             # half-angle of the half ring (centred on the tail): a semicircle
	"tail_dmg_pct": 15.0,
	"tail_stagger": 0.6,
	"pollen_radius": 3,               # the cloud, beyond the footprint
	"pollen_range": 5,                # only shaken with a player this close (edge distance)
	"pollen_chance": 0.6,             # when charged and in range, pollen vs anything else
	"pollen_pulses": 3,               # the cloud pulses this many times ...
	"pollen_pulse_ticks": 45,         # ... this far apart (1.5 s): it lingers 3 s past the first hit
	"pollen_dmg_pct": 4.0,            # per pulse
	"pollen_paint_steps": 1,          # dark 1 on the ground
	"pollen_slow_ticks": 90,          # slow on every pulse
	"pollen_poison_ticks": 120,       # dark's status, on every pulse
	"pollen_linger_ticks": 90,        # in the cloud again within this of the last pulse = paralysis
	"pollen_paralysis_ticks": 60,
	"breath_range": 6,                # cone length from the centre
	"breath_cone_deg": 30.0,
	"thunder_dmg_pct": 10.0,
	"thunder_paint_steps": 1,
	"thunder_paralysis_ticks": 36,
	"dark_dmg_pct": 10.0,
	"dark_paint_steps": 2,
	"dark_poison_ticks": 150,
	"spore_radius": 3,                # wind ring beyond the footprint
	"spore_dmg_pct": 5.0,
	"spore_paint_steps": 1,           # gale markers copy the dark around them
	"spore_slow_ticks": 60,
	"ranged_max": 8,                  # past this it walks in
}

const ALLOWED_KINDS := ["floor", "sun", "shade", "vent", "water"]   # never lava; rock / pillar / tree impassable
const RANGED := ["barb_throw", "thunder_breath", "dark_breath", "spore_spread", "reed_lash"]

var id := ""
var state := "calm"                   ## calm | aggravated | enraged
var mode := "idle"                    ## idle | approach | attack | squash | dead
var charged := false                  ## u.charge above the threshold (arcs showing)
var phase_state := {}
var busy_until := 0                   ## no decisions before this tick (a clip is playing)
var next_attack_at := 0               ## no telegraph before this tick
var burnt_until := -1                 ## reeds cut until this tick (-1 = intact)
var last_hp := -1.0
var goal := Vector2i(-9999, -9999)
var goals: Array = []                 ## every goal hex chosen (tests)
var attacks: Array = []               ## every telegraph issued: [{ tick, clip, ticks, hexes, at, facing }] (tests)
var anim := ""                        ## the clip last asked for
var repositioned := false
var rolls := 0                        ## rng draws (tests)
var squash := {}                      ## { to, leap_at, land_at, flying }
var squashes_landed := 0              ## (tests)
var pollen := {}                      ## { hexes, checks: [tick ...], issued, seen: { pid: tick } }
var pollens := 0                      ## pollen shakes issued (tests)
var paralysed: Array = []             ## [{ tick, id }] lingering strikes issued (tests)
var force_attack := ""                ## tests: the next attack chosen, if in range


func _init(monster_id: String = "spirewalker") -> void:
	id = monster_id
	phase_state = HHPhases.start(phases())


## The phase script (HHPhases): calm -> aggravated on first damage (the brain
## also forces it on proximity); enraged below 0.25. "charged" is not an HP
## phase: it is the charge meter crossing TUNE.pollen_threshold.
static func phases() -> Dictionary:
	return {
		"rules": { "gap_mult": 1.0, "squash_chance": TUNE.squash_chance, "pollen_chance": TUNE.pollen_chance },
		"phases": [
			{ "id": "aggravated", "trigger": { "hp_below": 1.0 }, "rules": {} },
			{ "id": "enraged", "trigger": { "hp_below": 0.25, "after": "aggravated" }, "rules": { "gap_mult": 0.75, "squash_chance": 0.55, "pollen_chance": 0.8 } },
		],
	}


## Where it may stand (the fight passes this to add_monster).
func allowed_kinds() -> Array:
	return ALLOWED_KINDS.duplicate()


## Damage multiplier for a hit on `u` from `from_hex`: TUNE.burnt_mult from
## anywhere while the reeds are cut (u.reeds_burnt), else TUNE.rear_mult
## inside the rear arc (the reed bed, centred on the tail), else 1.0. Pure.
static func rear_mult(u: Dictionary, from_hex: Vector2i) -> float:
	if bool(u.get("reeds_burnt", false)):
		return float(TUNE.burnt_mult)
	return float(TUNE.rear_mult) if is_behind(u, from_hex) else 1.0


## True when `hex` lies inside the rear arc of `u` (facing = atan2(dx, dz)).
static func is_behind(u: Dictionary, hex: Vector2i) -> bool:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var b: Vector2 = HHHex.to_world(hex, 1.0)
	var v := b - a
	if v.length_squared() < 1e-6:
		return false
	var f := float(u.get("facing", 0.0))
	var fwd := Vector2(sin(f), cos(f))
	var ang := rad_to_deg(acos(clampf(fwd.dot(v.normalized()), -1.0, 1.0)))
	return ang > 180.0 - float(TUNE.rear_arc_deg) * 0.5


func reeds_burnt(sim: HHSim) -> bool:
	return burnt_until >= 0 and sim.tick < burnt_until


# ------------------------------------------------------------------ the tick

func tick(sim: HHSim, u: Dictionary) -> void:
	if not sim.alive(u):
		if mode != "dead":
			mode = "dead"
			squash = {}
			pollen = {}
			_anim(sim, u, "death")
		return
	_ensure(u)
	_reeds(sim, u)
	_charge(sim, u)
	var hp_frac := float(u.hp) / maxf(float(u.max_hp), 1.0)
	for pid in HHPhases.check(phase_state, hp_frac, sim.tick):
		_on_phase(sim, u, str(pid))
	var p := _nearest_player(sim, u)
	if state == "calm":
		if not p.is_empty() and _edge_dist(u, p) <= int(TUNE.aggro_hexes):
			_force_phase(sim, u, "aggravated")
		else:
			_anim(sim, u, _idle_clip(sim))
			return
	_pollen_pulse(sim, u)
	_squash_flight(sim, u)
	if sim.tick < busy_until:
		return
	if mode == "attack" or mode == "squash":
		mode = "idle"
	if p.is_empty():
		_stop(u)
		_anim(sim, u, _idle_clip(sim))
		return
	var d := _edge_dist(u, p)
	if (u.path as Array).is_empty():
		_turn_toward(u, p.hex)
	if sim.tick < next_attack_at:
		if d > int(TUNE.punch_range) and d > int(TUNE.squash_max):
			_approach(sim, u, p)
		elif not repositioned:
			repositioned = true
			if _rng(sim) < float(TUNE.reposition_chance):
				_reposition(sim, u, p)
			else:
				_stop(u)
				_anim(sim, u, _idle_clip(sim))
		elif (u.path as Array).is_empty():
			_anim(sim, u, _idle_clip(sim))
		return
	_choose(sim, u, p, d)


## Pick and start an attack for edge distance `d`.
func _choose(sim: HHSim, u: Dictionary, p: Dictionary, d: int) -> void:
	if force_attack != "":
		var f := force_attack
		force_attack = ""
		if _start(sim, u, p, f):
			return
	if is_behind(u, p.hex) and d <= int(TUNE.tail_reach):
		_tail_drag(sim, u)
		return
	var pollen_chance := float(HHPhases.rule(phase_state, "pollen_chance", TUNE.pollen_chance))
	if charged and not reeds_burnt(sim) and d <= int(TUNE.pollen_range) and _rng(sim) < pollen_chance:
		_pollen(sim, u)
		return
	var squash_chance := float(HHPhases.rule(phase_state, "squash_chance", TUNE.squash_chance))
	if d <= int(TUNE.close_range):
		if _rng(sim) < 0.5:
			_bite(sim, u, p)
		else:
			_punch(sim, u, p)
	elif d <= int(TUNE.punch_range):
		var r := _rng(sim)
		if r < 0.4:
			_punch(sim, u, p)
		elif r < 0.7 and d >= int(TUNE.squash_min):
			_squash(sim, u, p)
		else:
			_reed_lash(sim, u, p)
	elif d <= int(TUNE.squash_max) and _rng(sim) < squash_chance:
		_squash(sim, u, p)
	elif HHHex.distance(u.hex, p.hex) <= int(TUNE.ranged_max):
		var pool: Array = RANGED.duplicate()
		if d > int(TUNE.lash_len):
			pool.erase("reed_lash")
		var pick: String = pool[int(floor(_rng(sim) * pool.size())) % pool.size()]
		_start(sim, u, p, pick)
	else:
		_approach(sim, u, p)


## Start `clip` as an attack if its range allows; false if not started.
func _start(sim: HHSim, u: Dictionary, p: Dictionary, clip: String) -> bool:
	match clip:
		"leaping_squash": _squash(sim, u, p)
		"forearm_punch": _punch(sim, u, p)
		"bite": _bite(sim, u, p)
		"barb_throw": _barb_throw(sim, u, p)
		"reed_lash": _reed_lash(sim, u, p)
		"tail_drag": _tail_drag(sim, u)
		"pollen_shake": _pollen(sim, u)
		"thunder_breath": _thunder_breath(sim, u, p)
		"dark_breath": _dark_breath(sim, u, p)
		"spore_spread": _spore_spread(sim, u)
		_: return false
	return true


# ------------------------------------------------------------------ phases

func _on_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	match pid:
		"aggravated":
			if state == "calm":
				state = "aggravated"
				_emit_state(sim, u, state)
				_anim(sim, u, _idle_clip(sim))
		"enraged":
			state = "enraged"
			_emit_state(sim, u, state)


func _force_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	if HHPhases.fired(phase_state, pid):
		return
	for p in phase_state.script.get("phases", []):
		if str(p.id) == pid:
			phase_state.fired.append(pid)
			phase_state.rules.merge(Dictionary(p.get("rules", {})), true)
	_on_phase(sim, u, pid)


func _emit_state(sim: HHSim, u: Dictionary, what: String) -> void:
	sim._emit({ "type": "monster_state", "id": u.id, "state": what })


# ------------------------------------------------------------------ charge and reeds

## Static soaks in every tick (x3 on a sun cell) unless the reeds are cut.
func _charge(sim: HHSim, u: Dictionary) -> void:
	if reeds_burnt(sim):
		u.charge = 0.0
		if charged:
			charged = false
		return
	var rate := float(TUNE.charge_per_tick)
	if str(sim.arena.kind(u.hex)) == "sun":
		rate *= float(TUNE.charge_sun_mult)
	u.charge = minf(1.0, float(u.charge) + rate)
	var now := float(u.charge) > float(TUNE.pollen_threshold)
	if now and not charged:
		_emit_state(sim, u, "charged")
	charged = now


## The weak point: damage taken this tick with a player in the rear arc
## (within tail_reach of the body) while charge > reed_hit_charge cuts the
## reeds; they regrow after reeds_burnt_ticks.
func _reeds(sim: HHSim, u: Dictionary) -> void:
	var hp := float(u.hp)
	if last_hp >= 0.0 and hp < last_hp and not reeds_burnt(sim) and float(u.charge) > float(TUNE.reed_hit_charge):
		for p in sim.players():
			if sim.alive(p) and is_behind(u, p.hex) and _edge_dist(u, p) <= int(TUNE.tail_reach):
				burnt_until = sim.tick + int(TUNE.reeds_burnt_ticks)
				u.charge = 0.0
				charged = false
				pollen = {}
				_emit_state(sim, u, "reeds_burnt")
				if mode == "idle" or mode == "approach":
					_anim(sim, u, "reeds_burnt_idle")
				break
	last_hp = hp
	var burnt := reeds_burnt(sim)
	if bool(u.reeds_burnt) and not burnt:
		_emit_state(sim, u, "reeds_regrown")
		burnt_until = -1
	u.reeds_burnt = burnt


func _idle_clip(sim: HHSim) -> String:
	if reeds_burnt(sim):
		return "reeds_burnt_idle"
	return "calm_soak" if state == "calm" else "aggravated_idle"


# ------------------------------------------------------------------ attacks

func _punch(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.punch_range), float(TUNE.punch_cone_deg), 1)
	_attack(sim, u, "forearm_punch", hexes, {
		"dmg_pct": float(TUNE.punch_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.punch_stagger) })


func _bite(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.bite_range), float(TUNE.bite_cone_deg), 1)
	_attack(sim, u, "bite", hexes, {
		"dmg_pct": float(TUNE.bite_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.bite_stagger) })


## The leaping squash: the danger area is its footprint at the landing hex
## (the player's hex when the footprint fits there, else the nearest fit).
## The window is the crouch tell; the last squash_air_ticks are the flight.
func _squash(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var to := _landing(sim, u, p.hex)
	var hexes: Array = []
	for h in HHHex.area(to, int(TUNE.squash_radius)):
		if sim.arena.exists(h):
			hexes.append(h)
	hexes.sort()
	var ticks := _attack(sim, u, "leaping_squash", hexes, {    # H276: the landing hull; its damage is the push-out's
		"dmg_pct": 0.0, "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": 0.0, "landing": true })
	mode = "squash"
	var air := mini(int(TUNE.squash_air_ticks), ticks)
	squash = { "to": to, "leap_at": sim.tick + ticks - air + 1, "land_at": sim.tick + ticks, "air": air, "flying": false }


func _squash_flight(sim: HHSim, u: Dictionary) -> void:
	if squash.is_empty():
		return
	if not bool(squash.flying) and sim.tick >= int(squash.leap_at):
		squash.flying = true
		var to: Vector2i = squash.to
		if to != u.hex:
			sim.begin_leap(u, to, int(squash.air), Callable())
			u.leap["splash"] = str(TUNE.squash_splash)     # H269: plain data, so it replicates
	if sim.tick >= int(squash.land_at):
		if (u.leap as Dictionary).is_empty():
			squashes_landed += 1
			squash = {}
		else:
			squash.land_at = sim.tick + 1          # a tick late: still in the air


## The hex it lands on: `at` when the footprint fits, else the nearest hex
## around it that fits (rings outward), else where it stands.
func _landing(sim: HHSim, u: Dictionary, at: Vector2i) -> Vector2i:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	if _fits(sim, u, at, kinds, blocked):
		return at
	for r in range(1, int(TUNE.squash_radius) + 3):
		var ring := HHHex.ring(at, r)
		ring.sort()
		for h in ring:
			if _fits(sim, u, h, kinds, blocked):
				return h
	return u.hex


## Three single-hex projectiles along the line through the player.
func _barb_throw(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var dist := HHHex.distance(u.hex, p.hex)
	var ln := _line_through(u, p.hex, int(TUNE.barb_range))
	var hexes: Array = []
	var n := int(TUNE.barb_count)
	for k in n:
		var i := dist - n / 2 + k                   # dist-1, dist, dist+1 along the line through the player
		i = clampi(i, int(u.size) + 1, int(TUNE.barb_range))
		if i - 1 < ln.size():
			var h: Vector2i = ln[i - 1]
			if sim.arena.exists(h) and not hexes.has(h):
				hexes.append(h)
	_attack(sim, u, "barb_throw", hexes, {
		"dmg_pct": float(TUNE.barb_dmg_pct), "element": "thunder", "paint_steps": int(TUNE.barb_paint_steps),
		"status": "", "status_ticks": 0, "stagger": 0.1 }, true)


func _reed_lash(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes: Array = []
	for h in _line_through(u, p.hex, int(u.size) + int(TUNE.lash_len)):
		if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
			hexes.append(h)
	_attack(sim, u, "reed_lash", hexes, {
		"dmg_pct": float(TUNE.lash_dmg_pct), "element": "thunder", "paint_steps": int(TUNE.lash_paint_steps),
		"status": "", "status_ticks": 0, "stagger": float(TUNE.lash_stagger) })


## The half ring behind it: 1..tail_ring beyond the footprint, within
## tail_arc_deg of the backward direction.
func _tail_drag(sim: HHSim, u: Dictionary) -> void:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var f := float(u.facing)
	var back := -Vector2(sin(f), cos(f))
	var cos_h := cos(deg_to_rad(float(TUNE.tail_arc_deg)))
	var hexes: Array = []
	for h in _around(sim, u, int(TUNE.tail_ring)):
		var v: Vector2 = HHHex.to_world(h, 1.0) - a
		if v.normalized().dot(back) >= cos_h:
			hexes.append(h)
	_attack(sim, u, "tail_drag", hexes, {
		"dmg_pct": float(TUNE.tail_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.tail_stagger) })


## The signature: the cloud is two telegraphs on the same hexes (the sim
## carries one status per payload): "pollen_shake" slows and paints dark 1,
## "pollen_spores" poisons. It pulses pollen_pulses times; whoever is in it
## at a pulse after being in it at the previous one (within linger_ticks)
## takes a paralysis strike on their own hex. Spends the whole charge.
func _pollen(sim: HHSim, u: Dictionary) -> void:
	u.charge = 0.0
	charged = false
	pollens += 1
	_emit_state(sim, u, "pollen")
	var cloud := _around(sim, u, int(TUNE.pollen_radius))
	var ticks := _attack(sim, u, "pollen_shake", cloud, _pollen_payload())
	_spores(sim, u, cloud, ticks)
	pollen = { "hexes": cloud, "checks": [sim.tick + ticks], "issued": 1, "seen": {} }


func _pollen_payload() -> Dictionary:
	return { "dmg_pct": float(TUNE.pollen_dmg_pct), "element": "dark", "paint_steps": int(TUNE.pollen_paint_steps),
		"status": "slow", "status_ticks": int(TUNE.pollen_slow_ticks), "stagger": 0.0, "clip": "pollen_shake", "name": "pollen_shake" }


func _spores(sim: HHSim, u: Dictionary, cloud: Array, ticks: int) -> void:
	sim.telegraph(u.id, cloud, ticks, { "dmg_pct": 0.0, "element": "", "paint_steps": 0,
		"status": "poison", "status_ticks": int(TUNE.pollen_poison_ticks), "stagger": 0.0, "clip": "pollen_shake", "name": "pollen_spores" })


func _pollen_pulse(sim: HHSim, u: Dictionary) -> void:
	if pollen.is_empty():
		return
	var checks: Array = pollen.checks
	if checks.is_empty() or sim.tick < int(checks[0]):
		return
	checks.pop_front()
	var seen: Dictionary = pollen.seen
	for v in sim.units_in(pollen.hexes, u.id):
		if v.kind != "player":
			continue
		if seen.has(v.id) and sim.tick - int(seen[v.id]) <= int(TUNE.pollen_linger_ticks):
			var spot: Array = []
			for h in HHHex.area(v.hex, 1):
				if sim.arena.exists(h):
					spot.append(h)
			sim.telegraph(u.id, spot, 2, { "dmg_pct": 0.0, "element": "", "paint_steps": 0,
				"status": "paralysis", "status_ticks": int(TUNE.pollen_paralysis_ticks), "stagger": 0.0,
				"clip": "pollen_shake", "name": "pollen_paralysis" })
			paralysed.append({ "tick": sim.tick, "id": v.id })
		seen[v.id] = sim.tick
	if int(pollen.issued) < int(TUNE.pollen_pulses):
		var ticks := int(TUNE.pollen_pulse_ticks)
		sim.telegraph(u.id, pollen.hexes, ticks, _pollen_payload())
		_spores(sim, u, pollen.hexes, ticks)
		pollen.issued = int(pollen.issued) + 1
		checks.append(sim.tick + ticks)
	elif checks.is_empty():
		pollen = {}


func _thunder_breath(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.breath_range), float(TUNE.breath_cone_deg))
	_attack(sim, u, "thunder_breath", hexes, {
		"dmg_pct": float(TUNE.thunder_dmg_pct), "element": "thunder", "paint_steps": int(TUNE.thunder_paint_steps),
		"status": "paralysis", "status_ticks": int(TUNE.thunder_paralysis_ticks), "stagger": 0.2 })


func _dark_breath(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.breath_range), float(TUNE.breath_cone_deg))
	_attack(sim, u, "dark_breath", hexes, {
		"dmg_pct": float(TUNE.dark_dmg_pct), "element": "dark", "paint_steps": int(TUNE.dark_paint_steps),
		"status": "poison", "status_ticks": int(TUNE.dark_poison_ticks), "stagger": 0.0 })


func _spore_spread(sim: HHSim, u: Dictionary) -> void:
	var hexes := _around(sim, u, int(TUNE.spore_radius))
	_attack(sim, u, "spore_spread", hexes, {
		"dmg_pct": float(TUNE.spore_dmg_pct), "element": "wind", "paint_steps": int(TUNE.spore_paint_steps),
		"status": "slow", "status_ticks": int(TUNE.spore_slow_ticks), "stagger": 0.0 })


## Issue a telegraph and its clip on the same tick: the window is the clip's
## contact tick x windup_mult (H38), clamped; the clip plays slowed so its
## contact lands with the shape. `split` issues one telegraph per hex (the
## barbs). Returns the window in ticks.
func _attack(sim: HHSim, u: Dictionary, clip: String, hexes: Array, payload: Dictionary, split: bool = false) -> int:
	mode = "attack"
	_stop(u)
	var contact := int(HHSpirewalkerClips.CLIPS[clip].contact_tick)
	var ticks := HHTierBrain.windup(u, clampi(int(round(float(contact) * float(TUNE.windup_mult))), int(TUNE.telegraph_min_ticks), int(TUNE.telegraph_max_ticks)))   # H360: identity on EASY
	var speed := float(contact) / float(ticks) if contact > 0 else 1.0
	payload["clip"] = clip
	if not payload.has("name"):
		payload["name"] = clip
	payload["flagged"] = false
	if split:
		for h in hexes:
			sim.telegraph(u.id, [h], ticks, payload)
	else:
		sim.telegraph(u.id, hexes, ticks, payload)
	attacks.append({ "tick": sim.tick, "clip": clip, "ticks": ticks, "hexes": hexes.duplicate(), "at": u.hex, "facing": float(u.facing) })
	_anim(sim, u, clip, speed)
	busy_until = sim.tick + int(ceil(float(_clip_ticks(clip)) / speed))
	next_attack_at = busy_until + _gap()
	repositioned = false
	return ticks


func _gap() -> int:
	return int(ceil(float(TUNE.attack_gap_ticks) * float(HHPhases.rule(phase_state, "gap_mult", 1.0))))


# ------------------------------------------------------------------ movement

func _approach(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	mode = "approach"
	var want := int(u.size) + int(TUNE.close_range)
	var best := Vector2i(-9999, -9999)
	var best_d := 1 << 30
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	for h in HHHex.ring(p.hex, want):
		if not _fits(sim, u, h, kinds, blocked):
			continue
		var d := HHHex.distance(u.hex, h)
		if d < best_d or (d == best_d and h < best):
			best_d = d
			best = h
	if best.x == -9999:
		_stop(u)
		_anim(sim, u, _idle_clip(sim))
		return
	_move(sim, u, best)
	_anim(sim, u, "walk" if not (u.path as Array).is_empty() else _idle_clip(sim))


## H39: between attacks it moves to a new spot around the player, 2-4 hexes
## beyond the footprint, preferring a change of bearing.
func _reposition(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var cur_bearing := HHHex.direction_index(p.hex, u.hex)
	var cands: Array = []
	for r in range(int(TUNE.reposition_min), int(TUNE.reposition_max) + 1):
		for h in HHHex.ring(p.hex, int(u.size) + r):
			if _fits(sim, u, h, kinds, blocked) and HHHex.distance(u.hex, h) <= 8:
				var bearing := HHHex.direction_index(p.hex, h)
				cands.append([h, 1 if bearing != cur_bearing else 0])
	if cands.is_empty():
		_stop(u)
		_anim(sim, u, _idle_clip(sim))
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var flank: Array = cands.filter(func(c): return int(c[1]) == 1)
	var pool: Array = flank if not flank.is_empty() else cands
	var pick: Vector2i = pool[int(floor(_rng(sim) * pool.size())) % pool.size()][0]
	mode = "approach"
	_move(sim, u, pick)
	_anim(sim, u, "walk" if not (u.path as Array).is_empty() else _idle_clip(sim))


func _move(sim: HHSim, u: Dictionary, to: Vector2i) -> void:
	if to == u.hex:
		_stop(u)
		return
	if to == goal and not (u.path as Array).is_empty():
		return
	if int(float(u.progress) * 1000.0) > 0 and not (u.path as Array).is_empty():
		return
	goal = to
	goals.append(to)
	sim.monster_move(u, to)


func _stop(u: Dictionary) -> void:
	if not (u.path as Array).is_empty() and int(float(u.progress) * 1000.0) > 0:
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		u.path = np
	else:
		u.path = [] as Array[Vector2i]
	goal = Vector2i(-9999, -9999)


static func _fits(sim: HHSim, u: Dictionary, h: Vector2i, kinds: Array, blocked: Dictionary) -> bool:
	for c in HHHex.area(h, int(u.size)):
		if not sim.arena.walkable(c) or blocked.has(c):
			return false
		if not str(sim.arena.kind(c)) in kinds:
			return false
	return true


func _turn_toward(u: Dictionary, hex: Vector2i) -> void:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var b: Vector2 = HHHex.to_world(hex, 1.0)
	var v := b - a
	if v.length_squared() < 1e-6:
		return
	var want := atan2(v.x, v.y)
	var cur := float(u.facing)
	var step := deg_to_rad(float(TUNE.turn_deg_per_tick))
	var diff := wrapf(want - cur, -PI, PI)
	u.facing = cur + clampf(diff, -step, step)


func _face(u: Dictionary, hex: Vector2i) -> void:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var b: Vector2 = HHHex.to_world(hex, 1.0)
	var v := b - a
	if v.length_squared() > 1e-6:
		u.facing = atan2(v.x, v.y)


# ------------------------------------------------------------------ shapes

## A cone of hexes toward `at`, `range_hexes` past the footprint, within
## `half_deg` of the heading. Ranged shapes start past the footprint
## (`min_dist` = size + 1, H312); the jaws and forearms reach under the body
## (`min_dist` 1) because a squashed player stands inside the footprint.
## With `at` at the centre the cone follows the facing.
func _cone(sim: HHSim, u: Dictionary, at: Vector2i, range_hexes: int, half_deg: float, min_dist: int = -1) -> Array:
	var out: Array = []
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var dirv: Vector2 = (HHHex.to_world(at, 1.0) - a)
	if dirv.length_squared() < 1e-6:
		dirv = Vector2(sin(float(u.facing)), cos(float(u.facing)))
	dirv = dirv.normalized()
	var lo := int(u.size) + 1 if min_dist < 0 else min_dist
	var cos_h := cos(deg_to_rad(half_deg))
	for h in HHHex.area(u.hex, int(u.size) + range_hexes):
		if not sim.arena.exists(h) or HHHex.distance(u.hex, h) < lo:
			continue
		var v: Vector2 = HHHex.to_world(h, 1.0) - a
		if v.normalized().dot(dirv) >= cos_h:
			out.append(h)
	out.sort()
	return out


## The straight hex line from the centre through `at`, continued past it
## (HHHex.step_beyond) to `length` hexes; index i-1 is the hex at distance i.
static func _line_through(u: Dictionary, at: Vector2i, length: int) -> Array:
	var out: Array = []
	if at == u.hex:
		return out
	var ln := HHHex.line(u.hex, at)
	for i in range(1, ln.size()):
		out.append(ln[i])
	while out.size() < length:
		var prev: Vector2i = out[-2] if out.size() >= 2 else u.hex
		out.append(HHHex.step_beyond(prev, out[-1]))
	return out.slice(0, length)


func _around(sim: HHSim, u: Dictionary, radius: int) -> Array:
	var out: Array = []
	for h in HHHex.area(u.hex, int(u.size) + radius):
		if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
			out.append(h)
	out.sort()
	return out


# ------------------------------------------------------------------ misc

func _ensure(u: Dictionary) -> void:
	if not u.has("allowed_kinds") or (u.allowed_kinds as Array).is_empty():
		u["allowed_kinds"] = ALLOWED_KINDS.duplicate()
	if not u.has("walk_ticks"):
		u["walk_ticks"] = float(TUNE.walk_ticks)
	if not u.has("untargetable"):
		u["untargetable"] = false
	if not u.has("charge"):
		u["charge"] = 0.0
	if not u.has("reeds_burnt"):
		u["reeds_burnt"] = false


## The hunter it goes for: the sim's one aggro rule (H53: nearest standing,
## with a threat bonus for the last hunter that hit it).
func _nearest_player(sim: HHSim, u: Dictionary) -> Dictionary:
	return sim.monster_target(u)


## Hexes between the footprint edge and the player's hex (0 = touching).
func _edge_dist(u: Dictionary, p: Dictionary) -> int:
	return maxi(0, HHHex.distance(u.hex, p.hex) - int(u.size))


func _clip_ticks(clip: String) -> int:
	return int(ceil(float(HHSpirewalkerClips.CLIPS[clip].duration) / HHSim.TICK))


func _rng(sim: HHSim) -> float:
	rolls += 1
	return sim.rng.randf()


func _anim(sim: HHSim, u: Dictionary, clip: String, speed: float = 1.0) -> void:
	if clip == anim and bool(HHSpirewalkerClips.CLIPS[clip].loop):
		return
	anim = clip
	sim._emit({ "type": "monster_anim", "id": u.id, "clip": clip, "speed": speed })
