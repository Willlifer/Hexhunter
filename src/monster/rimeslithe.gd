class_name HHRimeslithe
extends RefCounted
## Rimeslithe's brain (the Swampfang pattern, H310): node-free, seeded from
## sim.rng, one `tick()` per sim tick from HHSim.step (sim.brains[id]).
##
## Kickoff (Lane E, Rimeslithe): huge, hunched, long forearms, a dragon head,
## ice crystals on its shoulders and back. Calm = seeks a cold vent or shade
## ("shade" / "vent" cells) and sits in it, frosting over: `u.cold` (0..1)
## rises there and with every ice attack; the crystals glow with it (the
## body's crystal material, later). Aggravated (a player within
## TUNE.aggro_hexes, or damage) = fights at medium and close range and, every
## TUNE.mist_every_ticks, exhales a wide freezing mist over the arena centre
## that paints the ground with ice (slow terrain) and slows whoever is in it.
## Enraged (< 0.25 hp) = shorter gaps, more meteors.
##
## Attacks (all through sim.telegraph with windup_mult 2.0, H38; the clip
## plays slowed so its contact lands with the telegraph):
##   frost_beam      a long line: ice 2 on even hexes + light 1 on odd hexes
##                   (two telegraphs on one tick), slow
##   cold_slam       radius-3 ring beyond the footprint, stagger, ice 1 (tell:
##                   both fists planted)
##   shoulder_charge a short line, heavy stagger; it drives down the line
##   roar            flags the next attack x1.5, adds cold
##   bite            front cone, stagger
##   arm_swipe       radius-3 half-ring in front
##   mist_breath     cone, ice 1 + slow (and the arena-wide mist)
##   meteor_drop     radius-2 hail zone on the player, 3 s, ice 3 + freeze
##   freeze_pillar   a rock / pillar near the player: the ring around it
##                   bursts (ice shards)
## Status: slow, then freeze: a player hit by two of its ice attacks within
## TUNE.freeze_window_ticks is frozen (the brain stacks it).
## Weak points (rear_mult): x1.5 while it stands on fire, or while
## u.cold > TUNE.cold_high; every hit while that high drains cold.
##
## Unit keys it writes: allowed_kinds, walk_ticks, untargetable, cold.

const TUNE := {
	"aggro_hexes": 8,                 # calm -> aggravated when a player is this close (edge to edge)
	"attack_gap_ticks": 36,           # 1.2 s from the end of one attack clip to the next telegraph
	"windup_mult": 2.0,               # the heaviest monster: telegraph = contact tick x2 (clip slowed to match)
	"telegraph_min_ticks": 40,
	"telegraph_max_ticks": 96,        # meteor_drop: 45 x 2 = 90 ticks = 3 s
	"reposition_chance": 0.7,         # H39
	"reposition_min": 2,
	"reposition_max": 4,
	"walk_ticks": 12.0,               # ticks per hex: slower than Swampfang (10)
	"charge_walk_ticks": 5.0,         # ... except down the shoulder-charge line
	"turn_deg_per_tick": 3.0,
	"close_range": 1,                 # hexes beyond the footprint: bite / slam / swipe
	"medium_range": 4,                # ... swipe / charge / mist
	"ranged_max": 10,                 # beam / meteor / pillar reach (hexes from the centre)
	"beam_range": 10,
	"beam_dmg_pct": 12.0,
	"beam_ice_steps": 2,
	"beam_light_steps": 1,
	"slam_radius": 3,
	"slam_dmg_pct": 18.0,
	"slam_stagger": 0.6,
	"slam_ice_steps": 1,
	"charge_range": 5,
	"charge_dmg_pct": 20.0,
	"charge_stagger": 0.9,
	"bite_range": 3,
	"bite_cone_deg": 30.0,
	"bite_dmg_pct": 16.0,
	"bite_stagger": 0.3,
	"swipe_radius": 3,
	"swipe_dmg_pct": 14.0,
	"swipe_stagger": 0.5,
	"mist_range": 6,
	"mist_cone_deg": 40.0,
	"mist_dmg_pct": 8.0,
	"mist_ice_steps": 1,
	"mist_every_ticks": 600,          # the arena-wide mist, every 20 s while aggravated
	"mist_radius": 7,                 # ... over the arena centre, this wide
	"mist_wide_dmg_pct": 5.0,
	"mist_wide_ticks": 60,            # its telegraph window (2 s)
	"meteor_radius": 2,
	"meteor_dmg_pct": 25.0,
	"meteor_ice_steps": 3,
	"meteor_chance": 0.3,             # at range, meteor vs beam (enrage raises it)
	"pillar_search": 6,               # a rock / pillar within this many hexes of the player
	"pillar_dmg_pct": 15.0,
	"pillar_ice_steps": 1,
	"pillar_chance": 0.4,
	"roar_chance": 0.3,
	"roar_dmg_mult": 1.5,
	"roar_cold": 0.2,                 # a roar stores this much cold
	"slow_ticks": 240,                # 8 s of slow from any ice attack
	"freeze_ticks": 60,               # 2 s frozen when slow stacks
	"freeze_window_ticks": 300,       # two ice hits within 10 s (one attack cycle at x2 windups) freeze
	"cold_gain_shade": 1.0 / 240.0,   # per tick in shade / on a vent: full in 8 s
	"cold_gain_attack": 0.15,         # per ice attack issued
	"cold_decay": 1.0 / 5400.0,       # per tick elsewhere: empties in 3 min
	"cold_drain_hit": 0.2,            # per hit taken while above cold_high
	"cold_high": 0.7,                 # weak point: crystals bright
	"cold_low": 0.3,                  # below this (and no player within seek_shade_hexes) it goes back to the cold ...
	"cold_sit_until": 0.8,            # ... and sits there until this full
	"seek_shade_hexes": 6,
	"weak_mult": 1.5,                 # heat under it, or crystals bright
}

const ALLOWED_KINDS := ["floor", "shade", "vent", "sun", "water"]
const SHADE_KINDS := ["shade", "vent"]
const PILLAR_KINDS := ["rock", "pillar"]
const ICE_CLIPS := ["frost_beam", "cold_slam", "mist_breath", "meteor_drop", "freeze_pillar", "mist_wide"]

## The sim the brain last ticked in: rear_mult (static, called by HHSim.strike)
## reads the ground and the unit's cold through it.
static var last_sim: HHSim = null

var id := ""
var state := "calm"                   ## calm | aggravated | enraged
var mode := "idle"                    ## idle | seek | sit | approach | attack | charge | dead
var phase_state := {}
var busy_until := 0
var next_attack_at := 0
var next_mist_at := -1                ## the arena-wide mist (-1: not aggravated yet)
var flagged := false
var goal := Vector2i(-9999, -9999)
var goals: Array = []                 ## every goal hex chosen (tests)
var attacks: Array = []               ## every telegraph issued: [{ tick, clip, ticks, hexes, element }] (tests)
var anim := ""
var repositioned := false
var rolls := 0
var charge_goal := Vector2i(-9999, -9999)
var ice_hits := {}                    ## player id -> [ticks of ice hits] (freeze stacking)
var pending_ice: Array = []           ## ice telegraphs waiting to resolve: [{ at, hexes }]
var last_hp := -1.0
var freezes := 0                      ## freezes applied (tests)
var want_cold := false                ## aggravated but low on cold: heading for the shade


func _init(monster_id: String = "rimeslithe") -> void:
	id = monster_id
	phase_state = HHPhases.start(phases())


func setup(_sim: HHSim, u: Dictionary) -> void:
	_ensure(u)


func allowed_kinds() -> Array:
	return ALLOWED_KINDS


## calm -> aggravated on first damage (the brain also forces it on
## proximity); enraged below 0.25: shorter gaps, more meteors.
static func phases() -> Dictionary:
	return {
		"rules": { "gap_mult": 1.0, "meteor_chance": TUNE.meteor_chance },
		"phases": [
			{ "id": "aggravated", "trigger": { "hp_below": 1.0 }, "rules": {} },
			{ "id": "enraged", "trigger": { "hp_below": 0.25, "after": "aggravated" }, "rules": { "gap_mult": 0.75, "meteor_chance": 0.55 } },
		],
	}


## Damage multiplier for a hit on `u` (from anywhere): TUNE.weak_mult when
## it stands on fire (any footprint hex carries fire) or its stored cold is
## above TUNE.cold_high; 1.0 otherwise. Reads the ground through last_sim.
static func rear_mult(u: Dictionary, _from_hex: Vector2i) -> float:
	if float(u.get("cold", 0.0)) > float(TUNE.cold_high):
		return float(TUNE.weak_mult)
	if last_sim != null and on_heat(last_sim, u):
		return float(TUNE.weak_mult)
	return 1.0


static func on_heat(sim: HHSim, u: Dictionary) -> bool:
	for h in HHHex.area(u.hex, int(u.get("size", 2))):
		if sim.charge.carries(h, "fire"):
			return true
	return false


# ------------------------------------------------------------------ the tick

func tick(sim: HHSim, u: Dictionary) -> void:
	last_sim = sim
	_ensure(u)
	_cold(sim, u)
	_stack_freeze(sim)
	if not sim.alive(u):
		if mode != "dead":
			mode = "dead"
			_anim(sim, u, "death")
		return
	var hp_frac := float(u.hp) / maxf(float(u.max_hp), 1.0)
	for pid in HHPhases.check(phase_state, hp_frac, sim.tick):
		_on_phase(sim, u, str(pid))
	var p := _nearest_player(sim, u)
	if state == "calm":
		if not p.is_empty() and _edge_dist(u, p) <= int(TUNE.aggro_hexes):
			_force_phase(sim, u, "aggravated")
		else:
			_calm(sim, u)
			return
	if sim.tick < busy_until:
		return
	if mode == "charge":
		u["walk_ticks"] = float(TUNE.walk_ticks)
		mode = "idle"
	elif mode in ["attack", "sit", "seek"]:
		mode = "idle"
	if p.is_empty():
		_stop(u)
		_anim(sim, u, "aggravated_idle")
		return
	# the sim lets a monster glide over a player (H31): never attack from on top of one, step off first
	if HHHex.distance(u.hex, p.hex) <= int(u.size):
		if (u.path as Array).is_empty():
			_reposition(sim, u, p)
		return
	# the arena-wide mist, on its own clock
	if next_mist_at >= 0 and sim.tick >= next_mist_at and sim.tick >= next_attack_at:
		_mist_wide(sim, u)
		return
	var d := _edge_dist(u, p)
	if (u.path as Array).is_empty():
		_turn_toward(u, p.hex)
	# low on cold and nobody close: back to the shade, and sit until charged (hysteresis)
	if d <= int(TUNE.seek_shade_hexes) or float(u.cold) >= float(TUNE.cold_sit_until):
		want_cold = false
	elif float(u.cold) < float(TUNE.cold_low):
		want_cold = true
	if want_cold:
		if _in_shade(sim, u):
			_stop(u)
			mode = "sit"
			_anim(sim, u, "frost_over")
			return
		if _seek_shade(sim, u):
			return
		want_cold = false
	if sim.tick < next_attack_at:
		if d > int(TUNE.medium_range):
			_approach(sim, u, p)
		elif not repositioned:
			repositioned = true
			if _rng(sim) < float(TUNE.reposition_chance):
				_reposition(sim, u, p)
			else:
				_stop(u)
				_anim(sim, u, "aggravated_idle")
		elif (u.path as Array).is_empty():
			_anim(sim, u, "aggravated_idle")
		return
	_choose(sim, u, p, d)


func _choose(sim: HHSim, u: Dictionary, p: Dictionary, d: int) -> void:
	var meteor_chance := float(HHPhases.rule(phase_state, "meteor_chance", TUNE.meteor_chance))
	if d <= int(TUNE.close_range):
		var r := _rng(sim)
		if flagged or r < 0.4:
			_cold_slam(sim, u)
		elif r < 0.7:
			_bite(sim, u, p)
		else:
			_arm_swipe(sim, u, p)
	elif d <= int(TUNE.medium_range):
		var r := _rng(sim)
		if d <= int(TUNE.swipe_radius) and r < 0.3:
			_arm_swipe(sim, u, p)
		elif r < 0.55:
			_shoulder_charge(sim, u, p)
		elif r < 0.8:
			_mist_breath(sim, u, p)
		else:
			_cold_slam(sim, u)
	elif HHHex.distance(u.hex, p.hex) <= int(TUNE.ranged_max):
		if not flagged and _rng(sim) < float(TUNE.roar_chance):
			_roar(sim, u)
		elif _rng(sim) < float(TUNE.pillar_chance) and _freeze_pillar(sim, u, p):
			pass
		elif _rng(sim) < meteor_chance:
			_meteor_drop(sim, u, p)
		else:
			_frost_beam(sim, u, p)
	else:
		_approach(sim, u, p)


# ------------------------------------------------------------------ calm and cold

func _calm(sim: HHSim, u: Dictionary) -> void:
	if sim.tick < busy_until:
		return
	if _in_shade(sim, u):
		_stop(u)
		mode = "sit"
		_anim(sim, u, "frost_over" if float(u.cold) < 1.0 else "calm_sit")
		return
	if not _seek_shade(sim, u):
		_stop(u)
		mode = "sit"
		_anim(sim, u, "calm_sit")


## The cold meter: rises in shade / on a vent, decays elsewhere, drains when
## hit while high (the weak point).
func _cold(sim: HHSim, u: Dictionary) -> void:
	var cold := float(u.cold)
	var hp := float(u.hp)
	if last_hp >= 0.0 and hp < last_hp and cold > float(TUNE.cold_high):
		cold -= float(TUNE.cold_drain_hit)
	last_hp = hp
	if _in_shade(sim, u):
		cold += float(TUNE.cold_gain_shade)
	else:
		cold -= float(TUNE.cold_decay)
	u.cold = clampf(cold, 0.0, 1.0)


func _in_shade(sim: HHSim, u: Dictionary) -> bool:
	return str(sim.arena.kind(u.hex)) in SHADE_KINDS


## Walk to the nearest shade / vent hex the footprint fits on. False if none.
func _seek_shade(sim: HHSim, u: Dictionary) -> bool:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var best := Vector2i(-9999, -9999)
	var best_d := 1 << 30
	var keys := sim.arena.cells.keys()
	keys.sort()
	for h in keys:
		if not str(sim.arena.kind(h)) in SHADE_KINDS:
			continue
		if not _fits(sim, u, h, kinds, blocked):
			continue
		var d := HHHex.distance(u.hex, h)
		if d < best_d:
			best_d = d
			best = h
	if best.x == -9999:
		return false
	mode = "seek"
	_move(sim, u, best)
	_anim(sim, u, "walk" if not (u.path as Array).is_empty() else "calm_sit")
	return true


# ------------------------------------------------------------------ phases

func _on_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	match pid:
		"aggravated":
			if state == "calm":
				state = "aggravated"
				next_mist_at = sim.tick + int(TUNE.mist_every_ticks)
				_emit_state(sim, u)
				_roar(sim, u)
		"enraged":
			state = "enraged"
			_emit_state(sim, u)


func _force_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	if HHPhases.fired(phase_state, pid):
		return
	for p in phase_state.script.get("phases", []):
		if str(p.id) == pid:
			phase_state.fired.append(pid)
			phase_state.rules.merge(Dictionary(p.get("rules", {})), true)
	_on_phase(sim, u, pid)


func _emit_state(sim: HHSim, u: Dictionary) -> void:
	sim._emit({ "type": "monster_state", "id": u.id, "state": state })


# ------------------------------------------------------------------ attacks

func _roar(sim: HHSim, u: Dictionary) -> void:
	flagged = true
	mode = "attack"
	_stop(u)
	u.cold = clampf(float(u.cold) + float(TUNE.roar_cold), 0.0, 1.0)
	_anim(sim, u, "roar")
	busy_until = sim.tick + _clip_ticks("roar")
	next_attack_at = busy_until + _gap()


func _frost_beam(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var ice: Array = []
	var light: Array = []
	var i := 0
	for h in _line_through(sim, u, p.hex, int(TUNE.beam_range)):
		if i % 2 == 0:
			ice.append(h)
		else:
			light.append(h)
		i += 1
	# the light half: same damage, light on the ground, no slow (light is neutral: it heals anyone who stands on it later)
	_attack(sim, u, "frost_beam", ice, {
		"dmg_pct": float(TUNE.beam_dmg_pct), "element": "ice", "paint_steps": int(TUNE.beam_ice_steps),
		"status": "slow", "status_ticks": int(TUNE.slow_ticks), "stagger": 0.2 },
		[{ "hexes": light, "payload": { "dmg_pct": float(TUNE.beam_dmg_pct), "element": "light", "paint_steps": int(TUNE.beam_light_steps),
			"status": "", "status_ticks": 0, "stagger": 0.2, "name": "frost_beam_light" } }])


func _cold_slam(sim: HHSim, u: Dictionary) -> void:
	_attack(sim, u, "cold_slam", _around(sim, u, int(TUNE.slam_radius)), {
		"dmg_pct": float(TUNE.slam_dmg_pct), "element": "ice", "paint_steps": int(TUNE.slam_ice_steps),
		"status": "slow", "status_ticks": int(TUNE.slow_ticks), "stagger": float(TUNE.slam_stagger) })


func _shoulder_charge(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes: Array = _line_through(sim, u, p.hex, int(u.size) + int(TUNE.charge_range))
	var last: Vector2i = hexes[hexes.size() - 1] if not hexes.is_empty() else u.hex
	_attack(sim, u, "shoulder_charge", hexes, {
		"dmg_pct": float(TUNE.charge_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.charge_stagger) })
	# it drives down the line as the clip plays (the fit check keeps it on the floor)
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var dest := Vector2i(-9999, -9999)
	for h in HHHex.line(u.hex, last):
		if h != u.hex and _fits(sim, u, h, kinds, blocked) and HHHex.distance(h, p.hex) > int(u.size):
			dest = h
	if dest.x != -9999:
		mode = "charge"
		charge_goal = dest
		u["walk_ticks"] = float(TUNE.charge_walk_ticks)
		_move(sim, u, dest)


func _bite(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	_attack(sim, u, "bite", _cone(sim, u, p.hex, int(TUNE.bite_range), float(TUNE.bite_cone_deg)), {
		"dmg_pct": float(TUNE.bite_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.bite_stagger) })


func _arm_swipe(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	_attack(sim, u, "arm_swipe", _cone(sim, u, p.hex, int(TUNE.swipe_radius), 90.0), {
		"dmg_pct": float(TUNE.swipe_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.swipe_stagger) })


func _mist_breath(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	_attack(sim, u, "mist_breath", _cone(sim, u, p.hex, int(TUNE.mist_range), float(TUNE.mist_cone_deg)), {
		"dmg_pct": float(TUNE.mist_dmg_pct), "element": "ice", "paint_steps": int(TUNE.mist_ice_steps),
		"status": "slow", "status_ticks": int(TUNE.slow_ticks), "stagger": 0.0 })


## The arena-wide mist: a wide area over the arena centre, ice 1 + slow;
## the body plays mist_breath over it.
func _mist_wide(sim: HHSim, u: Dictionary) -> void:
	next_mist_at = sim.tick + int(TUNE.mist_every_ticks)
	var hexes: Array = []
	for h in HHHex.area(Vector2i.ZERO, int(TUNE.mist_radius)):
		if sim.arena.exists(h) and sim.arena.kind(h) != "edge" and HHHex.distance(u.hex, h) > int(u.size):
			hexes.append(h)
	hexes.sort()
	_attack(sim, u, "mist_breath", hexes, {
		"dmg_pct": float(TUNE.mist_wide_dmg_pct), "element": "ice", "paint_steps": int(TUNE.mist_ice_steps),
		"status": "slow", "status_ticks": int(TUNE.slow_ticks), "stagger": 0.0, "name": "mist_wide" },
		[], int(TUNE.mist_wide_ticks))


func _meteor_drop(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	_attack(sim, u, "meteor_drop", _around_at(sim, u, p.hex, int(TUNE.meteor_radius), 0), {
		"dmg_pct": float(TUNE.meteor_dmg_pct), "element": "ice", "paint_steps": int(TUNE.meteor_ice_steps),
		"status": "freeze", "status_ticks": int(TUNE.freeze_ticks), "stagger": 0.5 })


## A rock / pillar within TUNE.pillar_search of the player: the ring around
## it bursts. False when there is none.
func _freeze_pillar(sim: HHSim, u: Dictionary, p: Dictionary) -> bool:
	var best := Vector2i(-9999, -9999)
	var best_d := 1 << 30
	for h in HHHex.area(p.hex, int(TUNE.pillar_search)):
		if not sim.arena.exists(h) or not str(sim.arena.kind(h)) in PILLAR_KINDS:
			continue
		var d := HHHex.distance(h, p.hex)
		if d < best_d or (d == best_d and h < best):
			best_d = d
			best = h
	if best.x == -9999:
		return false
	_face(u, best)
	var hexes: Array = []
	for h in HHHex.ring(best, 1):
		if sim.arena.exists(h) and not str(sim.arena.kind(h)) in PILLAR_KINDS:
			hexes.append(h)
	hexes.sort()
	_attack(sim, u, "freeze_pillar", hexes, {
		"dmg_pct": float(TUNE.pillar_dmg_pct), "element": "ice", "paint_steps": int(TUNE.pillar_ice_steps),
		"status": "slow", "status_ticks": int(TUNE.slow_ticks), "stagger": 0.3, "pillar": best })
	return true


## Issue a telegraph and its clip on the same tick (H306, H38): window =
## contact tick x windup_mult (or `window` when given), clamped; the clip is
## slowed so its contact lands with the telegraph. `extra` = more
## { hexes, payload } telegraphs on the same tick (the beam's light half).
func _attack(sim: HHSim, u: Dictionary, clip: String, hexes: Array, payload: Dictionary, extra: Array = [], window: int = -1) -> void:
	mode = "attack"
	_stop(u)
	var contact := int(HHRimeslitheClips.CLIPS[clip].contact_tick)
	var ticks := window if window > 0 else int(round(float(contact) * float(TUNE.windup_mult)))
	ticks = clampi(ticks, int(TUNE.telegraph_min_ticks), int(TUNE.telegraph_max_ticks))
	var speed := float(contact) / float(ticks) if contact > 0 else 1.0
	payload["clip"] = clip
	payload["flagged"] = flagged
	var mult := float(TUNE.roar_dmg_mult) if flagged else 1.0
	flagged = false
	payload["dmg_pct"] = float(payload.dmg_pct) * mult
	var name := str(payload.get("name", clip))
	var all_hexes: Array = hexes.duplicate()
	sim.telegraph(u.id, hexes, ticks, payload)
	for e in extra:
		var ep: Dictionary = e.payload
		ep["clip"] = clip
		ep["flagged"] = payload.flagged
		ep["dmg_pct"] = float(ep.dmg_pct) * mult
		sim.telegraph(u.id, e.hexes, ticks, ep)
		all_hexes.append_array(e.hexes)
	attacks.append({ "tick": sim.tick, "clip": clip, "name": name, "ticks": ticks, "hexes": hexes.duplicate(),
		"element": str(payload.get("element", "")), "at": u.hex })
	if name in ICE_CLIPS or str(payload.get("element", "")) == "ice":
		u.cold = clampf(float(u.cold) + float(TUNE.cold_gain_attack), 0.0, 1.0)
		pending_ice.append({ "at": sim.tick + ticks, "hexes": all_hexes })
	_anim(sim, u, clip, speed)
	busy_until = sim.tick + int(ceil(float(_clip_ticks(clip)) / speed))
	next_attack_at = busy_until + _gap()
	repositioned = false


func _gap() -> int:
	return int(ceil(float(TUNE.attack_gap_ticks) * float(HHPhases.rule(phase_state, "gap_mult", 1.0))))


## Slow, then freeze: an ice telegraph that resolved last tick counts as an
## ice hit on every player standing in its hexes now; two hits within
## TUNE.freeze_window_ticks freeze that player.
func _stack_freeze(sim: HHSim) -> void:
	if pending_ice.is_empty():
		return
	var keep: Array = []
	for t in pending_ice:
		if sim.tick <= int(t.at):
			keep.append(t)
			continue
		for v in sim.units_in(t.hexes, id):
			if v.kind != "player":
				continue
			var hits: Array = ice_hits.get(v.id, [])
			hits = hits.filter(func(x): return sim.tick - int(x) <= int(TUNE.freeze_window_ticks))
			hits.append(sim.tick)
			ice_hits[v.id] = hits
			if hits.size() >= 2 and not v.statuses.has("freeze"):
				sim.apply_status(v, "freeze", int(TUNE.freeze_ticks))
				freezes += 1
				ice_hits[v.id] = []
	pending_ice = keep


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
		_anim(sim, u, "aggravated_idle")
		return
	_move(sim, u, best)
	_anim(sim, u, "walk" if not (u.path as Array).is_empty() else "aggravated_idle")


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
		_anim(sim, u, "aggravated_idle")
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var flank: Array = cands.filter(func(c): return int(c[1]) == 1)
	var pool: Array = flank if not flank.is_empty() else cands
	var pick: Vector2i = pool[int(floor(_rng(sim) * pool.size())) % pool.size()][0]
	mode = "approach"
	_move(sim, u, pick)
	_anim(sim, u, "walk" if not (u.path as Array).is_empty() else "aggravated_idle")


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

func _cone(sim: HHSim, u: Dictionary, at: Vector2i, range_hexes: int, half_deg: float) -> Array:
	var out: Array = []
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var dirv: Vector2 = (HHHex.to_world(at, 1.0) - a)
	if dirv.length_squared() < 1e-6:
		dirv = Vector2(sin(float(u.facing)), cos(float(u.facing)))      # aimed at its own centre: along its facing
	dirv = dirv.normalized()
	var cos_h := cos(deg_to_rad(half_deg))
	for h in HHHex.area(u.hex, int(u.size) + range_hexes):
		if not sim.arena.exists(h) or HHHex.distance(u.hex, h) <= int(u.size):
			continue
		var v: Vector2 = HHHex.to_world(h, 1.0) - a
		if v.normalized().dot(dirv) >= cos_h - 1e-6:
			out.append(h)
	out.sort()
	return out


## A straight hex line from the footprint edge through `at`, `length` hexes
## from the centre (a true line, so it passes through the target hex rather
## than snapping to one of the six hex directions like HHHex.ray).
func _line_through(sim: HHSim, u: Dictionary, at: Vector2i, length: int) -> Array:
	var out: Array = []
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var v: Vector2 = HHHex.to_world(at, 1.0) - a
	if v.length_squared() < 1e-6:
		return out
	var far := HHHex.from_world(a + v.normalized() * (float(length) * 1.6), 1.0)
	for h in HHHex.line(u.hex, far):
		if HHHex.distance(u.hex, h) > length:
			break
		if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
			out.append(h)
	return out


func _around(sim: HHSim, u: Dictionary, radius: int) -> Array:
	return _around_at(sim, u, u.hex, radius, int(u.size))


## Hexes within `radius` of `centre` that exist, past `inner` from the centre.
func _around_at(sim: HHSim, _u: Dictionary, centre: Vector2i, radius: int, inner: int) -> Array:
	var out: Array = []
	for h in HHHex.area(centre, inner + radius):
		if sim.arena.exists(h) and HHHex.distance(centre, h) > inner:
			out.append(h)
	if inner == 0 and sim.arena.exists(centre):
		out.append(centre)
	out.sort()
	return out


# ------------------------------------------------------------------ misc

func _ensure(u: Dictionary) -> void:
	if not u.has("allowed_kinds") or (u.allowed_kinds as Array).is_empty():
		u["allowed_kinds"] = ALLOWED_KINDS
	if not u.has("walk_ticks"):
		u["walk_ticks"] = float(TUNE.walk_ticks)
	if not u.has("untargetable"):
		u["untargetable"] = false
	if not u.has("cold"):
		u["cold"] = 0.0


func _nearest_player(sim: HHSim, u: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 1 << 30
	for p in sim.players():
		if not sim.alive(p):
			continue
		var d := HHHex.distance(u.hex, p.hex)
		if d < best_d:
			best_d = d
			best = p
	return best


func _edge_dist(u: Dictionary, p: Dictionary) -> int:
	return maxi(0, HHHex.distance(u.hex, p.hex) - int(u.size))


func _clip_ticks(clip: String) -> int:
	return int(ceil(float(HHRimeslitheClips.CLIPS[clip].duration) / HHSim.TICK))


func _rng(sim: HHSim) -> float:
	rolls += 1
	return sim.rng.randf()


func _anim(sim: HHSim, u: Dictionary, clip: String, speed: float = 1.0) -> void:
	if clip == anim and bool(HHRimeslitheClips.CLIPS[clip].loop):
		return
	anim = clip
	sim._emit({ "type": "monster_anim", "id": u.id, "clip": clip, "speed": speed })
