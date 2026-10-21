class_name HHColambros
extends RefCounted
## Colambros's brain: node-free, seeded from sim.rng, one `tick()` per sim
## tick (`sim.brains[id] = brain`; HHSim.step calls `brain.tick(sim, u)`
## after orders). The Swampfang pattern (H310-H316) for THE ONE FAST MONSTER.
##
## Kickoff (Lane E, Colambros): calm = sprawls in the sun and gnaws loose
## quills off its flanks. Aggravated (a player within TUNE.aggro_hexes, or
## damage) = runs laps of the arena (every reposition is a far run of 8-14
## hexes, on all fours) and CHARGES in a straight line when the player is
## far: the dirt-scrape lights the whole line for ~1.5 s, then it crosses the
## line at TUNE.run_ticks per hex (2-3x the player's run). After the first
## lap (TUNE.lap_hexes travelled) its quills SMOULDER: every charge paints a
## burning trail (fire 1, 2 on "vent" cells). Close in it bites, lashes its
## tail at whoever stands beside or behind it, and back-rolls, scattering
## smouldering quills; at range it spits embers (three fire areas toward the
## player) or leaps onto the player's hex and stomps (H275: the stomp hurts
## through the push-out, 20%, and splashes fire on its Attack Ring). The rattle-roar flags
## the next attack. After the roll it is BALD for TUNE.bald_ticks: 2x damage
## from any side (rear_mult), on top of 1.3x from behind. Enraged < 0.25.
##
## Contracts (guide/02): sim.telegraph(owner, hexes, ticks, payload) with
## payload { dmg_pct, element, paint_steps, status, status_ticks, stagger, clip,
## flagged, name }, sim.monster_move, sim.begin_leap, u.walk_ticks,
## u.allowed_kinds. Keys this brain writes on its unit (none in state_hash):
## allowed_kinds, walk_ticks, bald_until, now, smoulder, untargetable.
## Events: monster_anim { id, clip, speed }, monster_state { id, state }.

## Every feel number, in one place (ticks are 30 Hz; pct = percent of max HP).
const TUNE := {
	"aggro_hexes": 8,                 # calm -> aggravated when a player is this close (edge to edge)
	"attack_gap_ticks": 24,           # 0.8 s from the end of one attack clip to the next telegraph (fast monster)
	"windup_mult": 1.8,               # H38: telegraph window = clip contact tick x this (the clip slows to match)
	"telegraph_min_ticks": 40,        # 1.3-3.0 s
	"telegraph_max_ticks": 90,
	"walk_ticks": 8.0,                # ticks per hex on two legs (biped walk)
	"run_ticks": 3.0,                 # ticks per hex on all fours: the charge and the laps (~11 m/s vs the player's 8)
	"turn_deg_per_tick": 6.0,         # it turns fast
	"lap_min": 8,                     # a lap leg: this many hexes away ...
	"lap_max": 14,                    # ... up to this
	"lap_hexes": 22,                  # hexes travelled since aggravation before the quills smoulder (one lap)
	"close_range": 1,                 # hexes beyond the footprint: in its jaws
	"melee_range": 2,                 # ... the tail reaches
	"charge_min_dist": 5,             # charge only when the player is at least this far (edge)
	"charge_len_min": 6,              # a charge line shorter than this is not worth it: approach instead
	"charge_len_max": 16,             # the line is clamped to walkable hexes, at most this long
	"charge_width": 1,                # hexes either side of the line that the body covers
	"charge_dmg_pct": 30.0,          # H422 easy calibration x1.25 (was 24)
	"charge_stagger": 0.9,            # heavy
	"charge_paint_steps": 1,          # the burning trail (smouldering only)
	"vent_paint_steps": 2,            # ... hotter on vents
	"charge_chance": 0.75,            # when a line is open and the player is far, charge (else spit / leap)
	"bite_range": 2,                  # cone length beyond the footprint
	"bite_cone_deg": 42.0,
	"bite_dmg_pct": 17.5,            # H422 easy calibration x1.25 (was 14)
	"bite_stagger": 0.3,
	"lash_range": 3,                  # arc reach beyond the footprint
	"lash_arc_deg": 100.0,            # half-angle of the arc, centred on the player's bearing (side/rear)
	"lash_dmg_pct": 22.5,            # H422 easy calibration x1.25 (was 18)
	"lash_stagger": 0.6,
	"spit_min": 3,                    # ember spit when the player is 3..9 hexes out (edge)
	"spit_max": 9,
	"spit_areas": 3,                  # three small areas along the ray toward the player
	"spit_radius": 1,
	"spit_dmg_pct": 12.5,            # H422 easy calibration x1.25 (was 10)
	"spit_paint_steps": 2,            # fire 2
	"burn_ticks": 120,                # 4 s of burn
	"leap_min": 3,                    # leap and stomp when the player is 3..8 out
	"leap_max": 8,
	"leap_air_ticks": 15,             # 0.5 s in the air at the end of the window
	# H268/H275: the stomp's own damage (26%, footprint + 1) is gone: the telegraph marks the landing hull,
	# the hunters under it take the push-out's push_land_pct (HHTune), and the ring gets the splash
	"leap_splash": "fire",            # H269: the element it splashes on the Attack Ring as it lands (HHTune leap_splash_steps)
	"roll_radius": 3,                 # back-roll reach beyond the footprint
	"roll_dmg_pct": 27.5,            # H422 easy calibration x1.25 (was 22)
	"roll_stagger": 0.8,
	"roll_chance": 0.4,               # at melee range, roll vs bite/lash
	"roll_scatter": 10,               # smouldering quills scattered: this many hexes within roll_radius + 3 get fire 1
	"roll_paint_steps": 1,
	"bald_ticks": 120,                # 4 s bald after a roll
	"bald_mult": 2.0,                 # damage multiplier while bald (any side)
	"bald_rest_ticks": 36,            # it stays put, dazed, this long after the roll
	"roar_chance": 0.3,
	"roar_dmg_mult": 1.5,
	"rear_arc_deg": 120.0,
	"rear_mult": 1.3,
	"gnaw_every_ticks": 330,          # calm: a quill gnaw every 11 s
	"rethink_ticks": 12,              # while approaching, look again this often (no per-tick rng drain)
}

const ALLOWED_KINDS := ["floor", "vent", "sun", "shade", "water"]
const VENT_KIND := "vent"

var id := ""
var state := "calm"                   ## calm | aggravated | smoulder | enraged
var mode := "idle"                    ## idle | lap | approach | attack | charge_run | leap | dead
var phase_state := {}
var busy_until := 0
var next_attack_at := 0
var flagged := false
var smouldering := false
var travelled := 0                    ## hexes moved since aggravation
var last_hex := Vector2i(-9999, -9999)
var lapped := false                   ## picked a lap leg since the last attack
var goal := Vector2i(-9999, -9999)
var goals: Array = []                 ## every goal hex chosen (tests)
var attacks: Array = []               ## every telegraph issued: [{ tick, clip, ticks, hexes, line, travelled }] (tests)
var charges: Array = []               ## every charge: { tick, line, start_hex, end_hex, run_from } (tests)
var anim := ""
var rolls := 0                        ## rng draws (tests)
var charge_line: Array = []
var charge_end_at := 0
var leap_to := Vector2i.ZERO
var leap_at := 0
var leap_started := false
var bald_rest_until := 0
var gnaw_at := 0


func _init(monster_id: String = "colambros") -> void:
	id = monster_id
	phase_state = HHPhases.start(phases())


static func allowed_kinds() -> Array:
	return ALLOWED_KINDS.duplicate()


## The phase script (HHPhases): calm -> aggravated on first damage (the brain
## also forces it on proximity); "smoulder" is forced after the first lap
## (no hp trigger); enraged below 0.25.
static func phases() -> Dictionary:
	return {
		"rules": { "gap_mult": 1.0, "roll_chance": TUNE.roll_chance, "charge_chance": TUNE.charge_chance, "trails": false },
		"phases": [
			{ "id": "aggravated", "trigger": { "hp_below": 1.0 }, "rules": {} },
			{ "id": "smoulder", "trigger": { "hp_below": -1.0, "after": "aggravated" }, "rules": { "trails": true } },
			{ "id": "enraged", "trigger": { "hp_below": 0.25, "after": "aggravated" }, "rules": { "gap_mult": 0.7, "roll_chance": 0.55, "charge_chance": 0.85 } },
		],
	}


## Damage multiplier for a hit on `u` from `from_hex`: TUNE.bald_mult while
## `u.bald_until > u.now` (the brain writes `now` each tick), times
## TUNE.rear_mult from inside the rear arc. Pure: u.hex, u.facing, u.bald_until, u.now.
static func rear_mult(u: Dictionary, from_hex: Vector2i) -> float:
	var m := 1.0
	if int(u.get("bald_until", 0)) > int(u.get("now", 0)):
		m = float(TUNE.bald_mult)
	if is_behind(u, from_hex):
		m *= float(TUNE.rear_mult)
	return m


static func is_behind(u: Dictionary, hex: Vector2i) -> bool:
	return _bearing_deg(u, hex) > 180.0 - float(TUNE.rear_arc_deg) * 0.5


## Angle (deg) between the monster's facing and the direction to `hex`; 0 = dead ahead.
static func _bearing_deg(u: Dictionary, hex: Vector2i) -> float:
	var a: Vector2 = HHHex.to_world(u.hex, 1.0)
	var b: Vector2 = HHHex.to_world(hex, 1.0)
	var v := b - a
	if v.length_squared() < 1e-6:
		return 0.0
	var f := float(u.get("facing", 0.0))
	var fwd := Vector2(sin(f), cos(f))
	return rad_to_deg(acos(clampf(fwd.dot(v.normalized()), -1.0, 1.0)))


static func is_bald(u: Dictionary) -> bool:
	return int(u.get("bald_until", 0)) > int(u.get("now", 0))


# ------------------------------------------------------------------ the tick

func tick(sim: HHSim, u: Dictionary) -> void:
	u["now"] = sim.tick
	if not sim.alive(u):
		if mode != "dead":
			mode = "dead"
			_anim(sim, u, "death")
		return
	_ensure(u)
	if u.hex != last_hex:
		if last_hex.x != -9999 and state != "calm":
			travelled += 1
		last_hex = u.hex
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
	if not smouldering and travelled >= int(TUNE.lap_hexes):
		_force_phase(sim, u, "smoulder")
	if mode == "charge_run":
		_charge_run(sim, u)
		return
	if mode == "leap":
		if not leap_started and sim.tick >= leap_at:
			leap_started = true
			sim.begin_leap(u, leap_to, int(TUNE.leap_air_ticks), Callable())
			u.leap["splash"] = str(TUNE.leap_splash)       # H269: plain data, so it replicates
		if sim.tick < busy_until:
			return
		mode = "idle"
	if sim.tick < busy_until:
		return
	if mode == "attack":
		mode = "idle"
	if p.is_empty():
		_stop(u)
		_anim(sim, u, _idle_clip(u))
		return
	var d := _edge_dist(u, p)
	if (u.path as Array).is_empty():
		_turn_toward(u, p.hex)
	if sim.tick < bald_rest_until:
		_stop(u)
		_anim(sim, u, "bald_idle")
		return
	if sim.tick < next_attack_at:
		# between attacks it roams: one far run (a lap leg), then faces the player
		if not lapped:
			lapped = true
			_lap(sim, u, p)
		elif (u.path as Array).is_empty():
			if d > int(TUNE.melee_range) + 2 and sim.tick + 20 < next_attack_at:
				_approach(sim, u, p, true)
			else:
				_anim(sim, u, _idle_clip(u))
		return
	if mode == "lap" and not (u.path as Array).is_empty():
		return                                         # a lap leg runs to its end before the next attack
	if int(float(u.progress) * 1000.0) > 0 and not (u.path as Array).is_empty():
		return                                         # decide standing on a hex, not mid-glide
	_choose(sim, u, p, d)


func _choose(sim: HHSim, u: Dictionary, p: Dictionary, d: int) -> void:
	var roll_chance := float(HHPhases.rule(phase_state, "roll_chance", TUNE.roll_chance))
	var charge_chance := float(HHPhases.rule(phase_state, "charge_chance", TUNE.charge_chance))
	var bearing := _bearing_deg(u, p.hex)
	if d <= int(TUNE.melee_range):
		if _rng(sim) < roll_chance:
			_back_roll(sim, u)
		elif bearing > 70.0:
			_tail_lash(sim, u, p)
		elif d <= int(TUNE.close_range):
			_bite(sim, u, p)
		else:
			_approach(sim, u, p, false)
		return
	if not flagged and _rng(sim) < float(TUNE.roar_chance):
		_roar(sim, u)
		return
	if d >= int(TUNE.charge_min_dist):
		var line := _charge_line(sim, u, p)
		if line.size() >= int(TUNE.charge_len_min) and _rng(sim) < charge_chance:
			_charge(sim, u, p, line)
			return
	if d >= int(TUNE.spit_min) and d <= int(TUNE.spit_max):
		if d >= int(TUNE.leap_min) and d <= int(TUNE.leap_max) and _rng(sim) < 0.5:
			if _leap(sim, u, p):
				return
		_ember_spit(sim, u, p)
		return
	_approach(sim, u, p, d > 4)


# ------------------------------------------------------------------ phases

func _on_phase(sim: HHSim, u: Dictionary, pid: String) -> void:
	match pid:
		"aggravated":
			if state == "calm":
				state = "aggravated"
				travelled = 0
				_emit_state(sim, u)
				_roar(sim, u)
		"smoulder":
			smouldering = true
			u["smoulder"] = true
			if state != "enraged":
				state = "smoulder"
			_emit_state(sim, u)
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
	sim._emit({ "type": "monster_state", "id": u.id, "state": state, "smoulder": smouldering })


# ------------------------------------------------------------------ calm

func _calm(sim: HHSim, u: Dictionary) -> void:
	_stop(u)
	if gnaw_at == 0:
		gnaw_at = sim.tick + int(TUNE.gnaw_every_ticks)
	if sim.tick >= gnaw_at:
		gnaw_at = sim.tick + int(TUNE.gnaw_every_ticks)
		_anim(sim, u, "quill_gnaw")
		busy_until = sim.tick + _clip_ticks("quill_gnaw")
	elif sim.tick >= busy_until:
		_anim(sim, u, "calm_sprawl")


# ------------------------------------------------------------------ attacks

func _roar(sim: HHSim, u: Dictionary) -> void:
	flagged = true
	mode = "attack"
	_stop(u)
	_anim(sim, u, "rattle_roar")
	busy_until = sim.tick + _clip_ticks("rattle_roar")
	next_attack_at = busy_until + _gap()
	lapped = false


func _bite(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var hexes := _cone(sim, u, p.hex, int(TUNE.bite_range), float(TUNE.bite_cone_deg))
	_attack(sim, u, "bite", hexes, {
		"dmg_pct": float(TUNE.bite_dmg_pct), "element": "fire" if smouldering else "", "paint_steps": 0,
		"status": "burn" if smouldering else "", "status_ticks": int(TUNE.burn_ticks) if smouldering else 0,
		"stagger": float(TUNE.bite_stagger) })


func _tail_lash(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	# the arc of hexes on the player's side and behind, never ahead
	var hexes := _arc(sim, u, p.hex, int(TUNE.lash_range), float(TUNE.lash_arc_deg))
	_attack(sim, u, "tail_lash", hexes, {
		"dmg_pct": float(TUNE.lash_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.lash_stagger) })


func _ember_spit(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	_face(u, p.hex)
	var dist := HHHex.distance(u.hex, p.hex)
	var ray := HHHex.ray(u.hex, p.hex, dist + 2)
	var hexes := {}
	var n := int(TUNE.spit_areas)
	for i in n:
		var at := clampi(dist - 2 + 2 * i, int(u.size) + 1, ray.size())
		var centre: Vector2i = ray[at - 1]
		for h in HHHex.area(centre, int(TUNE.spit_radius)):
			if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
				hexes[h] = true
	var out := hexes.keys()
	out.sort()
	_attack(sim, u, "ember_spit", out, {
		"dmg_pct": float(TUNE.spit_dmg_pct), "element": "fire", "paint_steps": int(TUNE.spit_paint_steps),
		"status": "burn", "status_ticks": int(TUNE.burn_ticks), "stagger": 0.1 })


func _leap(sim: HHSim, u: Dictionary, p: Dictionary) -> bool:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var to: Vector2i = p.hex
	if not _fits(sim, u, to, kinds, blocked):
		to = _nearest_fit(sim, u, p.hex, kinds, blocked, 3)
		if to.x == -9999:
			return false
	_face(u, to)
	var hexes: Array = []
	for h in HHHex.area(to, int(u.size)):              # H275: the landing hull; its damage is the push-out's (H268)
		if sim.arena.exists(h):
			hexes.append(h)
	hexes.sort()
	var ticks := _attack(sim, u, "leap_stomp", hexes, {
		"dmg_pct": 0.0, "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": 0.0, "landing": true })
	mode = "leap"
	leap_to = to
	leap_at = sim.tick + ticks - int(TUNE.leap_air_ticks)
	leap_started = false
	lapped = true                                      # it lands on the player and stays to fight
	return true


func _back_roll(sim: HHSim, u: Dictionary) -> void:
	var hexes := _around(sim, u, int(TUNE.roll_radius))
	var ticks := _attack(sim, u, "back_roll", hexes, {
		"dmg_pct": float(TUNE.roll_dmg_pct), "element": "", "paint_steps": 0,
		"status": "", "status_ticks": 0, "stagger": float(TUNE.roll_stagger) })
	if smouldering:
		# the scattered quills: a seeded handful of hexes out to roll_radius + 3 catch fire
		var pool: Array = []
		for h in HHHex.area(u.hex, int(u.size) + int(TUNE.roll_radius) + 3):
			if sim.arena.exists(h) and HHHex.distance(u.hex, h) > int(u.size):
				pool.append(h)
		pool.sort()
		var picked: Array = []
		for i in int(TUNE.roll_scatter):
			if pool.is_empty():
				break
			var k := int(floor(_rng(sim) * pool.size())) % pool.size()
			picked.append(pool[k])
			pool.remove_at(k)
		picked.sort()
		if not picked.is_empty():
			_telegraph(sim, u, "quill_scatter", picked, ticks, {
				"dmg_pct": 0.0, "element": "fire", "paint_steps": int(TUNE.roll_paint_steps),
				"status": "", "status_ticks": 0, "stagger": 0.0, "clip": "back_roll", "flagged": false })
	u["bald_until"] = sim.tick + ticks + int(TUNE.bald_ticks)
	bald_rest_until = busy_until + int(TUNE.bald_rest_ticks)


# ------------------------------------------------------------------ the charge

## The charge line: HHHex.ray from the monster's hex toward the player, up to
## charge_len_max hexes, cut where the footprint no longer fits (lava, rock,
## pillar, the edge, another monster) or a cliff step appears.
func _charge_line(sim: HHSim, u: Dictionary, p: Dictionary) -> Array:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var out: Array = []
	var prev: Vector2i = u.hex
	var max_step := HHTune.value("max_step_m")
	for h in HHHex.ray(u.hex, p.hex, int(TUNE.charge_len_max)):
		if not _fits(sim, u, h, kinds, blocked):
			break
		if absf(sim.arena.hex_height(h) - sim.arena.hex_height(prev)) > max_step:
			break
		out.append(h)
		prev = h
	return out


func _charge(sim: HHSim, u: Dictionary, p: Dictionary, line: Array) -> void:
	_face(u, line[-1])
	mode = "attack"
	_stop(u)
	var contact := int(HHColambrosClips.CLIPS.dirt_scrape.contact_tick)
	var scrape := HHTierBrain.windup(u, clampi(int(round(float(contact) * float(TUNE.windup_mult))), int(TUNE.telegraph_min_ticks), int(TUNE.telegraph_max_ticks)))   # H400: identity on EASY
	var speed := float(contact) / float(scrape)
	var run := int(TUNE.run_ticks)
	var trails := smouldering
	# the lane: each line hex plus the hexes beside it, each hex in exactly one
	# segment; segment i resolves when the body reaches line hex i, so the whole
	# lane lights at once and a player who leaves before the body arrives is safe
	var owner := {}
	var segs: Array = []
	for i in line.size():
		segs.append([])
	for i in line.size():
		var h: Vector2i = line[i]
		if not owner.has(h):
			owner[h] = i
			segs[i].append(h)
	for i in line.size():
		for n in HHHex.area(line[i], int(TUNE.charge_width)):
			if sim.arena.exists(n) and not owner.has(n) and HHHex.distance(u.hex, n) > int(u.size):
				owner[n] = i
				segs[i].append(n)
	var payload := {
		"dmg_pct": float(TUNE.charge_dmg_pct) * (float(TUNE.roar_dmg_mult) if flagged else 1.0),
		"element": "fire" if trails else "", "paint_steps": int(TUNE.charge_paint_steps) if trails else 0,
		"status": "burn" if trails else "", "status_ticks": int(TUNE.burn_ticks) if trails else 0,
		"stagger": float(TUNE.charge_stagger), "clip": "charge", "flagged": flagged, "name": "charge" }
	flagged = false
	var all: Array = []
	var vents: Array = []
	for i in line.size():
		var hexes: Array = segs[i]
		if hexes.is_empty():
			continue
		hexes.sort()
		all.append_array(hexes)
		var ticks := scrape + (i + 1) * run
		_telegraph(sim, u, "charge", hexes, ticks, payload)
		if trails:
			for h in hexes:
				if str(sim.arena.kind(h)) == VENT_KIND:
					vents.append([h, ticks])
	for v in vents:
		# the vent burns one step hotter: a harmless second telegraph on that hex
		_telegraph(sim, u, "charge_vent", [v[0]], int(v[1]), {
			"dmg_pct": 0.0, "element": "fire", "paint_steps": int(TUNE.vent_paint_steps) - int(TUNE.charge_paint_steps),
			"status": "", "status_ticks": 0, "stagger": 0.0, "clip": "charge", "flagged": false, "name": "charge_vent" })
	attacks.append({ "tick": sim.tick, "clip": "charge", "ticks": scrape, "hexes": all.duplicate(), "line": line.duplicate(), "travelled": travelled })
	charges.append({ "tick": sim.tick, "line": line.duplicate(), "start_hex": u.hex, "run_from": sim.tick + scrape, "trails": trails })
	charge_line = line.duplicate()
	_anim(sim, u, "dirt_scrape", speed)
	busy_until = sim.tick + scrape
	charge_end_at = sim.tick + scrape + line.size() * run + 12
	mode = "charge_run"
	lapped = false


func _charge_run(sim: HHSim, u: Dictionary) -> void:
	if sim.tick < busy_until:
		return                                         # still scraping: the lane is lit
	if anim != "charge":
		u["walk_ticks"] = float(TUNE.run_ticks)
		_anim(sim, u, "charge")
	var end: Vector2i = charge_line[-1]
	var done: bool = (u.hex == end) or sim.tick >= charge_end_at
	if not done and (u.path as Array).is_empty() and int(u.stagger) <= 0:
		# (re)assert the remaining line: a stagger truncates the path, the charge is a commitment
		var rest: Array[Vector2i] = []
		var seen := false
		for h in charge_line:
			if seen:
				rest.append(h)
			elif h == u.hex:
				seen = true
		if not seen:
			rest = sim.arena.path(u.hex, end, sim.blocked_for(u))
		if rest.is_empty():
			done = true
		else:
			u.path = rest
			u.progress = 0.0
	if done:
		u["walk_ticks"] = float(TUNE.walk_ticks)
		_stop(u)
		if not charges.is_empty():
			charges[-1]["ended"] = sim.tick
			charges[-1]["end_hex"] = u.hex
			charges[-1]["walk_after"] = float(u.walk_ticks)
		mode = "idle"
		busy_until = sim.tick + 10                     # the skid
		next_attack_at = busy_until + _gap()
		_anim(sim, u, "aggravated_idle")


# ------------------------------------------------------------------ telegraph plumbing

## Issue a telegraph and its clip on the same tick (H306/H38): the countdown is
## the clip's contact tick x windup_mult clamped into the window; the clip
## slows so its contact lands with the telegraph. Returns the window (ticks).
func _attack(sim: HHSim, u: Dictionary, clip: String, hexes: Array, payload: Dictionary) -> int:
	mode = "attack"
	_stop(u)
	var contact := int(HHColambrosClips.CLIPS[clip].contact_tick)
	var ticks := HHTierBrain.windup(u, clampi(int(round(float(contact) * float(TUNE.windup_mult))), int(TUNE.telegraph_min_ticks), int(TUNE.telegraph_max_ticks)))   # H400: identity on EASY
	var speed := float(contact) / float(ticks) if contact > 0 else 1.0
	payload["clip"] = clip
	payload["name"] = clip
	payload["flagged"] = flagged
	if flagged:
		payload["dmg_pct"] = float(payload.dmg_pct) * float(TUNE.roar_dmg_mult)
		flagged = false
	_telegraph(sim, u, clip, hexes, ticks, payload)
	attacks.append({ "tick": sim.tick, "clip": clip, "ticks": ticks, "hexes": hexes.duplicate(), "line": [], "travelled": travelled })
	_anim(sim, u, clip, speed)
	busy_until = sim.tick + int(ceil(float(_clip_ticks(clip)) / speed))
	next_attack_at = busy_until + _gap()
	lapped = false
	return ticks


func _telegraph(sim: HHSim, u: Dictionary, name: String, hexes: Array, ticks: int, payload: Dictionary) -> void:
	var p := payload.duplicate()
	p["name"] = name
	sim.telegraph(u.id, hexes, ticks, p)


func _gap() -> int:
	return int(ceil(float(TUNE.attack_gap_ticks) * float(HHPhases.rule(phase_state, "gap_mult", 1.0))))


# ------------------------------------------------------------------ movement

## A lap leg (H39 for a roamer): a far spot 8-14 hexes away, preferring a new
## bearing from the player, reached on all fours.
func _lap(sim: HHSim, u: Dictionary, p: Dictionary) -> void:
	var blocked := sim.blocked_for(u)
	var kinds: Array = u.get("allowed_kinds", ALLOWED_KINDS)
	var cur_bearing := HHHex.direction_index(p.hex, u.hex)
	var cands: Array = []
	for r in range(int(TUNE.lap_min), int(TUNE.lap_max) + 1):
		for h in HHHex.ring(u.hex, r):
			if not _fits(sim, u, h, kinds, blocked):
				continue
			if HHHex.distance(h, p.hex) <= int(u.size) + 1:
				continue
			var bearing := HHHex.direction_index(p.hex, h)
			cands.append([h, 1 if bearing != cur_bearing else 0])
	if cands.is_empty():
		_approach(sim, u, p, true)
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var flank: Array = cands.filter(func(c): return int(c[1]) == 1)
	var pool: Array = flank if not flank.is_empty() else cands
	var pick: Vector2i = pool[int(floor(_rng(sim) * pool.size())) % pool.size()][0]
	mode = "lap"
	u["walk_ticks"] = float(TUNE.run_ticks)
	_move(sim, u, pick)
	_anim(sim, u, "run" if not (u.path as Array).is_empty() else _idle_clip(u))


func _approach(sim: HHSim, u: Dictionary, p: Dictionary, fast: bool) -> void:
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
		_anim(sim, u, _idle_clip(u))
		return
	u["walk_ticks"] = float(TUNE.run_ticks) if fast else float(TUNE.walk_ticks)
	_move(sim, u, best)
	lapped = true
	next_attack_at = maxi(next_attack_at, sim.tick + int(TUNE.rethink_ticks))
	_anim(sim, u, ("run" if fast else "walk") if not (u.path as Array).is_empty() else _idle_clip(u))


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


static func _nearest_fit(sim: HHSim, u: Dictionary, at: Vector2i, kinds: Array, blocked: Dictionary, within: int) -> Vector2i:
	for r in range(1, within + 1):
		var ring := HHHex.ring(at, r)
		ring.sort()
		for h in ring:
			if _fits(sim, u, h, kinds, blocked):
				return h
	return Vector2i(-9999, -9999)


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


## The tail arc: hexes beyond the footprint within `half_deg` of the player's
## bearing, excluding the front 60 deg (the tail cannot reach ahead).
func _arc(sim: HHSim, u: Dictionary, at: Vector2i, range_hexes: int, half_deg: float) -> Array:
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
		if v.normalized().dot(dirv) >= cos_h and _bearing_deg(u, h) > 30.0:
			out.append(h)
	out.sort()
	return out


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
	if not u.has("bald_until"):
		u["bald_until"] = 0
	if not u.has("smoulder"):
		u["smoulder"] = false


func _idle_clip(u: Dictionary) -> String:
	return "bald_idle" if is_bald(u) else "aggravated_idle"


## The hunter it goes for: the sim's one aggro rule (H53: nearest standing,
## with a threat bonus for the last hunter that hit it).
func _nearest_player(sim: HHSim, u: Dictionary) -> Dictionary:
	return sim.monster_target(u)


func _edge_dist(u: Dictionary, p: Dictionary) -> int:
	return maxi(0, HHHex.distance(u.hex, p.hex) - int(u.size))


func _clip_ticks(clip: String) -> int:
	return int(ceil(float(HHColambrosClips.CLIPS[clip].duration) / HHSim.TICK))


func _rng(sim: HHSim) -> float:
	rolls += 1
	return sim.rng.randf()


func _anim(sim: HHSim, u: Dictionary, clip: String, speed: float = 1.0) -> void:
	if clip == anim and bool(HHColambrosClips.CLIPS[clip].loop):
		return
	anim = clip
	sim._emit({ "type": "monster_anim", "id": u.id, "clip": clip, "speed": speed })
