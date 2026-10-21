class_name HHTierBrain
extends RefCounted
## Lane M (H360-H389): the NORMAL-and-up layer over every monster brain, the
## author's change spec sections 7 and 8. EASY never enters this file: HHSim
## calls `brain.tick(sim, u)` exactly as before unless `tier_at_least("normal")`
## (H240), and the brains' one hook (`windup`) is the identity while the unit
## has no `tier` key, which only this file writes.
##
## Node-free and seeded from sim.rng (only on NORMAL+). Its state lives on the
## monster's unit as `u.tier` (plain data), so a co-op mirror gets it with the
## unit and the view (HHTierFx) reads it there; the host runs the only copy.
##
##   7.1 Enrage over time: from TUNE.enrage_delay_s after aggravation it ramps
##       over TUNE.enrage_ramp_s: telegraph windows shrink to enrage_windup_min
##       of their length (the brains' `windup` hook; clips speed up to match),
##       damage grows to enrage_dmg_max, painted tiers gain +1 at half and +2
##       at full (capped at 3). The body idles faster and lower, eyes glow, a
##       heat ring grows on the ground (HHTierFx / HHMonsterBody).
##   7.2 Element Pulse: every pulse_every_s the monster overrides its own hull
##       with its own element at pulse_tier (+ the enrage bonus). It is how a
##       monster resists standing in a DOT; the paint is its own, so a hunter
##       can cash it in (Overheat today; EL's 3.3 trigger rule after merge).
##   7.3 dot_pain_meter: ground-tile damage (fire standing / crossing, dark
##       drain) in the last pain_window_s, as pct of the monster's unscaled max
##       HP. Past pain_pct: a Purge at the next safe moment (no telegraph of its
##       own in flight, not in the air / submerged / committed), then a
##       reposition to a clean corner. Purge by element pair (PROFILES):
##       quench (Quench Wave, water 2 over size + 3, contained) or roar
##       (Electric Discharge Roar: every charged hex in size + 3 detonates as
##       one contained action), else flare (own element 1 over size + 3).
##   7.4 Avoidance: sustained FIRE damage under the purge line (>= avoid_frac
##       of it) with fire under its centre: walk off the burning cluster; a
##       water monster pulses early (quench), a thunder monster detonates the
##       burning hexes round its hull (its own thunder).
##   8   Set-pieces, element-agnostic, assigned by element pair in PROFILES:
##       fakeout (8.1, chargers), sweep (8.2, channellers), siphon (8.3),
##       root (8.4, sun-soakers on the arena's authored "sun" cells).
##
## A running mechanic is `u.tier.act` (purge, move, fakeout, sweep, siphon,
## root, stun); while one runs the brain is paused (its tick is skipped) and
## handed back idle afterwards (`_end`: busy_until, next_attack_at, mode, anim).
## Every number is a TUNE key, F1-editable as "tier_<key>".

const TUNE := {
	# 7.1 enrage over time
	"enrage_delay_s": 20.0,         # calm for this long after aggravation ...
	"enrage_ramp_s": 120.0,         # ... then 0 -> 1 over this (full at 2:20 into the fight)
	"enrage_windup_min": 0.7,       # telegraph windows x this at full enrage
	"enrage_dmg_max": 1.3,          # attack damage x this at full enrage
	"enrage_tier_half": 1,          # painted tiers + this from enrage 0.5 ...
	"enrage_tier_full": 2,          # ... and this at 1.0 (capped at 3)
	"windup_floor_ticks": 24,       # never shorter than this (H306's 24-tick floor)
	# 7.2 element pulse
	"pulse_every_s": 8.0,
	"pulse_tier": 2,
	"pulse_tell_ticks": 18,         # the hull glows this long before (view only)
	# 7.3 dot_pain_meter and purge
	"pain_window_s": 4.0,
	"pain_pct": 3.0,                # pct of unscaled max HP from ground tiles within the window
	"purge_cd_s": 12.0,
	"purge_windup_ticks": 30,       # the slam / roar tell (1 s)
	"purge_radius": 3,              # hexes beyond the hull
	"quench_steps": 2,              # water 2
	"quench_dmg_pct": 6.0,          # the wave's own hit on hunters (pct max HP)
	"quench_stagger": 0.4,
	"roar_player_mult": 0.5,        # DECIDE-C until EL's 3.3: x reaction_unit_other x blast mult, never below 1 HP
	"reposition_min": 8,            # the clean corner is at least this far
	"reposition_s": 6.0,            # give up the move after this long
	"slide_ticks": 5.0,             # ticks per hex: a slide / swim / lap leg
	"leap_ticks": 24,               # a reposition leap's air time
	# 7.4 avoidance
	"avoid_frac": 0.34,             # of pain_pct, fire only
	"avoid_cd_s": 5.0,
	"avoid_s": 3.0,
	# 8 set-pieces
	"sp_first_s": 15.0,             # first set-piece this long after aggravation
	"sp_every_s": 25.0,             # then one every this ...
	"sp_jitter_s": 6.0,             # ... + up to this
	"sp_retry_s": 2.0,
	# 8.1 triple-corridor fakeout
	"fk_rear_ticks": 30,            # beat 1: rears, three yellow corridors
	"fk_chevron_ticks": 45,         # beat 2: chevrons + the body tell
	"fk_vanish_ticks": 18,          # beat 3: 0.6 s, decoys gone, the true lane red
	"fk_len": 12,                   # lane length beyond the hull
	"fk_min_len": 6,
	"fk_fan_deg": 38.0,             # side lanes this far off the centre lane
	"fk_dmg_pct": 24.0,
	"fk_stagger": 0.9,
	"fk_trail_tier": 3,
	"fk_min_dist": 4,               # hunter at least this far (edge) for a fakeout
	# 8.2 rotating sweep / safe wedge
	"sw_walk_s": 8.0,               # walk to the centre for at most this
	"sw_windup_ticks": 45,
	"sw_deg_per_tick": 3.0,         # 90 deg/s, clockwise from above
	"sw_turns": 2.0,
	"sw_reach": 9,                  # beam length beyond the hull
	"sw_lead_ticks": 12,            # each slice is telegraphed this long before the beam reaches it
	"sw_slice_ticks": 3,
	"sw_dmg_pct": 12.0,
	"sw_stagger": 0.3,
	"sw_tier": 3,
	"sw_block_hits": 2,             # [FILL] passes a breakable block survives: it breaks on the 2nd
	# 8.3 siphon
	"si_min_points": 6,             # a cluster worth stalking: this many tier points
	"si_stalk_s": 10.0,
	"si_heal_pct_per_point": 0.5,
	"si_heal_max_pct": 8.0,         # one siphon heals at most this (pct max HP)
	"si_buff_per_point": 0.03,
	"si_buff_max": 1.3,
	"si_buff_s": 20.0,
	"si_reach": 1,                  # drinks hull + this
	# 8.4 rooting
	"rt_hp_below": 0.85,
	"rt_min_sun": 4,                # sun hexes under the hull to root
	"rt_walk_s": 8.0,
	"rt_ticks": 180,                # rooted up to 6 s
	"rt_heal_pct_s": 1.5,
	"rt_stun_s": 4.0,               # [FILL] corrupted root: stunned (and exposed) this long
}

## Set-piece and purge assignment by element pair (spec 8: "assign each
## set-piece to the current roster by element pair"). H362, H363.
const PROFILES := {
	"swampfang": { "elements": ["water", "dark"], "pulse": "water", "purge": "quench", "move": "dive",
		"setpieces": ["siphon"], "siphon": "water",
		"clips": { "roar": "frill_roar", "slam": "thrash_splash", "walk": "walk", "dive": "dive", "swim": "swim", "react": "hit_react", "stun": "stagger" } },
	"colambros": { "elements": ["fire"], "pulse": "fire", "purge": "roar", "move": "run",
		"setpieces": ["fakeout", "siphon"], "siphon": "fire", "run_ticks": 3.0,
		"clips": { "roar": "rattle_roar", "slam": "tail_lash", "walk": "walk", "run": "run", "charge": "charge", "scrape": "dirt_scrape", "react": "hit_react", "stun": "stagger" } },
	"rimeslithe": { "elements": ["ice", "light"], "pulse": "ice", "purge": "quench", "move": "slide",
		"setpieces": ["fakeout", "sweep"], "run_ticks": 4.0,
		"clips": { "roar": "roar", "slam": "cold_slam", "walk": "walk", "run": "walk", "charge": "walk", "channel": "frost_beam", "react": "hit_react", "stun": "stagger" } },
	"spirewalker": { "elements": ["thunder", "dark"], "pulse": "thunder", "purge": "roar", "move": "leap",
		"setpieces": ["sweep", "root"], "sweep": "dark",
		"clips": { "roar": "pollen_shake", "slam": "tail_drag", "walk": "walk", "leap": "leaping_squash", "channel": "spore_spread", "root": "calm_soak", "react": "hit_react", "stun": "stagger" } },
}
const GROUND_CAUSES := ["fire", "fire_cross", "dark"]
const FIRE_CAUSES := ["fire", "fire_cross"]
const COMMITTED := ["charge_run", "leap", "squash", "dive", "swim", "surface", "charge", "bite_back", "dead"]
const NO_HEX := Vector2i(-9999, -9999)

static var _registered := false
static var entered := 0               ## director calls (tests: EASY never enters)


static func t(key: String) -> float:
	if not _registered:
		_registered = true
		HHTune.register("tier", TUNE)
	return HHTune.value("tier_" + key)


static func ti(key: String) -> int:
	return int(round(t(key)))


static func secs(key: String) -> int:
	return int(round(t(key) * 30.0))


# ------------------------------------------------------------------ hooks for the brains

## The brains' one hook (7.1): a telegraph window after enrage. The identity
## when the unit carries no `tier` (always on EASY).
static func windup(u: Dictionary, ticks: int) -> int:
	var tr: Variant = u.get("tier")
	if not (tr is Dictionary):
		return ticks
	var s := float((tr as Dictionary).get("windup", 1.0))
	if s >= 0.999:
		return ticks
	return maxi(mini(ticks, ti("windup_floor_ticks")), int(round(float(ticks) * s)))


## What kind of monster a brain drives (its `id`, else the unit's).
static func kind_of(brain: Object, u: Dictionary) -> String:
	var v: Variant = brain.get("id") if brain != null else null
	var k := str(v) if v != null else ""
	if PROFILES.has(k):
		return k
	return str(u.get("id", ""))


static func profile(kind: String) -> Dictionary:
	return PROFILES.get(kind, { "elements": [], "pulse": "", "purge": "flare", "move": "walk", "setpieces": [], "clips": {} })


# ------------------------------------------------------------------ the tick (HHSim.step calls this on NORMAL+)

static func tick(sim: HHSim, brain: Object, u: Dictionary) -> void:
	if not sim.tier_at_least("normal"):
		brain.tick(sim, u)                               # EASY: exactly as before
		return
	entered += 1
	var prev := _prev_events(sim)
	if not sim.alive(u):
		brain.tick(sim, u)
		return
	var T := _state(sim, brain, u)
	_pain(sim, u, T, prev)
	_aggro(sim, brain, u, T)
	_enrage(sim, u, T)
	if int(T.buff_until) >= 0 and sim.tick >= int(T.buff_until):
		T.buff = 1.0
		T.buff_until = -1
	if int(T.aggro_at) >= 0:
		_pulse(sim, brain, u, T, false)
	if not (T.act as Dictionary).is_empty():
		_run(sim, brain, u, T)
		return
	if int(T.aggro_at) >= 0:
		var thr := t("pain_pct")
		if float(T.meter) >= thr and sim.tick >= int(T.purge_cd):
			if _free(sim, brain, u, false):
				_start_purge(sim, brain, u, T)
				return
			if _glide_hold(u):
				return
		elif float(T.fire_meter) >= thr * t("avoid_frac") and sim.tick >= int(T.avoid_cd) and _burning_under(sim, u) and _free(sim, brain, u, false):
			_start_avoid(sim, brain, u, T)
			return
		if int(T.sp_next) >= 0 and sim.tick >= int(T.sp_next) and _free(sim, brain, u, true):
			if _start_setpiece(sim, brain, u, T):
				return
			T.sp_next = sim.tick + secs("sp_retry_s")
	var first := sim._next_tg
	brain.tick(sim, u)
	_scale_new(sim, u, T, first)


## The unit's tier state (created on the first NORMAL tick).
static func _state(sim: HHSim, brain: Object, u: Dictionary) -> Dictionary:
	if u.get("tier") is Dictionary:
		return u.tier
	var k := kind_of(brain, u)
	u["tier"] = {
		"kind": k, "enrage": 0.0, "windup": 1.0, "dmg": 1.0, "bonus": 0, "aggro_at": -1,
		"pulse_at": -1, "pulses": 0, "pain": [], "meter": 0.0, "fire_meter": 0.0,
		"purge_cd": 0, "avoid_cd": 0, "purges": 0, "act": {}, "sp_next": -1, "sp_used": {},
		"buff": 1.0, "buff_until": -1, "fx": {}, "log": [],
	}
	return u.tier


## The previous tick's events (HHSim resets `events` to a new array every
## step; the array we saw last tick has since been filled to the end).
static func _prev_events(sim: HHSim) -> Array:
	var m: Dictionary = sim.get_meta("hh_tier_ev", {})
	if int(m.get("tick", -1)) != sim.tick:
		var prev: Array = m.get("cur", []) if int(m.get("tick", -1)) == sim.tick - 1 else []
		m = { "tick": sim.tick, "cur": sim.events, "prev": prev }
		sim.set_meta("hh_tier_ev", m)
	return m.prev


static func _bget(brain: Object, key: String, def: Variant) -> Variant:
	if brain == null:
		return def
	var v: Variant = brain.get(key)
	return def if v == null else v


static func _bset(brain: Object, key: String, v: Variant) -> void:
	if brain != null and key in brain:
		brain.set(key, v)


static func _log(sim: HHSim, u: Dictionary, T: Dictionary, what: String, extra: Dictionary = {}) -> void:
	var e := { "type": "tier", "id": u.id, "what": what }
	e.merge(extra)
	sim._emit(e)
	var lg: Array = T.log
	lg.append([sim.tick, what])
	if lg.size() > 24:
		lg.pop_front()


# ------------------------------------------------------------------ 7.1 enrage

static func _aggro(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	if int(T.aggro_at) >= 0:
		return
	if str(_bget(brain, "state", "calm")) == "calm":
		return
	T.aggro_at = sim.tick
	T.pulse_at = sim.tick + secs("pulse_every_s")
	T.sp_next = sim.tick + secs("sp_first_s")


static func enrage_at(ticks_since_aggro: int) -> float:
	var x := (float(ticks_since_aggro) / 30.0 - t("enrage_delay_s")) / maxf(1.0, t("enrage_ramp_s"))
	return clampf(x, 0.0, 1.0)


static func _enrage(sim: HHSim, u: Dictionary, T: Dictionary) -> void:
	if int(T.aggro_at) < 0:
		return
	var e := enrage_at(sim.tick - int(T.aggro_at))
	T.enrage = e
	T.windup = lerpf(1.0, t("enrage_windup_min"), e)
	T.dmg = lerpf(1.0, t("enrage_dmg_max"), e)
	var b := ti("enrage_tier_full") if e >= 1.0 else (ti("enrage_tier_half") if e >= 0.5 else 0)
	if b != int(T.bonus):
		T.bonus = b
		_log(sim, u, T, "enrage", { "enrage": e, "bonus": b })


## Damage and tier on the telegraphs the brain issued this tick.
static func _scale_new(sim: HHSim, u: Dictionary, T: Dictionary, first: int) -> void:
	var mult := float(T.dmg) * float(T.buff)
	var bonus := int(T.bonus)
	if mult == 1.0 and bonus == 0:
		return
	for tg in sim.telegraphs:
		if int(tg.id) < first or str(tg.owner) != str(u.id):
			continue
		var p: Dictionary = tg.payload
		if float(p.get("dmg_pct", 0.0)) > 0.0:
			p.dmg_pct = float(p.dmg_pct) * mult
		if bonus > 0 and str(p.get("element", "")) != "" and int(p.get("paint_steps", 0)) > 0:
			p.paint_steps = mini(HHCharge.AXIS_MAX, int(p.paint_steps) + bonus)
		p["tier_scaled"] = true


# ------------------------------------------------------------------ 7.2 element pulse

static func _pulse(sim: HHSim, _brain: Object, u: Dictionary, T: Dictionary, early: bool) -> bool:
	var el := str(profile(str(T.kind)).get("pulse", ""))
	if el == "":
		return false
	if not early and sim.tick < int(T.pulse_at):
		return false
	if not (u.leap as Dictionary).is_empty() or bool(u.get("untargetable", false)):
		return false
	var tier := mini(HHCharge.AXIS_MAX, ti("pulse_tier") + int(T.bonus))
	var hull: Array = sim.footprint(u)
	var changed := HHElementBridge.paint_own(sim, u, hull, el, tier)
	T.pulse_at = sim.tick + secs("pulse_every_s")
	T.pulses = int(T.pulses) + 1
	T.fx["pulse"] = sim.tick
	T.fx["pulse_el"] = el
	_log(sim, u, T, "pulse", { "element": el, "tier": tier, "hexes": changed.size(), "early": early })
	return true


# ------------------------------------------------------------------ 7.3 dot_pain_meter

static func _pain(sim: HHSim, u: Dictionary, T: Dictionary, prev: Array) -> void:
	var list: Array = T.pain
	for e in prev:
		if str(e.get("type", "")) == "hurt" and str(e.get("id", "")) == str(u.id) and str(e.get("cause", "")) in GROUND_CAUSES:
			list.append([int(e.get("tick", sim.tick - 1)), float(e.get("amount", 0.0)), 1 if str(e.cause) in FIRE_CAUSES else 0])
	var win := secs("pain_window_s")
	while not list.is_empty() and sim.tick - int(list[0][0]) > win:
		list.pop_front()
	var total := 0.0
	var fire := 0.0
	for x in list:
		total += float(x[1])
		if int(x[2]) == 1:
			fire += float(x[1])
	var base := unscaled_hp(u)
	T.meter = 100.0 * total / base
	T.fire_meter = 100.0 * fire / base


## Max HP without the party scaling (H54: party HP never feeds ground damage).
static func unscaled_hp(u: Dictionary) -> float:
	return maxf(1.0, float(u.max_hp) / maxf(1.0, float(u.get("party_scale", 1.0))))


# ------------------------------------------------------------------ readiness

## Not mid-attack: nothing of its own in flight, grounded, surfaced, not
## committed. `strict` also waits out the brain's recovery (set-pieces).
static func _free(sim: HHSim, brain: Object, u: Dictionary, strict: bool) -> bool:
	if not (u.leap as Dictionary).is_empty() or not (u.windup as Dictionary).is_empty():
		return false
	if bool(u.get("untargetable", false)) or int(u.stagger) > 0 or sim._paralysed(u):
		return false
	if str(_bget(brain, "state", "calm")) == "calm":
		return false
	if str(_bget(brain, "mode", "idle")) in COMMITTED:
		return false
	for k in ["pollen", "squash", "pending"]:
		var v: Variant = _bget(brain, k, null)
		if (v is Dictionary and not (v as Dictionary).is_empty()) or (v is Array and not (v as Array).is_empty()):
			return false
	for tg in sim.telegraphs:
		if str(tg.owner) == str(u.id):
			return false
	if strict and sim.tick < int(_bget(brain, "busy_until", 0)):
		return false
	if float(u.progress) > 0.0 and not (u.path as Array).is_empty():
		return false
	return true


## Mid-glide when a purge is due: finish this hex and stop (skip the brain).
static func _glide_hold(u: Dictionary) -> bool:
	if float(u.progress) > 0.0 and (u.path as Array).size() > 0 and (u.leap as Dictionary).is_empty() and (u.windup as Dictionary).is_empty():
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		u.path = np
		return true
	return false


static func _begin(sim: HHSim, u: Dictionary, T: Dictionary, act: Dictionary) -> void:
	act["walk"] = float(u.get("walk_ticks", HHTune.value("monster_walk_ticks")))
	act["t0"] = sim.tick
	u.path = [] as Array[Vector2i]
	T.act = act
	T.anim = ""


## Hand the monster back to its brain, idle.
static func _end(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	u["walk_ticks"] = float(act.get("walk", u.get("walk_ticks", HHTune.value("monster_walk_ticks"))))
	if bool(act.get("hid", false)):
		u.untargetable = false
	if float(u.progress) > 0.0 and not (u.path as Array).is_empty():
		var first: Vector2i = u.path[0]
		var np: Array[Vector2i] = [first]
		u.path = np
	else:
		u.path = [] as Array[Vector2i]
	_log(sim, u, T, "end", { "act": str(act.get("kind", "")) })
	T.act = {}
	var gap := 30
	if brain != null and brain.has_method("_gap"):
		gap = int(brain.call("_gap"))
	_bset(brain, "busy_until", sim.tick + 6)
	_bset(brain, "next_attack_at", sim.tick + 6 + gap)
	_bset(brain, "mode", "idle")
	_bset(brain, "anim", "")
	_bset(brain, "goal", NO_HEX)
	_anim(sim, u, T, "aggravated_idle", 1.0, true)


static func _anim(sim: HHSim, u: Dictionary, T: Dictionary, clip: String, speed: float = 1.0, force: bool = false) -> void:
	if clip == "":
		return
	if not force and str(T.get("anim", "")) == clip:
		return
	T.anim = clip
	sim._emit({ "type": "monster_anim", "id": u.id, "clip": clip, "speed": speed })


static func _clip(T: Dictionary, role: String) -> String:
	return str((profile(str(T.kind)).get("clips", {}) as Dictionary).get(role, ""))


static func _fits(sim: HHSim, u: Dictionary, h: Vector2i, blocked: Dictionary) -> bool:
	var kinds: Array = u.get("allowed_kinds", [])
	for c in HHHex.area(h, int(u.size)):
		if not sim.arena.walkable(c) or blocked.has(c):
			return false
		if not kinds.is_empty() and not str(sim.arena.kind(c)) in kinds:
			return false
	return true


static func _nearest_fit(sim: HHSim, u: Dictionary, at: Vector2i, within: int) -> Vector2i:
	var blocked := sim.blocked_for(u)
	if _fits(sim, u, at, blocked):
		return at
	for r in range(1, within + 1):
		var ring := HHHex.ring(at, r)
		ring.sort()
		for h in ring:
			if _fits(sim, u, h, blocked):
				return h
	return NO_HEX


static func centre_hex(sim: HHSim) -> Vector2i:
	return sim.arena.from_world(Vector3.ZERO)


static func _target(sim: HHSim, u: Dictionary) -> Dictionary:
	return sim.monster_target(u)


static func _edge(u: Dictionary, p: Dictionary) -> int:
	return maxi(0, HHHex.distance(u.hex, p.hex) - int(u.size))


static func _angle(a: Vector2i, b: Vector2i) -> float:
	var v := HHHex.to_world(b, 1.0) - HHHex.to_world(a, 1.0)
	return atan2(v.x, v.y)


# ------------------------------------------------------------------ running mechanics

static func _run(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	match str(act.kind):
		"purge": _run_purge(sim, brain, u, T)
		"move": _run_move(sim, brain, u, T)
		"fakeout": _run_fakeout(sim, brain, u, T)
		"sweep": _run_sweep(sim, brain, u, T)
		"siphon": _run_siphon(sim, brain, u, T)
		"root": _run_root(sim, brain, u, T)
		_: _end(sim, brain, u, T)


# ---- 7.3 purge

static func purge_hexes(sim: HHSim, u: Dictionary) -> Array:
	var out: Array = []
	for h in HHHex.area(u.hex, int(u.size) + ti("purge_radius")):
		if sim.arena.exists(h):
			out.append(h)
	out.sort()
	return out


static func _start_purge(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var prof := profile(str(T.kind))
	var kind := str(prof.get("purge", "flare"))
	var hexes := purge_hexes(sim, u)
	var w := ti("purge_windup_ticks")
	_begin(sim, u, T, { "kind": "purge", "purge": kind, "at": sim.tick + w, "hexes": hexes })
	var outside: Array = hexes.filter(func(h): return not sim.in_hull(u, h))
	match kind:
		"quench":
			sim.telegraph(u.id, outside, w, { "dmg_pct": t("quench_dmg_pct") * float(T.dmg), "element": "water", "paint_steps": 0,
				"stagger": t("quench_stagger"), "name": "tier_quench_wave", "clip": _clip(T, "slam") })
			_anim(sim, u, T, _clip(T, "slam"), 1.0, true)
		"roar":
			var charged: Array = hexes.filter(func(h): return sim.charge.charged(h))
			if not charged.is_empty():
				sim.telegraph(u.id, charged, w, { "dmg_pct": 0.0, "element": "thunder", "paint_steps": 0, "name": "tier_discharge_roar", "clip": _clip(T, "roar") })
			_anim(sim, u, T, _clip(T, "roar"), 1.0, true)
		_:
			var el := str(prof.get("pulse", ""))
			sim.telegraph(u.id, outside, w, { "dmg_pct": 0.0, "element": el, "paint_steps": 0, "name": "tier_flare" })
			_anim(sim, u, T, _clip(T, "roar"), 1.0, true)
	var meter_at := float(T.meter)
	T.pain = []
	T.meter = 0.0
	T.fire_meter = 0.0
	T.purge_cd = sim.tick + secs("purge_cd_s")
	T.purges = int(T.purges) + 1
	T.fx["purge"] = sim.tick
	T.fx["purge_at"] = sim.tick + w
	T.fx["purge_kind"] = kind
	_log(sim, u, T, "purge", { "purge": kind, "at": sim.tick + w, "meter": meter_at })


static func _run_purge(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	if sim.tick < int(act.at):
		return
	var prof := profile(str(T.kind))
	var res := {}
	match str(act.purge):
		"quench":
			var r := HHElementBridge.quench(sim, u, act.hexes, ti("quench_steps"))
			res = { "doused": (r.doused as Array).size(), "changed": (r.changed as Array).size() }
		"roar":
			var r2 := HHElementBridge.discharge(sim, u, act.hexes)
			res = { "detonated": (r2.detonated as Array).size(), "players": r2.players, "monster": r2.monster }
		_:
			var el := str(prof.get("pulse", ""))
			res = { "changed": HHElementBridge.paint_own(sim, u, act.hexes, el, 1).size() }
	T.fx["purge_done"] = sim.tick
	_log(sim, u, T, "purge_done", res)
	_start_move(sim, brain, u, T, str(prof.get("move", "walk")), _clean_spot(sim, u, ti("reposition_min"), str(prof.get("move", "")) == "dive"), secs("reposition_s"), "reposition")


## The cleanest far spot the hull fits on (spec: "a clean corner"): least
## charge round it, away from hunters, toward the edge.
static func _clean_spot(sim: HHSim, u: Dictionary, min_d: int, prefer_water: bool) -> Vector2i:
	var blocked := sim.blocked_for(u)
	var c := centre_hex(sim)
	var players := sim.standing_players()
	var best := NO_HEX
	var best_s := INF
	var keys: Array = sim.arena.cells.keys()
	keys.sort()
	for h in keys:
		var d := HHHex.distance(h, u.hex)
		if d < min_d or not _fits(sim, u, h, blocked):
			continue
		var dirt := 0
		for n in HHHex.area(h, int(u.size) + 1):
			if sim.charge.charged(n):
				dirt += 1
		var near := 99
		for p in players:
			near = mini(near, HHHex.distance(h, p.hex) - int(u.size))
		var s := float(dirt) * 10.0 + (40.0 if near < 4 else 0.0) - float(HHHex.distance(h, c)) + 0.4 * float(d)
		if prefer_water and not str(sim.arena.kind(h)) in ["water", "deep"]:
			s += 20.0
		if s < best_s:
			best_s = s
			best = h
	return best


# ---- moves (reposition after a purge, 7.4 avoidance)

static func _start_move(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary, style: String, goal: Vector2i, limit: int, why: String) -> void:
	var walk := float((T.act as Dictionary).get("walk", u.get("walk_ticks", HHTune.value("monster_walk_ticks"))))
	T.act = { "kind": "move", "style": style, "goal": goal, "until": sim.tick + limit, "why": why, "walk": walk, "t0": sim.tick, "started": false }
	if goal == NO_HEX or goal == u.hex:
		_end(sim, brain, u, T)
		return
	_log(sim, u, T, "move", { "style": style, "goal": goal, "why": why })


static func _run_move(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	var goal: Vector2i = act.goal
	var style := str(act.style)
	if not bool(act.started):
		act.started = true
		match style:
			"leap":
				_anim(sim, u, T, _clip(T, "leap"), 1.0, true)
				sim.begin_leap(u, goal, ti("leap_ticks"), Callable())
				var sp_el := str(profile(str(T.kind)).get("pulse", ""))
				if sp_el != "" and not (u.leap as Dictionary).is_empty():
					u.leap["splash"] = sp_el                    # H269: every leap lands with the contained splash (dev's path, no own damage)
				return
			"dive":
				u.untargetable = true
				act["hid"] = true
				u["walk_ticks"] = t("slide_ticks")
				_anim(sim, u, T, _clip(T, "dive"), 1.0, true)
			"run", "slide":
				u["walk_ticks"] = t("slide_ticks")
				_anim(sim, u, T, _clip(T, "run") if style == "run" else _clip(T, "walk"), 1.0 if style == "run" else 1.8, true)
			_:
				_anim(sim, u, T, _clip(T, "walk"), 1.0, true)
		sim.monster_move(u, goal)
		return
	if style == "leap":
		if (u.leap as Dictionary).is_empty():
			_end(sim, brain, u, T)
		return
	if style == "dive" and sim.tick - int(act.t0) == 27:
		_anim(sim, u, T, _clip(T, "swim"))
	var arrived: bool = u.hex == goal and float(u.progress) == 0.0
	if arrived or sim.tick >= int(act.until):
		_end(sim, brain, u, T)
		return
	if (u.path as Array).is_empty() and int(u.stagger) <= 0 and (sim.tick - int(act.t0)) % 10 == 0:
		if not sim.monster_move(u, goal):
			_end(sim, brain, u, T)


# ---- 7.4 avoidance

static func _burning_under(sim: HHSim, u: Dictionary) -> bool:
	return sim.charge.intensity(u.hex, "fire") > 0 and HHElementBridge.foreign(sim, u.hex, u)


static func _start_avoid(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var prof := profile(str(T.kind))
	var els: Array = prof.get("elements", [])
	T.avoid_cd = sim.tick + secs("avoid_cd_s")
	var used := ""
	if "water" in els:
		used = "water"
		_pulse(sim, brain, u, T, true)                  # its own water quenches what is under it
	elif "thunder" in els:
		used = "thunder"
		var burning: Array = []
		for h in HHHex.area(u.hex, int(u.size) + 1):
			if sim.charge.intensity(h, "fire") > 0 and HHElementBridge.foreign(sim, h, u):
				burning.append(h)
		HHElementBridge.discharge(sim, u, burning)      # its own thunder cashes the cluster out
		T.fx["discharge"] = sim.tick
	var goal := _escape_spot(sim, u)
	_begin(sim, u, T, { "kind": "move" })
	_log(sim, u, T, "avoid", { "used": used, "goal": goal })
	_start_move(sim, brain, u, T, "walk", goal, secs("avoid_s"), "avoid")


## The nearest spot within 6 whose hull is the least on fire (centre clear).
static func _escape_spot(sim: HHSim, u: Dictionary) -> Vector2i:
	var blocked := sim.blocked_for(u)
	var best := NO_HEX
	var best_s := INF
	for r in range(2, 7):
		var ring := HHHex.ring(u.hex, r)
		ring.sort()
		for h in ring:
			if not _fits(sim, u, h, blocked):
				continue
			if sim.charge.intensity(h, "fire") > 0 and HHElementBridge.foreign(sim, h, u):
				continue
			var burn := 0
			for n in HHHex.area(h, int(u.size)):
				if sim.charge.intensity(n, "fire") > 0 and HHElementBridge.foreign(sim, n, u):
					burn += 1
			var s := float(burn) * 4.0 + float(r)
			if s < best_s:
				best_s = s
				best = h
	return best


# ------------------------------------------------------------------ 8 set-pieces

static func _start_setpiece(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> bool:
	var prof := profile(str(T.kind))
	var list: Array = (prof.get("setpieces", []) as Array).duplicate()
	if list.is_empty():
		T.sp_next = -1
		return false
	var used: Dictionary = T.sp_used
	list.sort_custom(func(a, b): return int(used.get(a, 0)) < int(used.get(b, 0)) or (int(used.get(a, 0)) == int(used.get(b, 0)) and str(a) < str(b)))
	# least used first; among equals a seeded pick
	var low := int(used.get(list[0], 0))
	var ties: Array = list.filter(func(x): return int(used.get(x, 0)) == low)
	if ties.size() > 1:
		var k := int(floor(sim.rng.randf() * ties.size())) % ties.size()
		var pick: String = ties[k]
		list.erase(pick)
		list.push_front(pick)
	for sp in list:
		var ok := false
		match str(sp):
			"fakeout": ok = _start_fakeout(sim, brain, u, T)
			"sweep": ok = _start_sweep(sim, brain, u, T)
			"siphon": ok = _start_siphon(sim, brain, u, T)
			"root": ok = _start_root(sim, brain, u, T)
		if ok:
			used[sp] = int(used.get(sp, 0)) + 1
			T.sp_next = sim.tick + secs("sp_every_s") + int(floor(sim.rng.randf() * float(secs("sp_jitter_s"))))
			_log(sim, u, T, "setpiece", { "setpiece": sp })
			return true
	return false


# ---- 8.1 triple-corridor fakeout

## Three lanes fanning from the monster toward `toward`: centre, left, right.
## Each: { line: [hex] (the run, hull fits all along), lane: [hex] (3 wide) }.
static func fakeout_lanes(sim: HHSim, u: Dictionary, toward: Vector2i) -> Array:
	var blocked := sim.blocked_for(u)
	var a := _angle(u.hex, toward)
	var c: Vector2 = HHHex.to_world(u.hex, 1.0)
	var fan := deg_to_rad(t("fk_fan_deg"))
	var span := float(int(u.size) + ti("fk_len"))
	var hull := {}
	for h in sim.footprint(u):
		hull[h] = true
	var out: Array = []
	for k in [-1, 0, 1]:
		var ang := a + fan * float(k)
		var end := HHHex.from_world(c + Vector2(sin(ang), cos(ang)) * span, 1.0)
		var line: Array = []                      # where the hull can run
		var reach: Array = []                     # where a hunter can stand (a decoy's drawn length)
		var prev: Vector2i = u.hex
		var running := true
		for h in HHHex.line(u.hex, end):
			if h == u.hex:
				continue
			if not sim.arena.walkable(h):
				break
			reach.append(h)
			if running and (not _fits(sim, u, h, blocked) or absf(sim.arena.hex_height(h) - sim.arena.hex_height(prev)) > HHTune.value("max_step_m")):
				running = false
			if running:
				line.append(h)
				prev = h
		var seen := {}
		var lane: Array = []
		var drawn: Array = line if line.size() >= ti("fk_min_len") else reach
		for h in drawn:
			for n in HHHex.area(h, 1):
				if sim.arena.exists(n) and not hull.has(n) and not seen.has(n):
					seen[n] = true
					lane.append(n)
		lane.sort()
		out.append({ "side": k, "line": line, "reach": reach, "lane": lane })
	return out


static func _start_fakeout(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> bool:
	var p := _target(sim, u)
	if p.is_empty() or _edge(u, p) < ti("fk_min_dist"):
		return false
	var lanes := fakeout_lanes(sim, u, p.hex)
	var ok: Array = []
	for i in lanes.size():
		if (lanes[i].line as Array).size() >= ti("fk_min_len"):
			ok.append(i)
	if ok.is_empty():
		return false
	var truth: int = ok[int(floor(sim.rng.randf() * ok.size())) % ok.size()]
	var variant := "single" if sim.rng.randf() < 0.5 else "decoys"
	_begin(sim, u, T, { "kind": "fakeout", "phase": "rear", "lanes": lanes, "truth": truth, "variant": variant,
		"tell": int(lanes[truth].side), "el": str(profile(str(T.kind)).get("pulse", "")), "painted": [], "run_ticks": float(profile(str(T.kind)).get("run_ticks", 4.0)) })
	var act: Dictionary = T.act
	act["chev_at"] = sim.tick + ti("fk_rear_ticks")
	act["vanish_at"] = int(act.chev_at) + ti("fk_chevron_ticks")
	act["run_at"] = int(act.vanish_at) + ti("fk_vanish_ticks")
	u.facing = _angle(u.hex, p.hex)
	_anim(sim, u, T, _clip(T, "roar"), 1.0, true)
	return true


static func _run_fakeout(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	var lane: Dictionary = act.lanes[int(act.truth)]
	var line: Array = lane.line
	match str(act.phase):
		"rear":
			if sim.tick >= int(act.chev_at):
				act.phase = "chevrons"
				_anim(sim, u, T, _clip(T, "scrape") if _clip(T, "scrape") != "" else "aggravated_idle", 0.6, true)
		"chevrons":
			if sim.tick >= int(act.vanish_at):
				act.phase = "vanish"
				# the true lane goes red: segment i lands as the body reaches line hex i
				var run := int(round(float(act.run_ticks)))
				var owner := {}
				var segs: Array = []
				for i in line.size():
					segs.append([])
				for i in line.size():
					var h: Vector2i = line[i]
					if not owner.has(h) and not sim.in_hull(u, h):
						owner[h] = i
						segs[i].append(h)
				for i in line.size():
					for n in HHHex.area(line[i], 1):
						if sim.arena.exists(n) and not owner.has(n) and not sim.in_hull(u, n):
							owner[n] = i
							segs[i].append(n)
				for i in line.size():
					var hs: Array = segs[i]
					if hs.is_empty():
						continue
					hs.sort()
					sim.telegraph(u.id, hs, ti("fk_vanish_ticks") + (i + 1) * run, { "dmg_pct": t("fk_dmg_pct") * float(T.dmg) * float(T.buff),
						"element": "", "paint_steps": 0, "stagger": t("fk_stagger"), "name": "tier_fakeout_run", "clip": _clip(T, "charge") })
				u.facing = _angle(u.hex, line[-1])
				act["end_at"] = int(act.run_at) + line.size() * run + 20
		"vanish":
			if sim.tick >= int(act.run_at):
				act.phase = "run"
				u["walk_ticks"] = float(act.run_ticks)
				var p: Array[Vector2i] = []
				for h in line:
					p.append(h)
				u.path = p
				u.progress = 0.0
				_anim(sim, u, T, _clip(T, "charge"), 2.4 if str(T.kind) == "rimeslithe" else 1.0, true)
		"run":
			var painted: Array = act.painted
			if u.hex in line and not u.hex in painted:
				painted.append(u.hex)
				HHElementBridge.paint_own(sim, u, [u.hex], str(act.el), ti("fk_trail_tier"))
			var done: bool = (u.hex == line[-1] and float(u.progress) == 0.0) or sim.tick >= int(act.end_at)
			if not done and (u.path as Array).is_empty() and int(u.stagger) <= 0:
				var rest: Array[Vector2i] = []
				var seen := false
				for h in line:
					if seen:
						rest.append(h)
					elif h == u.hex:
						seen = true
				if rest.is_empty():
					done = true
				else:
					u.path = rest
					u.progress = 0.0
			if done:
				_end(sim, brain, u, T)


# ---- 8.2 rotating sweep / safe wedge

static func _start_sweep(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> bool:
	var goal := _nearest_fit(sim, u, centre_hex(sim), 4)
	if goal == NO_HEX:
		goal = u.hex
	var el := str(profile(str(T.kind)).get("sweep", profile(str(T.kind)).get("pulse", "")))
	_begin(sim, u, T, { "kind": "sweep", "phase": "walk", "goal": goal, "until": sim.tick + secs("sw_walk_s"), "el": el,
		"paints": [], "safe": [], "hits": {}, "broken": [], "issued": 0, "a0": 0.0, "start": -1 })
	if goal != u.hex:
		sim.monster_move(u, goal)
		_anim(sim, u, T, _clip(T, "walk"), 1.0, true)
	return true


## The rotation in ticks (sw_turns full turns).
static func sweep_total() -> int:
	return int(round(360.0 * t("sw_turns") / maxf(0.1, t("sw_deg_per_tick"))))


## The beam's angle (atan2(x, z), radians) `r` ticks into the rotation:
## clockwise seen from above is a falling angle.
static func sweep_angle(act: Dictionary, r: float) -> float:
	return float(act.a0) - deg_to_rad(t("sw_deg_per_tick")) * r


## The hexes of one slice (rotation ticks [r0, r1)), split into hit and
## shadowed (behind a block). Each hex beyond the hull and within reach lies in
## exactly one slice per turn.
static func sweep_slice(sim: HHSim, u: Dictionary, act: Dictionary, r0: int, r1: int) -> Dictionary:
	var hit: Array = []
	var shadow: Array = []
	var blocks: Array = []
	var start := sweep_angle(act, float(r0))
	var span := deg_to_rad(t("sw_deg_per_tick")) * float(r1 - r0)
	var reach := int(u.size) + ti("sw_reach")
	var broken: Array = act.get("broken", [])
	for h in HHHex.area(u.hex, reach):
		if not sim.arena.exists(h) or HHHex.distance(u.hex, h) <= int(u.size):
			continue
		var turned := fposmod(start - _angle(u.hex, h), TAU)
		if turned >= span:
			continue
		var own_block := HHElementBridge.is_block(sim, h) and not h in broken
		if own_block:
			blocks.append(h)
		var behind := false
		for s in HHHex.line(u.hex, h):
			if s == h or HHHex.distance(u.hex, s) <= int(u.size):
				continue
			if HHElementBridge.is_block(sim, s) and not s in broken:
				behind = true
				break
		if behind:
			shadow.append(h)
		elif sim.arena.walkable(h) or own_block:
			hit.append(h)
	hit.sort()
	shadow.sort()
	return { "hit": hit, "shadow": shadow, "blocks": blocks }


static func _run_sweep(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	if str(act.phase) == "walk":
		var arrived: bool = u.hex == act.goal and float(u.progress) == 0.0
		if not arrived and sim.tick < int(act.until):
			if (u.path as Array).is_empty() and (sim.tick - int(act.t0)) % 10 == 0:
				sim.monster_move(u, act.goal)
			return
		u.path = [] as Array[Vector2i]
		if float(u.progress) > 0.0:
			u.progress = 0.0
			u.pos = sim.arena.stand(u.hex)
		var p := _target(sim, u)
		act.a0 = _angle(u.hex, p.hex) if not p.is_empty() else float(u.facing)
		act.phase = "wind"
		act.start = sim.tick + ti("sw_windup_ticks")
		act.total = sweep_total()
		u.facing = float(act.a0)
		_anim(sim, u, T, _clip(T, "channel"), 0.5, true)
	var start := int(act.start)
	var total := int(act.total)
	var step := maxi(1, ti("sw_slice_ticks"))
	var lead := ti("sw_lead_ticks")
	# telegraph the slices the beam reaches within `lead` ticks
	while int(act.issued) < total and start + int(act.issued) - sim.tick <= lead:
		var r0 := int(act.issued)
		var r1 := mini(total, r0 + step)
		var sl := sweep_slice(sim, u, act, r0, r1)
		var at := start + r0 + (r1 - r0) / 2
		var win := maxi(1, at - sim.tick)
		if not (sl.hit as Array).is_empty():
			sim.telegraph(u.id, sl.hit, win, { "dmg_pct": t("sw_dmg_pct") * float(T.dmg) * float(T.buff), "element": str(act.el),
				"paint_steps": 0, "stagger": t("sw_stagger"), "name": "tier_sweep" })
		(act.paints as Array).append([sim.tick + win, sl.hit])
		var safe: Array = act.safe
		safe.append_array(sl.shadow)
		while safe.size() > 90:
			safe.pop_front()
		var hits: Dictionary = act.hits
		for b in sl.blocks:
			var key := "%d,%d" % [b.x, b.y]
			hits[key] = int(hits.get(key, 0)) + 1
			if int(hits[key]) >= ti("sw_block_hits") and not b in (act.broken as Array):
				if HHElementBridge.break_block(sim, b):
					(act.broken as Array).append(b)
					_log(sim, u, T, "block_broken", { "hex": b })
		act.issued = r1
	# paint the slices the beam has passed: tier 3 of its element (an override, contained)
	var keep: Array = []
	for pr in act.paints:
		if sim.tick >= int(pr[0]):
			if not (pr[1] as Array).is_empty():
				HHElementBridge.paint_own(sim, u, pr[1], str(act.el), ti("sw_tier"))
		else:
			keep.append(pr)
	act.paints = keep
	if sim.tick >= start:
		act.phase = "sweep"
		u.facing = sweep_angle(act, float(sim.tick - start))
		var cl := _clip(T, "channel")
		if cl != "" and (sim.tick - start) % 72 == 0:
			_anim(sim, u, T, cl, 0.8, true)
	if int(act.issued) >= total and keep.is_empty() and sim.tick >= start + total:
		_end(sim, brain, u, T)


# ---- 8.3 siphon

## Connected groups of hexes carrying `element` that the monster did not lay
## and the arena did not author: [{ hexes, points, centre }], biggest first.
static func clusters(sim: HHSim, u: Dictionary, element: String) -> Array:
	var keys: Array = sim.charge.entries.keys()
	keys.sort()
	var seen := {}
	var out: Array = []
	for h0 in keys:
		if seen.has(h0) or sim.charge.intensity(h0, element) <= 0 or not HHElementBridge.foreign(sim, h0, u):
			continue
		var group: Array = []
		var pts := 0
		var q: Array = [h0]
		seen[h0] = true
		while not q.is_empty():
			var h: Vector2i = q.pop_front()
			group.append(h)
			pts += sim.charge.intensity(h, element)
			for n in HHHex.neighbors(h):
				if not seen.has(n) and sim.charge.intensity(n, element) > 0 and HHElementBridge.foreign(sim, n, u):
					seen[n] = true
					q.append(n)
		group.sort()
		var best: Vector2i = group[0]
		var best_d := 1 << 30
		for a in group:
			var s := 0
			for b in group:
				s += HHHex.distance(a, b)
			if s < best_d:
				best_d = s
				best = a
		out.append({ "hexes": group, "points": pts, "centre": best })
	out.sort_custom(func(a, b): return int(a.points) > int(b.points) or (int(a.points) == int(b.points) and a.centre < b.centre))
	return out


static func _start_siphon(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> bool:
	var el := str(profile(str(T.kind)).get("siphon", ""))
	if el == "":
		return false
	var cl := clusters(sim, u, el)
	if cl.is_empty() or int(cl[0].points) < ti("si_min_points"):
		return false
	var goal := _nearest_fit(sim, u, cl[0].centre, 3)
	if goal == NO_HEX:
		return false
	_begin(sim, u, T, { "kind": "siphon", "phase": "stalk", "el": el, "goal": goal, "cluster": cl[0].hexes, "points": int(cl[0].points),
		"until": sim.tick + secs("si_stalk_s"), "path": [] })
	sim.monster_move(u, goal)
	_siphon_path(u, T.act)
	_anim(sim, u, T, _clip(T, "walk"), 0.8, true)
	return true


static func _siphon_path(u: Dictionary, act: Dictionary) -> void:
	var p: Array = [u.hex]
	for h in u.path:
		p.append(h)
	act.path = p


static func _run_siphon(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	var goal: Vector2i = act.goal
	if str(act.phase) == "stalk":
		var near := HHHex.distance(u.hex, goal)
		var arrived: bool = (near == 0 or ((u.path as Array).is_empty() and near <= 2)) and float(u.progress) == 0.0
		if not arrived and sim.tick < int(act.until):
			if (sim.tick - int(act.t0)) % 15 == 0:
				var left := 0
				for h in act.cluster:
					if sim.charge.intensity(h, str(act.el)) > 0 and HHElementBridge.foreign(sim, h, u):
						left += sim.charge.intensity(h, str(act.el))
				act.points = left
				if (u.path as Array).is_empty():
					sim.monster_move(u, goal)
			_siphon_path(u, act)
			return
		u.path = [] as Array[Vector2i]
		var drink: Array = []
		for h in HHHex.area(u.hex, int(u.size) + ti("si_reach")):
			if sim.arena.exists(h):
				drink.append(h)
		drink.sort()
		var pts := HHElementBridge.siphon(sim, u, drink, str(act.el))
		act.taken = pts
		act.phase = "drink"
		act.path = []
		act.until = sim.tick + 45
		T.fx["siphon"] = sim.tick
		T.fx["siphon_pts"] = pts
		if pts > 0:
			sim.heal(u, float(u.max_hp) * minf(t("si_heal_max_pct"), t("si_heal_pct_per_point") * float(pts)) / 100.0, "siphon")
			T.buff = minf(t("si_buff_max"), 1.0 + t("si_buff_per_point") * float(pts))
			T.buff_until = sim.tick + secs("si_buff_s")
			_anim(sim, u, T, _clip(T, "roar"), 1.0, true)
		else:
			_anim(sim, u, T, _clip(T, "react"), 0.6, true)  # arrived at empty ground
		_log(sim, u, T, "siphon", { "points": pts, "buff": T.buff })
		return
	if sim.tick >= int(act.until):
		_end(sim, brain, u, T)


# ---- 8.4 rooting

static func sun_count(sim: HHSim, u: Dictionary, h: Vector2i) -> int:
	var n := 0
	for c in HHHex.area(h, int(u.size)):
		if sim.arena.exists(c) and str(sim.arena.kind(c)) == "sun":
			n += 1
	return n


## The nearest spot whose hull covers rt_min_sun authored sun hexes.
static func root_spot(sim: HHSim, u: Dictionary) -> Vector2i:
	var blocked := sim.blocked_for(u)
	var best := NO_HEX
	var best_d := 1 << 30
	var keys: Array = sim.arena.cells.keys()
	keys.sort()
	for h in keys:
		if str(sim.arena.kind(h)) != "sun":
			continue
		if sun_count(sim, u, h) < ti("rt_min_sun") or not _fits(sim, u, h, blocked):
			continue
		var d := HHHex.distance(u.hex, h)
		if d < best_d:
			best_d = d
			best = h
	return best


static func _start_root(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> bool:
	if float(u.hp) / maxf(1.0, float(u.max_hp)) >= t("rt_hp_below"):
		return false
	var goal := root_spot(sim, u)
	if goal == NO_HEX:
		return false
	_begin(sim, u, T, { "kind": "root", "phase": "walk", "goal": goal, "until": sim.tick + secs("rt_walk_s"), "healed": 0.0 })
	if goal != u.hex:
		sim.monster_move(u, goal)
		_anim(sim, u, T, _clip(T, "walk"), 1.0, true)
	return true


## A rooted hull with fire or dark under it that someone else laid.
static func root_corrupted(sim: HHSim, u: Dictionary) -> bool:
	for h in sim.footprint(u):
		if not HHElementBridge.foreign(sim, h, u):
			continue
		if sim.charge.intensity(h, "fire") > 0 or sim.charge.intensity(h, "dark") > 0:
			return true
	return false


static func _run_root(sim: HHSim, brain: Object, u: Dictionary, T: Dictionary) -> void:
	var act: Dictionary = T.act
	match str(act.phase):
		"walk":
			var arrived: bool = u.hex == act.goal and float(u.progress) == 0.0
			if not arrived and sim.tick < int(act.until):
				if (u.path as Array).is_empty() and (sim.tick - int(act.t0)) % 10 == 0:
					sim.monster_move(u, act.goal)
				return
			u.path = [] as Array[Vector2i]
			if sun_count(sim, u, u.hex) < ti("rt_min_sun"):
				_end(sim, brain, u, T)                   # never reached the sun
				return
			act.phase = "rooted"
			act.until = sim.tick + ti("rt_ticks")
			act.rooted_at = sim.tick
			T.fx["root"] = sim.tick
			_anim(sim, u, T, _clip(T, "root"), 1.0, true)
			_log(sim, u, T, "rooted", { "hex": u.hex })
		"rooted":
			if root_corrupted(sim, u):
				var st := secs("rt_stun_s")
				act.phase = "stun"
				act.until = sim.tick + st
				T.fx["stun"] = sim.tick
				var was := int(u.get("exposed", 0))
				u.exposed = maxi(was, st)
				if was <= 0:
					sim._emit({ "type": "exposed", "id": u.id, "ticks": st })
				_anim(sim, u, T, _clip(T, "stun"), 1.0, true)
				_log(sim, u, T, "root_corrupted", { "stun": st })
				return
			if (sim.tick - int(act.rooted_at)) % 30 == 29:
				var amt := float(u.max_hp) * t("rt_heal_pct_s") / 100.0
				sim.heal(u, amt, "root")
				act.healed = float(act.healed) + amt
			if sim.tick >= int(act.until):
				_end(sim, brain, u, T)
		"stun":
			if (sim.tick - int(T.fx.get("stun", sim.tick))) % 45 == 44:
				_anim(sim, u, T, _clip(T, "stun"), 1.0, true)
			if sim.tick >= int(act.until):
				_end(sim, brain, u, T)
