class_name HHClipsDaggers
extends RefCounted
## The dual-dagger clip set (Lane B): sword-sized karambits, one per hand
## (socket_weapon_r + socket_offhand_l), reverse grip so the blades run down
## the forearms. Low, wide, quick: contact at tick 5 (0.17 s) on the basic.
## The anticipation is a tight coil, the release a lunge, the follow-through
## a wide arm that re-centres.

const A := HHClipsShared.ANKLE_Y

const CLIPS := {
	"idle":        { "duration": 7.2, "contact_tick": -1, "loop": true,  "key": 0.9, "note": "H491: grounded, wide and low, torso forward, both blades up in front across the body in a guard; breathing through the knees" },
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
	# H60 (Lane X): the string, one dedicated clip per hit timed to the sim (see HHClipsLance for the row fields);
	# H70 (Lane X2): every hit spins, each more than the last (`spin` = degrees turned, all in the air)
	"combo_whirl":       { "duration": 0.5, "contact_tick": 5, "recovery": 5, "timed": true, "loop": false, "key": 0.3, "spin": 360, "trail": [0.12, 0.34, 0.7, "both", 0.14],
		"note": "string hit 1: the right blade cuts across on a lunge, and the cut carries her into a full airborne turn, blades out, down into the crouch" },
	"combo_double_spin": { "duration": 0.6, "contact_tick": 7, "recovery": 11, "timed": true, "loop": false, "key": 0.16, "spin": 720, "trail": [0.06, 0.42, 1.1, "both", 0.16],
		"note": "string hit 2: springs from the crouch into two airborne turns, the left blade whipping across the front on the first" },
	"combo_tornado":     { "duration": 0.77, "contact_tick": 10, "recovery": 16, "timed": true, "loop": false, "key": 0.22, "spin": 1080, "trail": [0.12, 0.56, 1.6, "both", 0.2],
		"note": "string finisher: wound tight, she drills up through two turns, crosses the blades in an X at the top, a third turn down into a deep landing" },
	"combo_ready":       { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits: crouched to spring, blades low and back" },
}
const SKILL_CLIPS := { "q": "flourish", "w": "swap", "e": "dive", "r": "jump" }   # H56: Q is the Flourish, E the Daggerleap (they were crossed)
const WINDUP_CLIPS := { "basic": "strike", "dive": "dive", "flourish": "flourish", "exchange": "swap" }
## H57: the basic string; H60: one dedicated clip per hit; H70: whirl, double spin, tornado; one ready loop between hits.
const COMBO_CLIPS := { 1: "combo_whirl", 2: "combo_double_spin", 3: "combo_tornado" }
const READY_CLIPS := { 1: "combo_ready", 2: "combo_ready" }
## H56: the held charge pose.
const CHARGE_CLIP := "flourish"
const LANDING_CLIPS := { "jump": "jump_attack" }


static func pose(clip: String, t: float, b: HHPlayerBody) -> void:
	match clip:
		"idle": HHClipsShared.stance(t, b, stance(), 0.012)
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
		"combo_whirl": _combo_whirl(t, b)
		"combo_double_spin": _combo_double_spin(t, b)
		"combo_tornado": _combo_tornado(t, b)
		"combo_ready": HHClipsShared.ready_loop(t, b, ready_pose())


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


## H491 (Lane ST, the author's reference): the idle stance. Grounded: feet
## wide, knees well bent, the torso leaning over them, the left side leading;
## both fists up in front, reverse grip, the blades crossing the body (the
## lead blade angled across to the right, the rear one across to the left).
static func stance() -> Dictionary:
	return {
		"move:root": Vector3(0, -0.32, 0.02),
		"hips": Vector3(24, 12, 0), "spine": Vector3(10, 4, 0), "chest": Vector3(10, 6, 0),
		"neck": Vector3(-16, -6, 0), "head": Vector3(-20, -8, 0),
		"foot_l": [Vector3(0.40, A, 0.40), 0.0], "foot_r": [Vector3(-0.38, A, -0.34), 0.0],
		"hand_l": HHClipsShared.hand(Vector3(0.1, 1.28, 0.52), "", HHClipsShared.aim(-8.0, -70.0)),
		"hand_r": HHClipsShared.hand(Vector3(-0.16, 1.12, 0.4), "", HHClipsShared.aim(0.0, 55.0)),
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


# ------------------------------------------------------------------ the string (H60 Lane X, H70 Lane X2)
# Three hits on Black | White's strike rig with the H70 spins: every hit
# turns, each more than the last (one turn, two, three), alternating
# directions. The turns are all in the air; hits 2 and 3 start from the
# same crouch (combo_ready), and every hit lands on it or on the guard.

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


static func _h(pos: Vector3, pitch: float, yaw: float, roll: float = 0.0, pole: Variant = null) -> Dictionary:
	return HHClipsShared.hand(pos, "", HHClipsShared.aim(pitch, yaw, roll), pole)


static func _k(t: float, base: Dictionary, over: Dictionary, ease_kind: String = "ss") -> Dictionary:
	return HHClipsShared.rkey(t, HHClipsShared.merge(base, over), ease_kind)


## Blades out level at both sides: the spinning-top silhouette.
static func _out() -> Dictionary:
	return { "hand_r": _h(Vector3(-0.64, 1.42, 0.02), -4.0, -95.0, 180.0), "hand_l": _h(Vector3(0.64, 1.42, 0.02), -4.0, 95.0, 180.0) }


## Between hits (H70: one shared stance): crouched to spring, blades low and back.
static func ready_pose() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.24, -0.04),
		"hips": Vector3(20, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(10, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-14, 0, 0),
		"hand_r": _h(Vector3(-0.36, 1.0, -0.1), -80.0, -30.0), "hand_l": _h(Vector3(0.36, 1.0, -0.1), -80.0, 30.0) })


## HIT 1, the whirl (wind-up 5, recovery 5; one turn, to her left). From
## B|W _strike_pair (a low coil, the right blade back, a cross-cut on the
## hit) with _strike_one's free arm; H70: the cut's momentum carries her
## off the floor into a full turn (B|W _strike_spin, the head spotting),
## blades out level, landing in the crouch the next hit springs from.
static func _combo_whirl(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(5, 5, 4)
	var w := _wr()
	var stop: float = bt.hit + HHClipsShared.T
	var lift := 0.205
	var land := 0.43
	var keys := [
		HHClipsShared.rkey(0.0, w),
		_k(bt.coil, w, { "move:root": Vector3(0.03, -0.2, -0.05), "hips": Vector3(14, -18, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -26, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-12, 20, 0),
			"hand_r": _h(Vector3(-0.56, 1.55, -0.12), 30.0, -120.0, 180.0), "hand_l": _h(Vector3(0.3, 1.22, 0.42), -55.0, 20.0) }, "coil"),
		_k(bt.launch, w, { "move:root": Vector3(0.02, -0.23, -0.03), "hips": Vector3(14, -16, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -24, 0),
			"neck": Vector3(-6, 10, 0), "head": Vector3(-12, 20, 0),
			"hand_r": _h(Vector3(-0.54, 1.55, -0.08), 26.0, -110.0, 180.0), "hand_l": _h(Vector3(0.3, 1.22, 0.42), -55.0, 20.0) }),
		_k(bt.land, w, { "move:root": Vector3(0.0, -0.18, 0.18), "hips": Vector3(12, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, -4, 0),
			"neck": Vector3(-6, 2, 0), "head": Vector3(-10, 4, 0),
			"hand_r": _h(Vector3(-0.3, 1.42, 0.4), 0.0, -30.0, 180.0), "hand_l": _h(Vector3(0.38, 1.16, 0.2), -62.0, 24.0) }, "lin"),
		_k(bt.hit, w, { "move:root": Vector3(-0.02, -0.18, 0.28), "hips": Vector3(10, 26, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 40, 0),
			"neck": Vector3(-2, -10, 0), "head": Vector3(-8, -16, 0),
			"hand_r": _h(Vector3(0.14, 1.3, 0.6), -20.0, 55.0, 180.0, Vector3(-0.9, -0.2, 0.2)), "hand_l": _h(Vector3(0.44, 1.14, -0.08), -70.0, 30.0) }, "lin"),
		_k(stop, w, { "move:root": Vector3(-0.025, -0.185, 0.285), "hips": Vector3(10, 27, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 42, 0),
			"neck": Vector3(-2, -10, 0), "head": Vector3(-8, -16, 0),
			"hand_r": _h(Vector3(0.18, 1.29, 0.59), -21.0, 62.0, 180.0, Vector3(-0.9, -0.2, 0.2)), "hand_l": _h(Vector3(0.45, 1.14, -0.1), -70.0, 30.0) }),
		_k(lift, w, { "move:root": Vector3(-0.02, -0.1, 0.24), "hips": Vector3(8, 30, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 44, 0),
			"neck": Vector3(-2, -16, 0), "head": Vector3(-8, -24, 0),
			"hand_r": _h(Vector3(0.46, 1.3, 0.36), -12.0, 96.0, 180.0), "hand_l": _h(Vector3(0.5, 1.3, -0.24), -20.0, 120.0) }),
		_k(0.3, HHClipsShared.merge(w, _out()), { "move:root": Vector3(0, 0.22, 0.14), "hips": Vector3(4, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }),
		_k(land, ready_pose(), { "move:root": Vector3(0, -0.32, 0.02), "hips": Vector3(24, 0, 0) }, "lin"),
		HHClipsShared.rkey(0.5, ready_pose()),
	]
	HHClipsShared.spin_hit(t, b, keys,
		[[0, 0, PLANT_L], [bt.coil, bt.hit, Vector3(0.26, A, 0.5)], [lift, land, PLANT_L, 0.36]],
		[[0, 0, PLANT_R], [bt.launch, stop, Vector3(-0.28, A, -0.04)], [lift + 0.005, land + 0.005, PLANT_R, 0.4]],
		[[lift + 0.025, land - 0.015, 360.0]], bt.hit, 0.2, 2.0, 18.0)


## HIT 2, the double spin (wind-up 7, recovery 11; two turns, to her
## right). From the crouch she springs into a full airborne turn (B|W
## _strike_spin, pair: the left blade rides the leading side and whips
## across the front on the hit), still in the air at the contact, and a
## second turn carries her down to land in the crouch exactly when hit 3's
## wind-up starts (hit 2's recovery ends on it).
static func _combo_double_spin(t: float, b: HHPlayerBody) -> void:
	var r := ready_pose()
	var hit := 0.233
	var lift := 0.06
	var land := 0.46
	var keys := [
		HHClipsShared.rkey(0.0, r),
		_k(0.045, r, { "move:root": Vector3(0, -0.32, -0.04), "hips": Vector3(26, 20, 0), "chest": Vector3(12, 26, 0), "head": Vector3(-14, -20, 0) }, "coil"),
		_k(0.08, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.06, 0.06), "hips": Vector3(6, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }, "snap"),
		_k(0.16, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.3, 0.16), "hips": Vector3(6, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }),
		_k(hit, r, { "move:root": Vector3(0, 0.3, 0.22), "hips": Vector3(8, -14, 0), "spine": Vector3(4, -6, 0), "chest": Vector3(4, -20, 0),
			"neck": Vector3(-6, 6, 0), "head": Vector3(-10, 10, 0),
			"hand_r": _h(Vector3(-0.34, 1.46, 0.14), -50.0, -30.0), "hand_l": _h(Vector3(-0.06, 1.36, 0.6), -12.0, -50.0, 180.0, Vector3(0.9, -0.2, 0.2)) }, "lin"),
		_k(hit + 0.05, r, { "move:root": Vector3(0, 0.3, 0.22), "hips": Vector3(8, -18, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(4, -26, 0),
			"neck": Vector3(-6, 8, 0), "head": Vector3(-10, 12, 0),
			"hand_r": _h(Vector3(-0.34, 1.46, 0.14), -50.0, -30.0), "hand_l": _h(Vector3(-0.2, 1.34, 0.56), -14.0, -66.0, 180.0, Vector3(0.9, -0.2, 0.2)) }),
		_k(0.35, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.26, 0.14), "hips": Vector3(8, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }),
		_k(land, r, { "move:root": Vector3(0, -0.34, 0.02), "hips": Vector3(26, 0, 0) }, "lin"),
		_k(0.53, r, { "move:root": Vector3(0, -0.28, -0.03) }),
		HHClipsShared.rkey(0.6, r),
	]
	HHClipsShared.spin_hit(t, b, keys,
		[[0, 0, PLANT_L], [lift, land, PLANT_L, 0.4]],
		[[0, 0, PLANT_R], [lift + 0.005, land + 0.005, PLANT_R, 0.44]],
		[[lift + 0.025, hit - 0.01, -360.0], [hit + 0.04, land - 0.015, -360.0]], hit, 0.25, 2.5, 18.0)


## HIT 3, the tornado (wind-up 10, recovery 16: the finisher; three
## turns, to her left). Wound tight in a deep crouch, arms wrapped (B|W
## leap's load), she launches and drills UP through two turns with the
## blades out level, crosses them in an X on the contact at the top, and
## a third turn brings her down into a deep squashed landing (B|W leap)
## with the blades ripped open; held, then home to the guard.
static func _combo_tornado(t: float, b: HHPlayerBody) -> void:
	var r := ready_pose()
	var w := _wr()
	var hit := 0.333
	var lift := 0.1
	var land := 0.55
	var keys := [
		HHClipsShared.rkey(0.0, r),
		_k(0.075, r, { "move:root": Vector3(0, -0.42, -0.06), "hips": Vector3(34, -30, 0), "spine": Vector3(12, -10, 0), "chest": Vector3(14, -30, 0),
			"neck": Vector3(-10, 20, 0), "head": Vector3(-16, 30, 0),
			"hand_r": _h(Vector3(0.22, 1.3, 0.22), -60.0, 60.0), "hand_l": _h(Vector3(-0.22, 1.32, 0.26), -60.0, -60.0) }, "coil"),
		_k(lift + 0.02, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.08, 0.08), "hips": Vector3(4, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(-6, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }, "snap"),
		_k(0.22, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.46, 0.26), "hips": Vector3(0, 0, 0), "spine": Vector3(-2, 0, 0), "chest": Vector3(-8, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }),
		_k(hit, r, { "move:root": Vector3(0, 0.6, 0.38), "hips": Vector3(10, 0, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(6, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_r": _h(Vector3(0.16, 1.34, 0.6), -45.0, 40.0, 180.0), "hand_l": _h(Vector3(-0.16, 1.3, 0.64), -45.0, -40.0, 180.0) }, "snap"),
		_k(hit + 0.05, r, { "move:root": Vector3(0, 0.62, 0.38), "hips": Vector3(10, 0, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(6, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_r": _h(Vector3(0.17, 1.33, 0.6), -46.0, 42.0, 180.0), "hand_l": _h(Vector3(-0.17, 1.29, 0.64), -46.0, -42.0, 180.0) }),
		_k(0.46, HHClipsShared.merge(r, _out()), { "move:root": Vector3(0, 0.36, 0.38), "hips": Vector3(8, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0) }),
		_k(land, r, { "move:root": Vector3(0, -0.42, 0.42), "hips": Vector3(32, 0, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-8, 0, 0), "head": Vector3(-14, 0, 0),
			"hand_r": _h(Vector3(-0.56, 1.1, 0.32), -40.0, -90.0), "hand_l": _h(Vector3(0.56, 1.1, 0.32), -40.0, 90.0) }, "snap"),
		_k(0.62, r, { "move:root": Vector3(0, -0.39, 0.42), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(7, 0, 0),
			"neck": Vector3(-8, 0, 0), "head": Vector3(-12, 0, 0),
			"hand_r": _h(Vector3(-0.54, 1.08, 0.3), -44.0, -84.0), "hand_l": _h(Vector3(0.54, 1.08, 0.3), -44.0, 84.0) }),
		_k(0.665, w, { "move:root": Vector3(0, -0.3, 0.34), "hips": Vector3(20, 0, 0), "chest": Vector3(4, 0, 0) }),
		_k(0.71, w, { "move:root": Vector3(0, -0.12, 0.04) }),
		_k(0.74, w, { "move:root": Vector3(0, -0.17, 0.0) }),
		HHClipsShared.rkey(0.77, w),
	]
	HHClipsShared.spin_hit(t, b, keys,
		[[0, 0, PLANT_L], [lift, land, Vector3(0.32, A, 0.68), 0.75], [0.665, 0.71, PLANT_L]],
		[[0, 0, PLANT_R], [lift + 0.005, land + 0.008, Vector3(-0.3, A, 0.2), 0.8], [0.67, 0.715, PLANT_R]],
		[[lift + 0.025, hit - 0.01, 720.0], [hit + 0.04, land - 0.02, 360.0]], hit, 0.3, 3.0, 14.0)
	HHClipsShared.impact(b, t, land, 0.35, 3.5, 12.0)
