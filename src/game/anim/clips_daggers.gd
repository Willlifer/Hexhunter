class_name HHClipsDaggers
extends RefCounted
## The dual-dagger clip set (Lane B): sword-sized karambits, one per hand
## (socket_weapon_r + socket_offhand_l), reverse grip so the blades run down
## the forearms. Low, wide, quick: contact at tick 5 (0.17 s) on the basic.
## The anticipation is a tight coil, the release a lunge, the follow-through
## a wide arm that re-centres.

const A := HHClipsShared.ANKLE_Y

const CLIPS := {
	"idle":        { "duration": 4.0, "contact_tick": -1, "loop": true,  "key": 1.0, "note": "blades reversed at the hips, loose shoulders" },
	"wield_idle":  { "duration": 2.4, "contact_tick": -1, "loop": true,  "key": 0.6, "note": "low crouch, arms out, blades down, weight bouncing" },
	"walk":        { "duration": 0.436, "contact_tick": -1, "loop": true, "key": 0.1, "stride": 2.4, "note": "jog, blades trailing" },
	"run":         { "duration": 0.4325, "contact_tick": -1, "loop": true, "key": 0.05, "stride": 3.46, "note": "sprint, both arms pump, blades trail down-back" },
	"strike":      { "duration": 0.5, "contact_tick": 5, "loop": false, "key": 0.18, "note": "the basic: right slash in-to-out with a lunge, left blade guards" },
	"sweep":       { "duration": 0.7, "contact_tick": 7, "loop": false, "key": 0.25, "note": "both blades cross in front at hip height" },
	"spin":        { "duration": 0.9, "contact_tick": 9, "loop": false, "key": 0.3, "note": "hop-spin, arms out, blades level" },
	"jump":        { "duration": 0.87, "contact_tick": -1, "loop": false, "key": 0.45, "note": "tuck, arms out for balance" },
	"jump_attack": { "duration": 0.8, "contact_tick": 5, "loop": false, "key": 0.2, "note": "landing double stab down" },
	"dive":        { "duration": 1.0, "contact_tick": 12, "loop": false, "key": 0.4, "note": "Daggerleap: head-first dive with a corkscrew roll, blades leading, rolls out to the feet" },
	"flourish":    { "duration": 0.9, "contact_tick": 10, "loop": false, "key": 0.33, "note": "a grounded turn with the blades twirling out wide" },
	"swap":        { "duration": 0.9, "contact_tick": -1, "loop": false, "key": 0.4, "note": "Elemental Exchange: both blades flipped and caught" },
	"stagger":     { "duration": 1.0, "contact_tick": -1, "loop": false, "key": 0.3, "note": "knocked back a step" },
	"hit_react":   { "duration": 0.45, "contact_tick": -1, "loop": false, "key": 0.08, "note": "flinch" },
	"death":       { "duration": 1.5, "contact_tick": -1, "loop": false, "key": 1.3, "note": "falls onto the back" },
	"dash":        { "duration": 0.36, "contact_tick": -1, "loop": false, "key": 0.12, "note": "H56: the dash, a low forward burst, the blades trailing" },
	# H60 (Lane X): the string, one dedicated clip per hit timed to the sim (see HHClipsLance for the row fields)
	"combo_slash":  { "duration": 0.467, "contact_tick": 5, "recovery": 5, "timed": true, "loop": false, "key": 0.167, "trail": [0.12, 0.27, 0.5, "main"],
		"note": "string hit 1: low coil, the right blade cuts high-right to low-left on a stepping lunge, the left flung back" },
	"combo_spin":   { "duration": 0.6, "contact_tick": 7, "recovery": 11, "timed": true, "loop": false, "key": 0.233, "trail": [0.08, 0.31, 0.9, "off"],
		"note": "string hit 2: a reverse hop-spin, the left blade leads the turn and cuts left to right as she lands facing front" },
	"combo_pounce": { "duration": 0.77, "contact_tick": 10, "recovery": 16, "timed": true, "loop": false, "key": 0.333, "trail": [0.29, 0.46, 1.5, "both"],
		"note": "string finisher: crouch, pounce, both blades over the top and crossed down in an X on the landing, ripped open, hop home" },
	"combo_ready1": { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits 1 and 2: wound to the left, the left blade cocked" },
	"combo_ready2": { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits 2 and 3: crouched to pounce, blades low and back" },
}
const SKILL_CLIPS := { "q": "flourish", "w": "swap", "e": "dive", "r": "jump" }   # H56: Q is the Flourish, E the Daggerleap (they were crossed)
const WINDUP_CLIPS := { "basic": "strike", "dive": "dive", "flourish": "flourish", "exchange": "swap" }
## H57: the basic string; H60: one dedicated clip per hit (cross slash, reverse spin, pounce X-cut), and the loops between hits.
const COMBO_CLIPS := { 1: "combo_slash", 2: "combo_spin", 3: "combo_pounce" }
const READY_CLIPS := { 1: "combo_ready1", 2: "combo_ready2" }
## H56: the held charge pose.
const CHARGE_CLIP := "flourish"
const LANDING_CLIPS := { "jump": "jump_attack" }


static func pose(clip: String, t: float, b: HHPlayerBody) -> void:
	match clip:
		"idle": HHClipsShared.idle(t, b, carry_idle())
		"wield_idle": _wield_idle(t, b)
		"walk": HHClipsShared.walk(t, b, carry_run(), 1.0, 1.0)
		"run": HHClipsShared.run(t, b, carry_run(), 1.0, 1.0)
		"strike": _strike(t, b)
		"sweep": _sweep(t, b)
		"spin": _spin(t, b)
		"jump": HHClipsShared.jump(t, b, carry_air(), float(CLIPS.jump.duration))
		"jump_attack": _jump_attack(t, b)
		"dive": _dive(t, b)
		"flourish": _flourish(t, b)
		"swap": _swap(t, b)
		"stagger": HHClipsShared.stagger(t, b, wield())
		"hit_react": HHClipsShared.hit_react(t, b, wield())
		"death": HHClipsShared.death(t, b, wield())
		"dash": HHClipsShared.dash(t, b, carry_run())
		"combo_slash": _combo_slash(t, b)
		"combo_spin": _combo_spin(t, b)
		"combo_pounce": _combo_pounce(t, b)
		"combo_ready1": HHClipsShared.ready_loop(t, b, ready1())
		"combo_ready2": HHClipsShared.ready_loop(t, b, ready2())


# ------------------------------------------------------------------ poses

## Reverse grip: the blade runs down from the fist. Aim only (no reach).
static func down_r() -> Dictionary:
	return HHClipsShared.hand(Vector3.ZERO, "", HHClipsShared.aim(-84.0, -10.0), null)


static func down_l() -> Dictionary:
	return HHClipsShared.hand(Vector3.ZERO, "", HHClipsShared.aim(-84.0, 10.0), null)


static func _noreach(h: Dictionary) -> Dictionary:
	var out := h.duplicate()
	out.reach = false
	return out


static func carry_idle() -> Dictionary:
	return {
		"upper_arm_l": Vector3(4, 0, -20), "forearm_l": Vector3(-16, 0, 0),
		"upper_arm_r": Vector3(4, 0, 20), "forearm_r": Vector3(-16, 0, 0),
		"hand_l": _noreach(down_l()), "hand_r": _noreach(down_r()),
	}


static func carry_run() -> Dictionary:
	return { "hand_l": _noreach(down_l()), "hand_r": _noreach(down_r()) }


static func carry_air() -> Dictionary:
	return {
		"upper_arm_l": Vector3(-20, 0, 50), "upper_arm_r": Vector3(-20, 0, -50), "forearm_l": Vector3(-30, 0, 0), "forearm_r": Vector3(-30, 0, 0),
		"hand_l": _noreach(down_l()), "hand_r": _noreach(down_r()),
	}


## The crouch: wide feet, hips low, arms out, blades down and slightly forward.
static func wield() -> Dictionary:
	return {
		"move:root": Vector3(0, -0.14, 0),
		"hips": Vector3(12, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, 0, 0), "neck": Vector3(-8, 0, 0), "head": Vector3(-12, 0, 0),
		"foot_l": [Vector3(0.28, A, 0.26), 0.0], "foot_r": [Vector3(-0.28, A, -0.22), 0.0],
		"hand_r": HHClipsShared.hand(Vector3(-0.44, 0.98, 0.18), "", HHClipsShared.aim(-70.0, -20.0)),
		"hand_l": HHClipsShared.hand(Vector3(0.42, 1.02, 0.26), "", HHClipsShared.aim(-70.0, 20.0)),
	}


static func _wield_idle(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.apply(b, wield())
	HHClipsShared.breath(b, t, 2.4, 0.8)
	var s := sin(TAU * t / 1.2)
	b.move("root", Vector3(0.0, 0.02 * s, 0.0))                 # bouncing on the toes
	b.rot("hips", Vector3(0.0, 3.0 * sin(TAU * t / 2.4), 0.0))


# ------------------------------------------------------------------ attacks

static func _strike(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.09, HHClipsShared.merge(w, { "move:root": Vector3(0.04, -0.16, -0.06), "hips": Vector3(12, 22, 0), "spine": Vector3(4, 10, 0), "chest": Vector3(6, 14, 0), "head": Vector3(-12, -20, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.46, 1.24, -0.22), "", HHClipsShared.aim(-50.0, -50.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.3, 1.1, 0.34), "", HHClipsShared.aim(-60.0, 30.0)) }), "coil"),
		HHClipsShared.key(0.167, HHClipsShared.merge(w, { "move:root": Vector3(-0.04, -0.14, 0.3), "hips": Vector3(10, -24, 0), "spine": Vector3(4, -12, 0), "chest": Vector3(4, -20, 0), "neck": Vector3(2, 10, 0), "head": Vector3(-8, 16, 0),
			"foot_l": [Vector3(0.26, A, 0.62), 0.0], "foot_r": [Vector3(-0.28, A, -0.2), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.18, 1.2, 0.74), "", HHClipsShared.aim(-10.0, 70.0), Vector3(-0.9, -0.2, 0.2)),
			"hand_l": HHClipsShared.hand(Vector3(0.42, 1.0, -0.12), "", HHClipsShared.aim(-70.0, 20.0)) }), "snap"),
		HHClipsShared.key(0.26, HHClipsShared.merge(w, { "move:root": Vector3(-0.06, -0.14, 0.32), "hips": Vector3(10, -32, 0), "spine": Vector3(4, -14, 0), "chest": Vector3(4, -24, 0), "neck": Vector3(2, 12, 0), "head": Vector3(-8, 20, 0),
			"foot_l": [Vector3(0.26, A, 0.62), 0.0], "foot_r": [Vector3(-0.28, A, -0.2), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.5, 1.1, 0.5), "", HHClipsShared.aim(-20.0, 105.0), Vector3(-0.9, -0.2, 0.2)),
			"hand_l": HHClipsShared.hand(Vector3(0.42, 1.0, -0.12), "", HHClipsShared.aim(-70.0, 20.0)) })),
		HHClipsShared.key(0.5, w),
	]
	HHClipsShared.keyed(t, keys, b)


static func _sweep(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.14, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.18, -0.08), "hips": Vector3(14, 0, 0), "chest": Vector3(8, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.6, 1.1, -0.1), "", HHClipsShared.aim(-30.0, -100.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.6, 1.1, -0.1), "", HHClipsShared.aim(-30.0, 100.0)) }), "coil"),
		HHClipsShared.key(0.233, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.2, 0.2), "hips": Vector3(18, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(10, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.46), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.12, 0.95, 0.52), "", HHClipsShared.aim(-10.0, 50.0)),
			"hand_l": HHClipsShared.hand(Vector3(-0.12, 1.05, 0.5), "", HHClipsShared.aim(-10.0, -50.0)) }), "snap"),
		HHClipsShared.key(0.36, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.2, 0.22), "hips": Vector3(18, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(10, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.46), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.3, 0.9, 0.4), "", HHClipsShared.aim(-10.0, 80.0)),
			"hand_l": HHClipsShared.hand(Vector3(-0.3, 1.0, 0.4), "", HHClipsShared.aim(-10.0, -80.0)) })),
		HHClipsShared.key(0.7, w),
	]
	HHClipsShared.keyed(t, keys, b)


static func _spin(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var yaw := 0.0
	if t < 0.12:
		yaw = -45.0 * HHClipsShared.coil(t / 0.12)
	elif t < 0.3:
		yaw = lerpf(-45.0, 360.0, (t - 0.12) / 0.18)
	else:
		yaw = 360.0
	var air := HHClipsShared.ss(t, 0.1, 0.17) * (1.0 - HHClipsShared.ss(t, 0.3, 0.42))
	var base := HHClipsShared.merge(w, {
		"move:root": Vector3(0, -0.12 + 0.3 * air, 0.0),
		"hand_r": HHClipsShared.hand(Vector3(-0.62, 1.1, 0.0), "", HHClipsShared.aim(-5.0, -100.0)),
		"hand_l": HHClipsShared.hand(Vector3(0.62, 1.1, 0.0), "", HHClipsShared.aim(-5.0, 100.0)),
	})
	if air > 0.01:
		base.erase("foot_l")
		base.erase("foot_r")
		base["thigh_l"] = Vector3(-40 * air, 0, 0)
		base["shin_l"] = Vector3(60 * air, 0, 0)
		base["thigh_r"] = Vector3(-40 * air, 0, 0)
		base["shin_r"] = Vector3(60 * air, 0, 0)
	var rotated := HHClipsShared.rotate_pose(base, yaw)
	HHClipsShared.apply(b, HHClipsShared.mix(rotated, HHClipsShared.merge(w, { "root": Vector3(0, 360, 0) }), HHClipsShared.ss(t, 0.42, 0.9)))


static func _jump_attack(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, HHClipsShared.merge(carry_air(), { "hips": Vector3(6, 0, 0), "thigh_l": Vector3(-25, 0, 0), "shin_l": Vector3(20, 0, 0), "thigh_r": Vector3(-25, 0, 0), "shin_r": Vector3(20, 0, 0) })),
		HHClipsShared.key(0.167, { "move:root": Vector3(0, -0.36, 0.1), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-12, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.3), 0.0], "foot_r": [Vector3(-0.26, A, -0.28), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.2, 0.62, 0.5), "", HHClipsShared.aim(-80.0, -5.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.2, 0.62, 0.5), "", HHClipsShared.aim(-80.0, 5.0)) }, "snap"),
		HHClipsShared.key(0.4, { "move:root": Vector3(0, -0.36, 0.1), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(-12, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.3), 0.0], "foot_r": [Vector3(-0.26, A, -0.28), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.2, 0.6, 0.52), "", HHClipsShared.aim(-82.0, -5.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.2, 0.6, 0.52), "", HHClipsShared.aim(-82.0, 5.0)) }),
		HHClipsShared.key(0.8, w),
	]
	HHClipsShared.keyed(t, keys, b)
	b.rot("chest", Vector3(3.0 * HHClipsShared.shake(t, 0.167, 0.25, 14.0), 0.0, 0.0))


## Head-first dive with a corkscrew: the root pitches the whole body
## horizontal at chest height, rolls once about its length, then lands.
static func _dive(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var pitch := 86.0 * HHClipsShared.ss(t, 0.0, 0.22) * (1.0 - HHClipsShared.ss(t, 0.62, 0.85))
	var lift := 1.05 * HHClipsShared.ss(t, 0.0, 0.22) * (1.0 - HHClipsShared.ss(t, 0.62, 0.85))
	var roll := 360.0 * HHClipsShared.ease_u(clampf((t - 0.14) / 0.46, 0.0, 1.0), "ss")
	var fly := HHClipsShared.ss(t, 0.0, 0.2)
	var land := HHClipsShared.ss(t, 0.62, 0.85)
	var settle := HHClipsShared.ss(t, 0.85, 1.0)
	# arms forward past the head, blades leading; legs straight, toes pointed
	var air := {
		"hips": Vector3(-6, 0, 0), "spine": Vector3(-4, 0, 0), "chest": Vector3(-6, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-14, 0, 0),
		"upper_arm_l": Vector3(-150, 0, -10), "upper_arm_r": Vector3(-150, 0, 10), "forearm_l": Vector3(-6, 0, 0), "forearm_r": Vector3(-6, 0, 0),
		"hand_l": _noreach(HHClipsShared.hand(Vector3.ZERO, "", HHClipsShared.aim(0.0, 10.0))), "hand_r": _noreach(HHClipsShared.hand(Vector3.ZERO, "", HHClipsShared.aim(0.0, -10.0))),
		"thigh_l": Vector3(8, 0, 0), "thigh_r": Vector3(8, 0, 0), "shin_l": Vector3(4, 0, 0), "shin_r": Vector3(4, 0, 0),
		"foot_l": [Vector3(0.12, A, 0.0), 40.0, 0.0], "foot_r": [Vector3(-0.12, A, 0.0), 40.0, 0.0],
	}
	var crouch := HHClipsShared.merge(w, { "move:root": Vector3(0, -0.34, 0.1), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
		"hand_r": HHClipsShared.hand(Vector3(-0.42, 0.8, 0.34), "", HHClipsShared.aim(-70.0, -20.0)), "hand_l": HHClipsShared.hand(Vector3(0.42, 0.8, 0.34), "", HHClipsShared.aim(-70.0, 20.0)) })
	var p := HHClipsShared.mix(w, air, fly)
	p = HHClipsShared.mix(p, crouch, land)
	p = HHClipsShared.mix(p, w, settle)
	# the root: pitched over head-first (outer), then the corkscrew about the
	# body's own length (inner: HHPlayerBody.rot applies the first call outermost)
	b.move("root", Vector3(0.0, lift, 0.0))
	b.rot("root", Vector3(pitch, 0.0, 0.0))
	b.rot("root", Vector3(0.0, roll * fly * (1.0 - land), 0.0))
	HHClipsShared.apply(b, p)
	if t > 0.85:
		b.rot("chest", Vector3(2.0 * HHClipsShared.shake(t, 0.85, 0.15, 12.0), 0.0, 0.0))


static func _flourish(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var yaw := 0.0
	if t < 0.1:
		yaw = -30.0 * HHClipsShared.coil(t / 0.1)
	elif t < 0.5:
		yaw = lerpf(-30.0, 360.0, HHClipsShared.ease_u((t - 0.1) / 0.4, "ss"))
	else:
		yaw = 360.0
	var twirl := 720.0 * HHClipsShared.ss(t, 0.05, 0.55)
	var base := HHClipsShared.merge(w, {
		"move:root": Vector3(0, -0.2, 0),
		"hips": Vector3(16, 0, 0), "chest": Vector3(8, 0, 0),
		"hand_r": HHClipsShared.hand(Vector3(-0.6, 1.15, 0.05), "", HHClipsShared.aim(-10.0 + 60.0 * sin(deg_to_rad(twirl)), -95.0)),
		"hand_l": HHClipsShared.hand(Vector3(0.6, 1.15, 0.05), "", HHClipsShared.aim(-10.0 - 60.0 * sin(deg_to_rad(twirl)), 95.0)),
	})
	# feet shuffle through the turn: the right foot pivots, the left steps around
	base["foot_l"] = [Vector3(0.28, A + 0.08 * sin(PI * HHClipsShared.ss(t, 0.1, 0.5)), 0.26), 0.0]
	var rotated := HHClipsShared.rotate_pose(base, yaw)
	HHClipsShared.apply(b, HHClipsShared.mix(rotated, HHClipsShared.merge(w, { "root": Vector3(0, 360, 0) }), HHClipsShared.ss(t, 0.5, 0.9)))


static func _swap(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var flip := 360.0 * HHClipsShared.ss(t, 0.18, 0.58)
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.2, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.06, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.45, 0.3), "", HHClipsShared.aim(80.0 + flip, -10.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.3, 1.45, 0.3), "", HHClipsShared.aim(80.0 + flip, 10.0)) }), "snap"),
		HHClipsShared.key(0.6, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.1, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.4, 0.3), "", HHClipsShared.aim(80.0 + flip, -10.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.3, 1.4, 0.3), "", HHClipsShared.aim(80.0 + flip, 10.0)) })),
		HHClipsShared.key(0.9, w),
	]
	HHClipsShared.keyed(t, keys, b)


# ------------------------------------------------------------------ the string (H60, Lane X)
# Three dedicated hits on Black | White's strike rig (HHClipsShared.beats /
# rooted / plant / impact). The hands alternate: the right blade cuts hit
# 1, the left leads the spin of hit 2, both cross on the finisher.

const PLANT_L := Vector3(0.28, A, 0.26)        ## the crouch's plants (wield())
const PLANT_R := Vector3(-0.28, A, -0.22)


## The crouch in the root frame: rooted(_wr()) is exactly wield().
static func _wr() -> Dictionary:
	var w := wield()
	var r: Vector3 = w["move:root"]
	for k in ["hand_l", "hand_r"]:
		var h: Dictionary = (w[k] as Dictionary).duplicate()
		h.pos = (h.pos as Vector3) - r
		w[k] = h
	return w


static func _h(pos: Vector3, pitch: float, yaw: float, pole: Variant = null) -> Dictionary:
	return HHClipsShared.hand(pos, "", HHClipsShared.aim(pitch, yaw), pole)


## Between hits 1 and 2: wound to the left (where the slash ended), the
## right arm across the body, the left blade cocked back for the spin.
static func ready1() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.16, 0),
		"hips": Vector3(12, 14, 0), "spine": Vector3(4, 6, 0), "chest": Vector3(6, 22, 0), "neck": Vector3(-8, -6, 0), "head": Vector3(-12, -14, 0),
		"hand_r": _h(Vector3(0.16, 1.14, 0.36), -60.0, 40.0), "hand_l": _h(Vector3(0.5, 1.26, -0.08), -40.0, 70.0) })


## Between hits 2 and 3: crouched to pounce, both blades low and back.
static func ready2() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.26, -0.04),
		"hips": Vector3(22, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(10, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-14, 0, 0),
		"hand_r": _h(Vector3(-0.36, 0.98, -0.12), -80.0, -30.0), "hand_l": _h(Vector3(0.36, 0.98, -0.12), -80.0, 30.0) })


## HIT 1, the cross slash (wind-up 5, recovery 5). From B|W _strike_pair
## (a low crouching coil, the right blade back, a right cross-cut on the
## hit) with _strike_one's free arm (reaches for the target in the coil,
## flung back on the cut), on the reference body's stepping lunge.
static func _combo_slash(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(5, 5, 4)
	var w := _wr()
	var stop: float = bt.hit + HHClipsShared.T
	var over: float = bt.hit + 2.6 * HHClipsShared.T
	var keys := [
		HHClipsShared.rkey(0.0, w),
		HHClipsShared.rkey(bt.coil, HHClipsShared.merge(w, { "move:root": Vector3(0.03, -0.2, -0.05), "hips": Vector3(14, -18, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -26, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-12, 20, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.56, 1.55, -0.12), "", HHClipsShared.aim(30.0, -120.0, 180.0)), "hand_l": _h(Vector3(0.3, 1.22, 0.42), -55.0, 20.0) }), "coil"),
		HHClipsShared.rkey(bt.launch, HHClipsShared.merge(w, { "move:root": Vector3(0.02, -0.23, -0.03), "hips": Vector3(14, -16, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -24, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-12, 20, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.54, 1.55, -0.08), "", HHClipsShared.aim(26.0, -110.0, 180.0)), "hand_l": _h(Vector3(0.3, 1.22, 0.42), -55.0, 20.0) })),
		HHClipsShared.rkey(bt.land, HHClipsShared.merge(w, { "move:root": Vector3(0.0, -0.18, 0.18), "hips": Vector3(12, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, -4, 0),
			"neck": Vector3(-6, 2, 0), "head": Vector3(-10, 4, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.42, 0.4), "", HHClipsShared.aim(0.0, -30.0, 180.0)), "hand_l": _h(Vector3(0.38, 1.16, 0.2), -62.0, 24.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(w, { "move:root": Vector3(-0.02, -0.18, 0.28), "hips": Vector3(10, 26, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 40, 0),
			"neck": Vector3(-2, -10, 0), "head": Vector3(-8, -16, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.14, 1.3, 0.6), "", HHClipsShared.aim(-20.0, 55.0, 180.0), Vector3(-0.9, -0.2, 0.2)), "hand_l": _h(Vector3(0.44, 1.14, -0.08), -70.0, 30.0) }), "lin"),
		HHClipsShared.rkey(stop, HHClipsShared.merge(w, { "move:root": Vector3(-0.025, -0.185, 0.285), "hips": Vector3(10, 27, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 42, 0),
			"neck": Vector3(-2, -10, 0), "head": Vector3(-8, -16, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.18, 1.29, 0.59), "", HHClipsShared.aim(-21.0, 62.0, 180.0), Vector3(-0.9, -0.2, 0.2)), "hand_l": _h(Vector3(0.45, 1.14, -0.1), -70.0, 30.0) })),
		HHClipsShared.rkey(over, HHClipsShared.merge(w, { "move:root": Vector3(-0.04, -0.19, 0.27), "hips": Vector3(10, 32, 0), "spine": Vector3(4, 14, 0), "chest": Vector3(4, 48, 0),
			"neck": Vector3(-2, -14, 0), "head": Vector3(-8, -22, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.46, 1.18, 0.38), "", HHClipsShared.aim(-28.0, 100.0, 180.0), Vector3(-0.9, -0.2, 0.2)), "hand_l": _h(Vector3(0.48, 1.18, -0.12), -60.0, 50.0) }), "over"),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(w, { "move:root": Vector3(-0.02, -0.22, 0.18), "hips": Vector3(12, 22, 0), "spine": Vector3(4, 8, 0), "chest": Vector3(6, 30, 0),
			"neck": Vector3(-6, -10, 0), "head": Vector3(-10, -16, 0),
			"hand_r": _h(Vector3(0.3, 1.12, 0.38), -40.0, 70.0), "hand_l": _h(Vector3(0.5, 1.22, -0.1), -48.0, 64.0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(ready1(), { "move:root": Vector3(0, -0.13, 0.02) })),
		HHClipsShared.rkey(bt.end, ready1()),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L], [bt.coil, bt.hit, Vector3(0.26, A, 0.5)], [bt.hop_start + 0.02, bt.hop_end + 0.03, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, stop, Vector3(-0.28, A, -0.04)], [bt.hop_start, bt.hop_end, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.2, 2.0, 18.0)


## HIT 2, the reverse spin (wind-up 7, recovery 11). From B|W
## _strike_spin (pair): the whole body turns a full circle off both feet,
## the head spotting, applied as a root yaw only while airborne so the
## planted feet never twist; the left blade rides out on the turn and
## whips across the front on the landing; hit-stop, the chest overshoots,
## and the hop home sinks straight into the pounce's crouch.
static func _combo_spin(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(7, 11, 0)
	var r1 := ready1()
	var lift := 0.06
	var down: float = bt.hit - 0.4 * HHClipsShared.T
	var stop: float = bt.hit + 1.5 * HHClipsShared.T
	var keys := [
		HHClipsShared.rkey(0.0, r1),
		HHClipsShared.rkey(lift, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.22, 0.0), "hips": Vector3(14, 26, 0), "spine": Vector3(4, 10, 0), "chest": Vector3(8, 34, 0),
			"neck": Vector3(-8, -14, 0), "head": Vector3(-12, -24, 0),
			"hand_r": _h(Vector3(0.12, 1.2, 0.3), -60.0, 50.0), "hand_l": _h(Vector3(0.56, 1.24, -0.18), -30.0, 80.0) }), "coil"),
		HHClipsShared.rkey(lerpf(lift, down, 0.5), HHClipsShared.merge(r1, { "move:root": Vector3(0, 0.12, 0.1), "hips": Vector3(4, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(2, 0, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-8, 20, 0),
			"hand_r": _h(Vector3(-0.3, 1.44, 0.16), -40.0, -20.0), "hand_l": _h(Vector3(0.66, 1.22, 0.06), -10.0, 95.0) })),
		HHClipsShared.rkey(down, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.14, 0.2), "hips": Vector3(12, 8, 0), "spine": Vector3(4, 4, 0), "chest": Vector3(6, 10, 0),
			"neck": Vector3(-6, -4, 0), "head": Vector3(-10, -6, 0),
			"hand_r": _h(Vector3(-0.32, 1.42, 0.2), -50.0, -30.0), "hand_l": _h(Vector3(0.4, 1.2, 0.46), -10.0, 50.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.2, 0.22), "hips": Vector3(14, -10, 0), "spine": Vector3(4, -6, 0), "chest": Vector3(6, -18, 0),
			"neck": Vector3(-6, 6, 0), "head": Vector3(-10, 10, 0),
			"hand_r": _h(Vector3(-0.34, 1.42, 0.16), -50.0, -30.0), "hand_l": _h(Vector3(-0.04, 1.16, 0.6), -12.0, -50.0, Vector3(0.9, -0.2, 0.2)) }), "lin"),
		HHClipsShared.rkey(stop, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.205, 0.22), "hips": Vector3(14, -12, 0), "spine": Vector3(4, -7, 0), "chest": Vector3(6, -21, 0),
			"neck": Vector3(-6, 7, 0), "head": Vector3(-10, 11, 0),
			"hand_r": _h(Vector3(-0.34, 1.42, 0.16), -50.0, -30.0), "hand_l": _h(Vector3(-0.1, 1.15, 0.58), -13.0, -58.0, Vector3(0.9, -0.2, 0.2)) })),
		HHClipsShared.rkey(bt.over, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.21, 0.21), "hips": Vector3(14, -22, 0), "spine": Vector3(4, -10, 0), "chest": Vector3(6, -34, 0),
			"neck": Vector3(-6, 12, 0), "head": Vector3(-10, 20, 0),
			"hand_r": _h(Vector3(-0.4, 1.3, 0.06), -60.0, -40.0), "hand_l": _h(Vector3(-0.38, 1.08, 0.36), -22.0, -100.0, Vector3(0.9, -0.2, 0.2)) }), "over"),
		HHClipsShared.rkey(bt.settle, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.22, 0.21), "hips": Vector3(14, -20, 0), "spine": Vector3(4, -9, 0), "chest": Vector3(6, -30, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-10, 18, 0),
			"hand_r": _h(Vector3(-0.4, 1.28, 0.06), -60.0, -40.0), "hand_l": _h(Vector3(-0.36, 1.06, 0.34), -26.0, -96.0, Vector3(0.9, -0.2, 0.2)) })),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(ready2(), { "move:root": Vector3(0, -0.24, 0.18), "hips": Vector3(16, -6, 0), "chest": Vector3(8, -8, 0),
			"hand_l": _h(Vector3(0.0, 1.06, 0.28), -60.0, -20.0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(ready2(), { "move:root": Vector3(0, -0.2, 0.0) })),
		HHClipsShared.rkey(bt.end, ready2()),
	]
	var p := HHClipsShared.sample(t, keys)
	var fl := HHClipsShared.plant(t, [[0, 0, PLANT_L], [lift, down, PLANT_L + Vector3(0, 0, 0.2), 0.32], [bt.hop_start + 0.02, bt.hop_end, PLANT_L]])
	var fr := HHClipsShared.plant(t, [[0, 0, PLANT_R], [lift + 0.01, down + 0.01, PLANT_R + Vector3(0, 0, 0.2), 0.36], [bt.hop_start, bt.hop_end, PLANT_R]])
	p["foot_l"] = fl
	p["foot_r"] = fr
	# the turn: the whole figure, clockwise seen from above, only off the ground
	# (the turn starts and ends a frame inside the air time: a foot on the floor never twists)
	var t0 := lift + 0.025
	var t1 := down - 0.015
	var yaw := -360.0 * HHClipsShared.ease_u(clampf((t - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0), "lin")
	HHClipsShared.apply(b, HHClipsShared.rotate_pose(p, yaw))
	HHClipsShared.impact(b, t, bt.hit, 0.25, 2.5, 18.0)


## HIT 3, the pounce (wind-up 10, recovery 16: the finisher). From B|W
## anim_skill leap (crouch and load, spring, tucked, a deep squashed
## landing held a beat, rise) with strike_axe's over-the-top line, both
## blades: they come down crossed in an X on the landing and are ripped
## open (the follow-through), then the hop home to the crouch.
static func _combo_pounce(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(10, 13, 0)
	bt.settle = 0.55                             # the X holds longer than the reference (review round 2)
	bt.hop_start = 0.63
	bt.hop_end = 0.69
	var r2 := ready2()
	var w := _wr()
	var apex := lerpf(bt.launch, bt.land, 0.5)
	var bounce := lerpf(bt.hop_end, bt.end, 0.5)
	var keys := [
		HHClipsShared.rkey(0.0, r2),
		HHClipsShared.rkey(bt.coil, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.4, -0.08), "hips": Vector3(36, 0, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(14, 0, 0),
			"neck": Vector3(-10, 0, 0), "head": Vector3(-16, 0, 0),
			"hand_r": _h(Vector3(-0.4, 0.92, -0.2), -70.0, -40.0), "hand_l": _h(Vector3(0.4, 0.92, -0.2), -70.0, 40.0) }), "coil"),
		HHClipsShared.rkey(bt.launch, HHClipsShared.merge(r2, { "move:root": Vector3(0, 0.08, 0.14), "hips": Vector3(6, 0, 0), "spine": Vector3(-2, 0, 0), "chest": Vector3(-10, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_r": _h(Vector3(-0.26, 1.9, 0.0), 70.0, -20.0), "hand_l": _h(Vector3(0.26, 1.9, 0.0), 70.0, 20.0) }), "snap"),
		HHClipsShared.rkey(apex, HHClipsShared.merge(r2, { "move:root": Vector3(0, 0.26, 0.32), "hips": Vector3(14, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(-16, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-8, 0, 0),
			"hand_r": _h(Vector3(-0.24, 2.05, -0.04), 80.0, -10.0), "hand_l": _h(Vector3(0.24, 2.05, -0.04), 80.0, 10.0) })),
		HHClipsShared.rkey(bt.land, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.16, 0.48), "hips": Vector3(20, 0, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(2, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-10, 0, 0),
			"hand_r": _h(Vector3(-0.12, 1.6, 0.38), 10.0, 20.0), "hand_l": _h(Vector3(0.12, 1.6, 0.38), 10.0, -20.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.38, 0.5), "hips": Vector3(32, 0, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(10, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.16, 1.32, 0.6), "", HHClipsShared.aim(-45.0, 40.0, 180.0)), "hand_l": HHClipsShared.hand(Vector3(-0.16, 1.28, 0.64), "", HHClipsShared.aim(-45.0, -40.0, 180.0)) }), "snap"),
		HHClipsShared.rkey(bt.stop, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.39, 0.5), "hips": Vector3(32, 0, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(10, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.17, 1.31, 0.6), "", HHClipsShared.aim(-46.0, 42.0, 180.0)), "hand_l": HHClipsShared.hand(Vector3(-0.17, 1.27, 0.64), "", HHClipsShared.aim(-46.0, -42.0, 180.0)) })),
		HHClipsShared.rkey(bt.over, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.38, 0.48), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(6, 0, 0),
			"neck": Vector3(-8, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_r": _h(Vector3(-0.56, 1.1, 0.32), -40.0, -90.0), "hand_l": _h(Vector3(0.56, 1.1, 0.32), -40.0, 90.0) }), "over"),
		HHClipsShared.rkey(bt.settle, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.39, 0.48), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(7, 0, 0),
			"neck": Vector3(-8, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_r": _h(Vector3(-0.54, 1.08, 0.3), -44.0, -84.0), "hand_l": _h(Vector3(0.54, 1.08, 0.3), -44.0, 84.0) })),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.3, 0.4), "hips": Vector3(20, 0, 0), "chest": Vector3(4, 0, 0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.12, 0.04) })),
		HHClipsShared.rkey(bounce, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.17, 0.0) })),
		HHClipsShared.rkey(bt.end, w),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L], [bt.launch - 0.015, bt.land, Vector3(0.32, A, 0.76), 0.4], [bt.hop_start, bt.hop_end, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, bt.land + 0.01, Vector3(-0.3, A, 0.26), 0.45], [bt.hop_start + 0.01, bt.hop_end + 0.01, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.4, 4.0, 14.0)
