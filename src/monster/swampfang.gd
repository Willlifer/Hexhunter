class_name HHSwampfang
extends RefCounted
## Swampfang's brain: node-free, seeded from sim.rng, one `tick()` per sim
## tick (the integrator keeps `sim.brains[id] = brain` and calls
## `brain.tick(sim, u)` inside HHSim.step after orders).
##
## Kickoff (Lane E): calm = floats half-submerged, only the frill showing.
## Aggravated (first damage, or a player within TUNE.aggro_hexes) = rises
## and rushes to close range; out of range it sprays dark-laced water or a
## water jet; close in it thrashes or builds momentum into a death-roll spin;
## the frill roar flags (empowers) the next attack. Its rear is weak: a
## player behind it makes it bite backward and miss, and hits from there do
## TUNE.rear_mult damage (rear_mult()). Threatened (< 0.5 hp) = dives, swims
## under the pads (untargetable, ripples mark the surface hex), surfaces in a
## lunge that spreads dark water. Enraged (< 0.25) = shorter gaps, more rolls.
##
## Pacing (H13): every attack is a telegraph (hex set + countdown) started on
## the same tick as its clip, with the countdown equal to the clip's contact
## tick (0.8-1.6 s); at least TUNE.attack_gap_ticks between the end of one
## attack and the next telegraph.
##
## Contracts built against (guide/02, Lane P):
##   sim.telegraph(owner_id: String, hexes: Array, ticks: int, payload: Dictionary)
##     payload: { dmg_pct, element, paint_steps, status, status_ticks, stagger 0..1, clip, flagged }
##     Until it exists the brain keeps its own countdown, emits a "telegraph"
##     event, and applies the payload itself through sim.hurt / apply_status / paint.
##   sim.monster_move(u: Dictionary, goal_hex: Vector2i)
##     footprint-aware path over hexes whose kind is in u.allowed_kinds. Until
##     it exists the brain sets u.path from sim.arena.path (walkable hexes).
## Events emitted: monster_anim { id, clip }, monster_state { id, state },
##   telegraph { id, hexes, ticks, payload } (fallback only).

## Every feel number, in one place (ticks are 30 Hz; pct = percent of max HP).
const TUNE := {
	"aggro_hexes": 6,                 # calm -> aggravated when a player is this close (edge to edge)
	"attack_gap_ticks": 12,           # 0.4 s from the end of one attack clip to the next telegraph (author: actions more common)
	"windup_mult": 1.8,               # H38: every telegraph window is the clip's contact tick x this (the clip slows to match)
	"telegraph_min_ticks": 40,        # telegraph windows 1.3-3.0 s
	"telegraph_max_ticks": 90,
	"reposition_chance": 0.7,         # H39: between attacks, move to a new spot around the player this often
	"reposition_min": 2,              # ... this many hexes beyond the footprint ...
	"reposition_max": 4,              # ... up to this many
	"walk_ticks": 10.0,               # ticks per hex (u.walk_ticks): heavy but it keeps moving
	"turn_deg_per_tick": 3.5,         # how fast it turns to face a player while standing
	"close_range": 1,                 # hexes beyond the footprint: "in its jaws"
	"thrash_range": 2,                # hexes beyond the footprint the thrash reaches
	"ranged_max": 9,                  # spray / jet reach (hexes from the centre)
	"spray_range": 6,                 # cone length from the centre
	"spray_cone_deg": 34.0,           # half-angle of the dark spray cone
	"spray_dmg_pct": 12.0,
	"spray_paint_steps": 2,           # dark on the ground
	"spray_poison_ticks": 150,        # 5 s of poison
	"jet_range": 9,                   # line length
	"jet_dmg_pct": 10.0,
	"jet_paint_steps": 2,             # water on the ground
	"thrash_dmg_pct": 15.0,
	"thrash_stagger": 0.5,
	"thrash_paint_steps": 2,          # water
	"roll_radius": 2,                 # hexes beyond the footprint
	"roll_dmg_pct": 30.0,
	"roll_stagger": 1.0,              # heavy stagger
	"roll_chance": 0.5,               # at close range, roll vs thrash (phases raise it)
	"lunge_radius": 1,                # hexes beyond the footprint at the surface hex
	"lunge_dmg_pct": 22.0,
	"lunge_stagger": 0.7,
	"lunge_paint_steps": 3,           # dark water
	"roar_chance": 0.35,              # chance to roar instead of a ranged attack when not yet flagged
	"roar_radius_plus": 1,            # H41: a flagged attack's shape grows by this many rings (not harder: bigger)
	"darkness_radius": 5,             # H40: the answer to a potion: dark over this radius around the drinker
	"darkness_ticks": 45,             # its telegraph window
	"darkness_cd_ticks": 450,         # at most one darkness every 15 s
	"rear_arc_deg": 120.0,            # the weak arc centred on the tail
	"rear_mult": 1.5,                 # damage multiplier from inside that arc
	"bite_back_reach": 3,             # hexes beyond the footprint: a player behind, this close, draws the miss
	"swim_ticks": 120,                # 4 s under the pads
	"swim_min_hexes": 5,              # the surface hex is this far from the player ...
	"swim_max_hexes": 9,              # ... and no farther
	"redive_every_ticks": 600,        # while threatened, dive again every 20 s
	"ripple_radius": 1,               # the ripple telegraph around the surface hex
}

const ALLOWED_KINDS := ["floor", "water", "deep"]
const SWIM_KINDS := ["water", "deep"]

var id := ""
var state := "calm"                   ## calm | aggravated | threatened | enraged
var mode := "idle"                    ## idle | approach | attack | bite_back | dive | swim | surface | dead
var phase_state := {}
var busy_until := 0                   ## no decisions before this tick (a clip is playing)
var next_attack_at := 0               ## no telegraph before this tick
var flagged := false                  ## the frill roar empowered the next attack
var want_dive := false
var last_dive_tick := -100000
var surface_at := 0
var surface_hex := Vector2i.ZERO
var goal := Vector2i(-9999, -9999)
var pending: Array = []               ## fallback telegraphs: [{ at, hexes, payload }]
var goals: Array = []                 ## every goal hex chosen (tests)
var attacks: Array = []               ## every telegraph issued: [{ tick, clip, ticks, hexes }] (tests)
var anim := ""                        ## the clip last asked for
var repositioned := false             ## already picked a new spot since the last attack
var darkness_at := -100000            ## tick of the last darkness
var rolls := 0                        ## rng draws (tests)


func _init(monster_id: String = "swampfang") -> void:
	id = monster_id
	phase_state = HHPhases.start(phases())


## The phase script (HHPhases): calm -> aggravated on first damage (the brain
## also forces it on proximity), threatened below 0.5 (dives), enraged below 0.25.
static func phases() -> Dictionary:
	return {
		"rules": { "gap_mult": 1.0, "roll_chance": TUNE.roll_chance, "dive": false },
		"phases": [
			{ "id": "aggravated", "trigger": { "hp_below": 1.0 }, "rules": {} },
			{ "id": "threatened", "trigger": { "hp_below": 0.5, "after": "aggravated" }, "rules": { "dive": true } },
			{ "id": "enraged", "trigger": { "hp_below": 0.25, "after": "threatened" }, "rules": { "gap_mult": 0.75, "roll_chance": 0.7 } },
		],
	}


## Damage multiplier for a hit on `u` from `from_hex`: TUNE.rear_mult inside
## the rear arc (centred on the tail), 1.0 elsewhere. Pure: uses u.hex and
## u.facing only (facing = atan2(dx, dz), the sim's convention).
static func rear_mult(u: Dictionary, from_hex: Vector2i) -> float:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var b: Vector2 = HHHex.to_world(from_hex, 1.0)
	var v := b - a
	if v.length_squared() < 1e-6:
		return 1.0
	var f := float(u.get("facing", 0.0))
	var fwd := Vector2(sin(f), cos(f))
	var ang := rad_to_deg(acos(clampf(fwd.dot(v.normalized()), -1.0, 1.0)))
	return float(TUNE.rear_mult) if ang > 180.0 - float(TUNE.rear_arc_deg) * 0.5 else 1.0


## True when `hex` lies behind the monster (inside the rear arc).
static func is_behind(u: Dictionary, hex: Vector2i) -> bool:
	return rear_mult(u, hex) > 1.0


# ------------------------------------------------------------------ the tick

func tick(sim: HHSim, u: Dictionary) -> void:
	_resolve_pending(sim)
	if not sim.alive(u):
		if mode != "dead":
			mode = "dead"
			_anim(sim, u, "death")
		return
	_ensure(u)
	var hp_frac := float(u.hp) / maxf(float(u.max_hp), 1.0)
	for pid in HHPhases.check(phase_state, hp_frac, sim.tick):
		_on_phase(sim, u, str(pid))
	var p := _nearest_player(sim, u)
	if _potion_seen(sim) and sim.tick - darkness_at >= int(TUNE.darkness_cd_ticks) and not p.is_empty():
		if state == "calm":
			_force_phase(sim, u, "aggravated")        # a potion wakes it (H40)
		_darkness(sim, u, p)
		return
	if state == "calm":
		if (not p.is_empty() and _edge_dist(u, p) <= int(TUNE.aggro_hexes)):
			_force_phase(sim, u, "aggravated")
		else:
			_anim(sim, u, "calm_float")
			return
	if sim.tick < busy_until:
		return
	match mode:
		"dive":
			_start_swim(sim, u, p)
			return
		"swim":
			if sim.tick >= surface_at or ((u.path as Array).is_empty() and u.hex == surface_hex):
				_surface(sim, u)
			return
		"surface", "attack", "bite_back":
			mode = "idle"
	if want_dive and sim.tick - last_dive_tick > int(TUNE.redive_every_ticks) * 0.5:
		_dive(sim, u)
		return
	if bool(HHPhases.rule(phase_state, "dive", false)) and sim.tick - last_dive_tick >= int(TUNE.redive_every_ticks):
		_dive(sim, u)
		return
	if p.is_empty():
		_stop(u)
		_anim(sim, u, "aggravated_idle")
		return
	var d := _edge_dist(u, p)
	if (u.path as Array).is_empty():
		_turn_toward(u, p.hex)
	if is_behind(u, p.hex) and d <= int(TUNE.bite_back_reach):
		_stop(u)
		mode = "bite_back"
		_anim(sim, u, "bite_back_miss")
		busy_until = sim.tick + _clip_ticks("bite_back_miss")
		return
	if sim.tick < next_attack_at:
		if d > int(TUNE.close_range):
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
	# choose an attack
	var roll_chance := float(HHPhases.rule(phase_state, "roll_chance", TUNE.roll_chance))
	if d <= int(TUNE.close_range):
		if flagged or _rng(sim) < roll_chance:
			_death_roll(sim, u)
		else:
			_thrash(sim, u)
	elif d <= int(TUNE.thrash_range):
		if _rng(sim) < 0.5:
			_thrash(sim, u)
		else:
			_approach(sim, u, p)
	elif HHHex.distance(u.hex, p.hex) <= int(TUNE.ranged_max):
		if not flagged and _rng(sim) < float(TUNE.roar_chance):
			_roar(sim, u)
		elif _rng(sim) < 0.5:
			_dark_spray(sim, u, p)
		else:
			_water_jet(sim, u, p)
	else:
		_approach(sim, u, p)


# ------------------------------------------------------------------ phases

func _on_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	match pid:
		"aggravated":
			if state == "calm":
				state = "aggravated"
				_emit_state(sim, u)
				_roar(sim, u)
		"threatened":
			state = "threatened"
			want_dive = true
			_emit_state(sim, u)
		"enraged":
			state = "enraged"
			want_dive = true
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

## H40: a player drank a potion this tick.
func _potion_seen(sim: HHSim) -> bool:
	for pl in sim.players():
		if sim.tick - int(pl.get("potion_tick", -100000)) <= 1:
			return true
	return false


## H40: monsters don't like potions: darkness over the drinker's ground
## (dark 2 on a wide area) so the heal starves until light clears it.
func _darkness(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	darkness_at = sim.tick
	var hexes: Array = []
	for h in HHHex.area(p.hex, int(TUNE.darkness_radius)):
		if sim.arena.exists(h) and sim.charge.can_hold(h):
			hexes.append(h)
	var payload := { "dmg_pct": 0.0, "element": "dark", "paint_steps": 2, "status": "", "status_ticks": 0, "stagger": 0.0, "clip": "frill_roar", "name": "darkness" }
	mode = "attack"
	_stop(u)
	if sim.has_method("telegraph"):
		sim.call("telegraph", u.id, hexes, int(TUNE.darkness_ticks), payload)
	attacks.append({ "tick": sim.tick, "clip": "darkness", "ticks": int(TUNE.darkness_ticks), "hexes": hexes.duplicate() })
	_anim(sim, u, "frill_roar")
	busy_until = sim.tick + _clip_ticks("frill_roar")
	next_attack_at = busy_until + _gap()


func _roar(sim: HHSim, u: Dictionary) -> void:
	flagged = true
	mode = "attack"
	_stop(u)
	_anim(sim, u, "frill_roar")
	busy_until = sim.tick + _clip_ticks("frill_roar")
	next_attack_at = busy_until + _gap()


func _dark_spray(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.spray_range), float(TUNE.spray_cone_deg))
	_attack(sim, u, "dark_spray", hexes, {
		"dmg_pct": float(TUNE.spray_dmg_pct), "element": "dark", "paint_steps": int(TUNE.spray_paint_steps),
		"status": "poison", "status_ticks": int(TUNE.spray_poison_ticks), "stagger": 0.0 })


func _water_jet(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes: Array = []
	for h in HHHex.ray(u.hex, p.hex, int(TUNE.jet_range)):
		if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
			hexes.append(h)
	_attack(sim, u, "water_jet", hexes, {
		"dmg_pct": float(TUNE.jet_dmg_pct), "element": "water", "paint_steps": int(TUNE.jet_paint_steps),
		"status": "", "status_ticks": 0, "stagger": 0.2 })


func _thrash(sim: HHSim, u: Dictionary) -> void:
	var hexes := _around(sim, u, int(TUNE.thrash_range))
	_attack(sim, u, "thrash_splash", hexes, {
		"dmg_pct": float(TUNE.thrash_dmg_pct), "element": "water", "paint_steps": int(TUNE.thrash_paint_steps),
		"status": "", "status_ticks": 0, "stagger": float(TUNE.thrash_stagger) })


func _death_roll(sim: HHSim, u: Dictionary) -> void:
	var hexes := _around(sim, u, int(TUNE.roll_radius))
	_attack(sim, u, "death_roll_spin", hexes, {
		"dmg_pct": float(TUNE.roll_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.roll_stagger) })


## Issue a telegraph and its clip on the same tick: the countdown is the
## clip's contact tick, clamped into the telegraph window.
func _attack(sim: HHSim, u: Dictionary, clip: String, hexes: Array, payload: Dictionary) -> void:
	mode = "attack"
	_stop(u)
	var contact := int(HHSwampfangClips.CLIPS[clip].contact_tick)
	var ticks := clampi(int(round(float(contact) * float(TUNE.windup_mult))), int(TUNE.telegraph_min_ticks), int(TUNE.telegraph_max_ticks))
	var speed := float(contact) / float(ticks) if contact > 0 else 1.0     # the clip slows so its contact lands with the telegraph
	payload["clip"] = clip
	payload["flagged"] = flagged
	if flagged:
		var grown: Array = []
		var own: Array = HHHex.area(u.hex, int(u.size))
		for h in HHHex.fringe(hexes, int(TUNE.roar_radius_plus)):
			if sim.arena.exists(h) and not h in own:
				grown.append(h)
		hexes = grown                                  # H41: a roared attack is BIGGER, not harder
		flagged = false
	if sim.has_method("telegraph"):
		sim.call("telegraph", u.id, hexes, ticks, payload)
	else:
		pending.append({ "at": sim.tick + ticks, "owner": u.id, "hexes": hexes, "payload": payload })
		sim._emit({ "type": "telegraph", "id": u.id, "hexes": hexes.duplicate(), "ticks": ticks, "payload": payload })
	attacks.append({ "tick": sim.tick, "clip": clip, "ticks": ticks, "hexes": hexes.duplicate() })
	_anim(sim, u, clip, speed)
	busy_until = sim.tick + int(ceil(float(_clip_ticks(clip)) / speed))
	next_attack_at = busy_until + _gap()
	repositioned = false


func _gap() -> int:
	return int(ceil(float(TUNE.attack_gap_ticks) * float(HHPhases.rule(phase_state, "gap_mult", 1.0))))


## The fallback telegraph resolution (no sim.telegraph yet): apply payloads
## whose countdown ran out.
func _resolve_pending(sim: HHSim) -> void:
	if pending.is_empty():
		return
	var keep: Array = []
	for t in pending:
		if sim.tick < int(t.at):
			keep.append(t)
			continue
		apply_payload(sim, str(t.owner), t.hexes, t.payload)
	pending = keep


## What a telegraph does when it lands (the integrator's telegraph() should
## do the same): damage + stagger + status to every unit in the hexes
## (never the owner), then the element painted on them.
static func apply_payload(sim: HHSim, owner: String, hexes: Array, payload: Dictionary) -> void:
	var hit := {}
	var pct := float(payload.get("dmg_pct", 0.0))
	for h in hexes:
		for v in sim.unit_at(h):
			if v.id == owner or hit.has(v.id):
				continue
			hit[v.id] = true
			if pct > 0.0:
				sim.hurt(v, HHFormulas.tile_damage(float(v.max_hp), pct).value, owner + "_" + str(payload.get("clip", "attack")), float(payload.get("stagger", 0.0)))
			var st := str(payload.get("status", ""))
			if st != "" and int(payload.get("status_ticks", 0)) > 0 and sim.alive(v):
				sim.apply_status(v, st, int(payload.status_ticks))
	var el := str(payload.get("element", ""))
	var steps := int(payload.get("paint_steps", 0))
	if el != "" and steps > 0 and not hexes.is_empty():
		sim.paint(hexes, el, owner, steps)


# ------------------------------------------------------------------ water

func _dive(sim: HHSim, u: Dictionary) -> void:
	want_dive = false
	last_dive_tick = sim.tick
	mode = "dive"
	_stop(u)
	u["untargetable"] = true
	_anim(sim, u, "dive")
	busy_until = sim.tick + _clip_ticks("dive")


func _start_swim(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	mode = "swim"
	u["allowed_kinds"] = SWIM_KINDS if _has_kind(sim, SWIM_KINDS) else ALLOWED_KINDS
	surface_hex = _pick_surface(sim, u, p)
	surface_at = sim.tick + int(TUNE.swim_ticks)
	u.run = true
	_move(sim, u, surface_hex)
	_anim(sim, u, "swim")
	# ripples: a harmless telegraph marking where it will come up
	var ripple := _around_at(sim, u, surface_hex, int(TUNE.ripple_radius))
	var payload := { "dmg_pct": 0.0, "element": "", "paint_steps": 0, "status": "", "status_ticks": 0, "stagger": 0.0, "clip": "swim", "ripple": true }
	if sim.has_method("telegraph"):
		sim.call("telegraph", u.id, ripple, int(TUNE.swim_ticks), payload)
	else:
		sim._emit({ "type": "telegraph", "id": u.id, "hexes": ripple, "ticks": int(TUNE.swim_ticks), "payload": payload })


func _surface(sim: HHSim, u: Dictionary) -> void:
	mode = "surface"
	u.run = false
	u["allowed_kinds"] = ALLOWED_KINDS
	u["untargetable"] = false
	_stop(u)
	var hexes := _around(sim, u, int(TUNE.lunge_radius))
	_attack(sim, u, "surface_lunge", hexes, {
		"dmg_pct": float(TUNE.lunge_dmg_pct), "element": "dark", "paint_steps": int(TUNE.lunge_paint_steps),
		"status": "", "status_ticks": 0, "stagger": float(TUNE.lunge_stagger) })
	mode = "surface"


## A hex to surface at: fits the footprint, preferably water, 5-9 hexes
## from the player, reachable; picked with the sim's rng.
func _pick_surface(sim: HHSim, u: Dictionary, p: Dictionary) -> Vector2i:
	var far: Array = []
	var any: Array = []
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var keys := sim.arena.cells.keys()
	keys.sort()
	var blocked := sim.blocked_for(u)
	var reach := _reachable(sim, u, blocked) if not sim.has_method("monster_move") else {}
	for h in keys:
		if not _fits(sim, u, h, kinds, blocked):
			continue
		if not reach.is_empty() and not reach.has(h):
			continue
		any.append(h)
		if not p.is_empty():
			var d := HHHex.distance(h, p.hex)
			if d >= int(TUNE.swim_min_hexes) and d <= int(TUNE.swim_max_hexes):
				far.append(h)
	var pool: Array = far if not far.is_empty() else any
	if pool.is_empty():
		return u.hex
	var i := int(floor(_rng(sim) * pool.size())) % pool.size()
	return pool[i]


## Every hex the monster's centre can walk to (one BFS over walk_neighbors).
static func _reachable(sim: HHSim, u: Dictionary, blocked: Dictionary) -> Dictionary:
	var seen := { u.hex: true }
	var queue: Array[Vector2i] = [u.hex]
	var qi := 0
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		for n in sim.arena.walk_neighbors(h, blocked):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _has_kind(sim: HHSim, kinds: Array) -> bool:
	for h in sim.arena.cells:
		if str(sim.arena.cells[h].kind) in kinds:
			return true
	return false


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


## H39: between attacks it does not stand still: a new spot around the
## player, 2-4 hexes beyond the footprint, preferring a change of bearing.
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
		return                                       # finish the current step first (no glide pop)
	goal = to
	goals.append(to)
	if sim.has_method("monster_move"):
		sim.call("monster_move", u, to)
	else:
		u.path = sim.arena.path(u.hex, to, sim.blocked_for(u))
		u.progress = 0.0


func _stop(u: Dictionary) -> void:
	if not (u.path as Array).is_empty() and int(float(u.progress) * 1000.0) > 0:
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		u.path = np                                  # land on the hex it is gliding to
	else:
		u.path = [] as Array[Vector2i]
	goal = Vector2i(-9999, -9999)


## The footprint fits at `h`: every covered hex exists, is walkable and of an
## allowed kind, and no other monster stands there.
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

## A cone of hexes from the monster's edge toward `at`, `range` long, within
## `half_deg` of the heading; never its own footprint.
func _cone(sim: HHSim, u: Dictionary, at: Vector2i, range_hexes: int, half_deg: float) -> Array:
	var out: Array = []
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var dirv: Vector2 = (HHHex.to_world(at, 1.0) - a)
	if dirv.length_squared() < 1e-6:
		return out
	dirv = dirv.normalized()
	var cos_h := cos(deg_to_rad(half_deg))
	for h in HHHex.area(u.hex, int(u.size) + range_hexes):
		if not sim.arena.exists(h) or HHHex.distance(u.hex, h) <= int(u.size):
			continue
		var v: Vector2 = HHHex.to_world(h, 1.0) - a
		if v.normalized().dot(dirv) >= cos_h:
			out.append(h)
	out.sort()
	return out


func _around(sim: HHSim, u: Dictionary, radius: int) -> Array:
	return _around_at(sim, u, u.hex, radius)


func _around_at(sim: HHSim, u: Dictionary, centre: Vector2i, radius: int) -> Array:
	var out: Array = []
	for h in HHHex.area(centre, int(u.size) + radius):
		if sim.arena.exists(h) and HHHex.distance(centre, h) > int(u.size):
			out.append(h)
	out.sort()
	return out


# ------------------------------------------------------------------ misc

func _ensure(u: Dictionary) -> void:
	if not u.has("allowed_kinds"):
		u["allowed_kinds"] = ALLOWED_KINDS
	if not u.has("walk_ticks"):
		u["walk_ticks"] = float(TUNE.walk_ticks)
	if not u.has("untargetable"):
		u["untargetable"] = false


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


## Hexes between the footprint edge and the player's hex (0 = touching).
func _edge_dist(u: Dictionary, p: Dictionary) -> int:
	return maxi(0, HHHex.distance(u.hex, p.hex) - int(u.size))


func _clip_ticks(clip: String) -> int:
	return int(ceil(float(HHSwampfangClips.CLIPS[clip].duration) / HHSim.TICK))


func _rng(sim: HHSim) -> float:
	rolls += 1
	return sim.rng.randf()


func _anim(sim: HHSim, u: Dictionary, clip: String, speed: float = 1.0) -> void:
	if clip == anim and bool(HHSwampfangClips.CLIPS[clip].loop):
		return
	anim = clip
	sim._emit({ "type": "monster_anim", "id": u.id, "clip": clip, "speed": speed })
