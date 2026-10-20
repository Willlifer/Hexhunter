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
}
const SKILL_CLIPS := { "q": "flourish", "w": "swap", "e": "dive", "r": "jump" }   # H56: Q is the Flourish, E the Daggerleap (they were crossed)
const WINDUP_CLIPS := { "basic": "strike", "dive": "dive", "flourish": "flourish", "exchange": "swap" }
## H57: the basic string (cross slash, reverse spin, leaping double stab); H56: the held charge pose.
const COMBO_CLIPS := { 1: "strike", 2: "spin", 3: "jump_attack" }
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
