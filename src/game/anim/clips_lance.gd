class_name HHClipsLance
extends RefCounted
## The lance clip set (Lane B). Two-handed: the right fist at the vamplate
## (socket_weapon_r), the left hand IK'd 0.4 m up the shaft. The stance is
## side-on, left foot forward, the lance level at chest height: every blow
## is a weight transfer from the back foot through the hips into the point.
##
## CLIPS: { name: { duration (s), contact_tick (30 Hz tick when damage lands;
## -1 none), loop, key (preview moment), stride (m per cycle, loops), note } }.
## Wind-ups (strike 12 ticks, plant 10: H34) hold their anticipation at the
## contact pose until the sim's strike / pierce event releases them.

const A := HHClipsShared.ANKLE_Y
const GRIP_L := Vector3(0.0, 0.4, 0.0)        ## the left hand on the shaft (socket_weapon_r frame)

const CLIPS := {
	"idle":        { "duration": 7.2, "contact_tick": -1, "loop": true,  "key": 0.9, "note": "H490: upright, weight on the right leg, the glaive low in the right hand trailing behind, blade near the ground, wound to spin forward; breathing, weight shifting" },
	"wield_idle":  { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "side-on guard, lance level at the chest, point on the target" },
	"walk":        { "duration": 0.436, "contact_tick": -1, "loop": true, "key": 0.1, "stride": 2.4, "note": "5.5 m/s jog, lance couched low at the hip" },
	"run":         { "duration": 0.4325, "contact_tick": -1, "loop": true, "key": 0.05, "stride": 3.46, "note": "8 m/s, 1.73 m steps, lance couched, left arm pumps" },
	"strike":      { "duration": 1.0, "contact_tick": 12, "loop": false, "key": 0.42, "note": "the basic: coil back over the rear foot (0-0.3), thrust (0.3-0.4), held point with shudder, recover" },
	"sweep":       { "duration": 1.1, "contact_tick": 14, "loop": false, "key": 0.47, "note": "wind to the right, a level cut across, follow-through to the left" },
	"spin":        { "duration": 1.2, "contact_tick": 16, "loop": false, "key": 0.53, "note": "hop-spin, the lance out at hip height, faces front at contact" },
	"jump":        { "duration": 0.87, "contact_tick": -1, "loop": false, "key": 0.45, "note": "the vault (Eruption's air): plants the lance, legs tuck over it, lance comes overhead for the slam" },
	"jump_attack": { "duration": 0.9, "contact_tick": 5, "loop": false, "key": 0.2, "note": "landing thrust down-forward" },
	"plant":       { "duration": 1.0, "contact_tick": 10, "loop": false, "key": 0.35, "note": "Pierce: the lance drawn far back and low, a long lunge, held" },
	"slam":        { "duration": 1.1, "contact_tick": 4, "loop": false, "key": 0.16, "note": "Eruption landing: crouch hard, drive the point into the ground, the shock rises through the body" },
	"guard":       { "duration": 1.2, "contact_tick": -1, "loop": true,  "key": 0.4, "note": "the lance braced level across the chest, low stance, tense" },
	"swap":        { "duration": 0.9, "contact_tick": -1, "loop": false, "key": 0.4, "note": "Elemental Exchange: plants the lance, a hand to the chest, a bow of the head" },
	"stagger":     { "duration": 1.0, "contact_tick": -1, "loop": false, "key": 0.3, "note": "knocked back a step, arms flail, slow recover" },
	"hit_react":   { "duration": 0.45, "contact_tick": -1, "loop": false, "key": 0.08, "note": "flinch" },
	"death":       { "duration": 1.5, "contact_tick": -1, "loop": false, "key": 1.3, "note": "knees go, falls onto the back, holds" },
	"dash":        { "duration": 0.36, "contact_tick": -1, "loop": false, "key": 0.12, "note": "H56: the dash, a low forward burst, the weapon trailing" },
	# H60 (Lane X): the string, one dedicated clip per hit, timed to the sim (contact_tick = the hit's wind-up,
	# `recovery` = its recovery ticks, `timed`: plays at full rate through the recovery: the follow-through is keyed);
	# `trail` = [from s, to s, strength, blades] for the swing ribbon; `spin` = degrees turned (H70, Lane X2: the
	# strings spin, each hit more than the last); one ready loop holds between hits
	"combo_stab":      { "duration": 0.9, "contact_tick": 12, "recovery": 5, "timed": true, "loop": false, "key": 0.4, "spin": 0, "trail": [0.33, 0.5, 0.6, "main"],
		"note": "string hit 1: wound right, a stepping lunge, the stab straight down the line, hit-stop, hop home" },
	"combo_leap_slam": { "duration": 1.1, "contact_tick": 14, "recovery": 12, "timed": true, "loop": false, "key": 0.33, "spin": 360, "trail": [0.22, 0.56, 1.3, "main", 0.25],
		"note": "string hit 2: the lance pulled back over the shoulder, a leap with a full turn in the air, slammed down on the landing" },
	"combo_spiral":    { "duration": 1.1, "contact_tick": 18, "recovery": 17, "timed": true, "loop": false, "key": 0.53, "spin": 720, "trail": [0.3, 0.8, 1.8, "main", 0.25],
		"note": "string finisher: crouch, then a rising corkscrew, the lance spiralling up through the target, a second turn on the fall, a big landing" },
	"combo_ready":     { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits: low and loaded, the lance drawn back at the hip, breathing hard" },
	"brace":        { "duration": 1.0, "contact_tick": -1, "loop": true, "key": 0.5, "note": "H60: the charged Pierce held: wide, low, planted, the shaft drawn back; trembles harder as the charge builds" },
}
const SKILL_CLIPS := { "q": "plant", "w": "swap", "e": "guard", "r": "jump" }
const WINDUP_CLIPS := { "basic": "strike", "pierce": "plant", "exchange": "swap" }
## H57: the basic string; H60: one dedicated clip per hit; H70: stab, leaping 360 slam, rising spiral; one ready loop between hits.
const COMBO_CLIPS := { 1: "combo_stab", 2: "combo_leap_slam", 3: "combo_spiral" }
const READY_CLIPS := { 1: "combo_ready", 2: "combo_ready" }
## H56: the held charge pose; H60: the brace loop, released into the plant from its coil.
const CHARGE_CLIP := "brace"
const CHARGE_FROM := { "plant": 0.26 }
const LANDING_CLIPS := { "jump": "slam" }


static func pose(clip: String, t: float, b: HHPlayerBody) -> void:
	match clip:
		"idle": HHClipsShared.stance(t, b, stance())
		"wield_idle": _wield_idle(t, b)
		"walk": HHClipsShared.walk(t, b, carry_run(), 1.0, 0.0)
		"run": HHClipsShared.run(t, b, carry_run(), 1.0, 0.0)
		"strike": _strike(t, b)
		"sweep": _sweep(t, b)
		"spin": _spin(t, b)
		"jump": _jump(t, b)
		"jump_attack": _jump_attack(t, b)
		"plant": _plant(t, b)
		"slam": _slam(t, b)
		"guard": _guard(t, b)
		"swap": _swap(t, b)
		"stagger": HHClipsShared.stagger(t, b, wield())
		"hit_react": HHClipsShared.hit_react(t, b, wield())
		"death": HHClipsShared.death(t, b, wield())
		"dash": HHClipsShared.dash(t, b, carry_run())
		"combo_stab": _combo_stab(t, b)
		"combo_leap_slam": _combo_leap_slam(t, b)
		"combo_spiral": _combo_spiral(t, b)
		"combo_ready": HHClipsShared.ready_loop(t, b, ready_pose())
		"brace": _brace(t, b)


# ------------------------------------------------------------------ poses

## Relaxed carry: the lance over the right shoulder, the left arm hanging.
static func carry_idle() -> Dictionary:
	return {
		"hand_r": HHClipsShared.hand(Vector3(-0.24, 1.38, 0.22), "", HHClipsShared.aim(62.0, 180.0)),
		"upper_arm_l": Vector3(2, 0, -22), "forearm_l": Vector3(-12, 0, 0),
	}


## H490 (Lane ST, the author's reference): the idle stance. Tall and easy,
## weight on the right leg (the left hip drops, the left foot rests ahead),
## the glaive in the right hand alone, held low and trailing behind her with
## the blade near the ground, the chest wound a touch to the right: the spin
## forward (combo_stab's unwind) is loaded. The left arm hangs loose.
static func stance() -> Dictionary:
	return {
		"move:root": Vector3(-0.07, -0.05, 0.0),
		"hips": Vector3(0, -10, -10), "spine": Vector3(-2, -5, 7), "chest": Vector3(-5, -14, 4),
		"neck": Vector3(-2, 12, -2), "head": Vector3(-4, 14, -4),
		"foot_l": [Vector3(0.25, A + 0.03, 0.34), 14.0], "foot_r": [Vector3(-0.12, A, -0.08), 0.0],
		"hand_r": HHClipsShared.hand(Vector3(-0.30, 0.94, -0.1), "", HHClipsShared.aim(-26.0, -158.0)),
		"upper_arm_l": Vector3(-4, 0, -16), "forearm_l": Vector3(-24, 0, 0),
	}


## Running carry: couched low at the right hip, point forward-up.
static func carry_run() -> Dictionary:
	return {
		"hand_r": HHClipsShared.hand(Vector3(-0.24, 0.98, 0.12), "", HHClipsShared.aim(22.0, -4.0)),
	}


## The guard stance: side-on, left foot forward, lance level at the chest.
static func wield() -> Dictionary:
	return {
		"move:root": Vector3(0, -0.05, 0),
		"hips": Vector3(0, 18, 0), "spine": Vector3(2, 8, 0), "chest": Vector3(4, 12, 0),
		"neck": Vector3(0, -10, 0), "head": Vector3(-2, -14, 0),
		"foot_l": [Vector3(0.2, A, 0.3), 0.0], "foot_r": [Vector3(-0.22, A, -0.3), 0.0],
		"hand_r": HHClipsShared.hand(Vector3(-0.14, 1.26, -0.12), "", HHClipsShared.aim(3.0, 0.0)),
		"hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r"),
	}


static func _wield_idle(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.apply(b, wield())
	HHClipsShared.breath(b, t, 3.0, 0.8)
	var s := sin(TAU * t / 3.0)
	b.move("root", Vector3(0.0, -0.01 * s, 0.015 * s))         # weight rocks front foot / back foot
	b.rot("hips", Vector3(0.0, 2.0 * s, 0.0))


# ------------------------------------------------------------------ attacks

static func _strike(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.3, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.08, -0.12), "hips": Vector3(0, 30, 0), "spine": Vector3(2, 12, 0), "chest": Vector3(2, 24, 0),
			"neck": Vector3(0, -22, 0), "head": Vector3(-2, -28, 0),
			"foot_l": [Vector3(0.2, A, 0.22), 0.0], "foot_r": [Vector3(-0.22, A, -0.4), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.2, 1.3, -0.42), "", HHClipsShared.aim(8.0, -5.0)) }), "coil"),
		HHClipsShared.key(0.4, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.09, 0.3), "hips": Vector3(6, -6, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -16, 0),
			"neck": Vector3(-4, 6, 0), "head": Vector3(-6, 10, 0),
			"foot_l": [Vector3(0.2, A, 0.7), 0.0], "foot_r": [Vector3(-0.22, A, -0.25), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.04, 1.22, 0.56), "", HHClipsShared.aim(-4.0, 0.0)) }), "snap"),
		HHClipsShared.key(0.52, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.1, 0.36), "hips": Vector3(8, -8, 0), "spine": Vector3(5, -9, 0), "chest": Vector3(8, -18, 0),
			"neck": Vector3(-4, 6, 0), "head": Vector3(-6, 10, 0),
			"foot_l": [Vector3(0.2, A, 0.7), 0.0], "foot_r": [Vector3(-0.22, A, -0.25), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.03, 1.2, 0.6), "", HHClipsShared.aim(-7.0, 0.0)) })),
		HHClipsShared.key(1.0, w),
	]
	HHClipsShared.keyed(t, keys, b)
	var sh := HHClipsShared.shake(t, 0.4, 0.3, 14.0)
	b.rot("chest", Vector3(2.0 * sh, 0.0, 0.0))
	b.rot("head", Vector3(3.0 * sh, 0.0, 0.0))


static func _sweep(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.32, HHClipsShared.merge(w, { "move:root": Vector3(0.05, -0.08, -0.08), "hips": Vector3(0, 40, 0), "spine": Vector3(2, 16, 0), "chest": Vector3(2, 26, 0),
			"neck": Vector3(0, -28, 0), "head": Vector3(-2, -34, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.32, 1.22, -0.25), "", HHClipsShared.aim(2.0, -85.0)) }), "coil"),
		HHClipsShared.key(0.467, HHClipsShared.merge(w, { "move:root": Vector3(-0.05, -0.1, 0.12), "hips": Vector3(4, -10, 0), "spine": Vector3(2, -10, 0), "chest": Vector3(4, -18, 0),
			"neck": Vector3(0, 8, 0), "head": Vector3(-2, 10, 0),
			"foot_l": [Vector3(0.22, A, 0.4), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.08, 1.15, 0.36), "", HHClipsShared.aim(-5.0, 8.0)) }), "snap"),
		HHClipsShared.key(0.64, HHClipsShared.merge(w, { "move:root": Vector3(-0.1, -0.1, 0.1), "hips": Vector3(4, -30, 0), "spine": Vector3(2, -18, 0), "chest": Vector3(4, -30, 0),
			"neck": Vector3(0, 14, 0), "head": Vector3(-2, 20, 0),
			"foot_l": [Vector3(0.22, A, 0.4), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.3, 1.12, 0.12), "", HHClipsShared.aim(-6.0, 62.0)) })),
		HHClipsShared.key(1.1, w),
	]
	HHClipsShared.keyed(t, keys, b)
	b.rot("chest", Vector3(0.0, 0.0, 2.5 * HHClipsShared.shake(t, 0.467, 0.25, 12.0)))


## A hop-spin: the body turns a full circle with the lance out at hip
## height; the feet leave the ground, the point faces front at contact.
static func _spin(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var yaw := 0.0
	if t < 0.2:
		yaw = -50.0 * HHClipsShared.coil(t / 0.2)
	elif t < 0.533:
		yaw = lerpf(-50.0, 360.0, HHClipsShared.ease_u((t - 0.2) / 0.333, "lin"))
	else:
		yaw = 360.0
	var out := HHClipsShared.hand(Vector3(-0.42, 1.05, 0.05), "", HHClipsShared.aim(-6.0, -92.0))
	var air := HHClipsShared.ss(t, 0.2, 0.3) * (1.0 - HHClipsShared.ss(t, 0.5, 0.62))
	var base := HHClipsShared.merge(w, {
		"move:root": Vector3(0, -0.1 + 0.26 * air, 0.0),
		"hips": Vector3(6, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, 0, 0), "neck": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0),
		"hand_r": out,
	})
	if air > 0.01:
		base.erase("foot_l")
		base.erase("foot_r")
		base["thigh_l"] = Vector3(-45 * air, 0, 0)
		base["shin_l"] = Vector3(70 * air, 0, 0)
		base["thigh_r"] = Vector3(-35 * air, 0, 0)
		base["shin_r"] = Vector3(65 * air, 0, 0)
	var rotated := HHClipsShared.rotate_pose(base, yaw)
	var settle := HHClipsShared.ss(t, 0.62, 1.2)
	HHClipsShared.apply(b, HHClipsShared.mix(rotated, HHClipsShared.merge(w, { "root": Vector3(0, 360, 0) }), settle))


static func _jump(t: float, b: HHPlayerBody) -> void:
	var d := float(CLIPS.jump.duration)
	var keys := [
		HHClipsShared.key(0.0, { "move:root": Vector3(0, 0.0, 0), "hips": Vector3(14, 0, 0), "chest": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0),
			"thigh_l": Vector3(-35, 0, 0), "shin_l": Vector3(30, 0, 0), "thigh_r": Vector3(0, 0, 0), "shin_r": Vector3(40, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.12, 1.45, 0.3), "", HHClipsShared.aim(-62.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(d * 0.45, { "move:root": Vector3(0, 0.1, 0), "hips": Vector3(22, 0, 0), "chest": Vector3(-10, 0, 0), "head": Vector3(-10, 0, 0),
			"thigh_l": Vector3(-80, 0, 0), "shin_l": Vector3(100, 0, 0), "thigh_r": Vector3(-70, 0, 0), "shin_r": Vector3(105, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.12, 1.7, 0.1), "", HHClipsShared.aim(40.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(d, { "move:root": Vector3(0, 0.0, 0), "hips": Vector3(6, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-4, 0, 0),
			"thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(25, 0, 0), "thigh_r": Vector3(-30, 0, 0), "shin_r": Vector3(25, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 1.95, -0.05), "", HHClipsShared.aim(82.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
	]
	HHClipsShared.keyed(t, keys, b)


static func _jump_attack(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, { "hips": Vector3(6, 0, 0), "chest": Vector3(-14, 0, 0), "thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(25, 0, 0), "thigh_r": Vector3(-30, 0, 0), "shin_r": Vector3(25, 0, 0),
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 1.95, -0.05), "", HHClipsShared.aim(82.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(0.167, { "move:root": Vector3(0, -0.3, 0.1), "hips": Vector3(22, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(-10, 0, 0),
			"foot_l": [Vector3(0.24, A, 0.32), 0.0], "foot_r": [Vector3(-0.24, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.08, 1.0, 0.55), "", HHClipsShared.aim(-32.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }, "snap"),
		HHClipsShared.key(0.42, { "move:root": Vector3(0, -0.32, 0.12), "hips": Vector3(24, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(8, 0, 0), "head": Vector3(-10, 0, 0),
			"foot_l": [Vector3(0.24, A, 0.32), 0.0], "foot_r": [Vector3(-0.24, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.08, 0.98, 0.58), "", HHClipsShared.aim(-34.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(0.9, w),
	]
	HHClipsShared.keyed(t, keys, b)
	b.rot("chest", Vector3(3.0 * HHClipsShared.shake(t, 0.167, 0.3, 13.0), 0.0, 0.0))


static func _plant(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.26, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.14, -0.2), "hips": Vector3(2, 36, 0), "spine": Vector3(4, 14, 0), "chest": Vector3(4, 26, 0),
			"neck": Vector3(0, -26, 0), "head": Vector3(-4, -32, 0),
			"foot_l": [Vector3(0.2, A, 0.18), 0.0], "foot_r": [Vector3(-0.25, A, -0.52), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.22, 1.02, -0.58), "", HHClipsShared.aim(10.0, -4.0)) }), "coil"),
		HHClipsShared.key(0.333, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.14, 0.46), "hips": Vector3(10, -10, 0), "spine": Vector3(6, -10, 0), "chest": Vector3(8, -20, 0),
			"neck": Vector3(-6, 8, 0), "head": Vector3(-8, 12, 0),
			"foot_l": [Vector3(0.22, A, 0.88), 0.0], "foot_r": [Vector3(-0.24, A, -0.18), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.0, 1.15, 0.74), "", HHClipsShared.aim(-2.0, 0.0)) }), "snap"),
		HHClipsShared.key(0.5, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.15, 0.5), "hips": Vector3(12, -12, 0), "spine": Vector3(6, -10, 0), "chest": Vector3(10, -22, 0),
			"neck": Vector3(-6, 8, 0), "head": Vector3(-8, 12, 0),
			"foot_l": [Vector3(0.22, A, 0.88), 0.0], "foot_r": [Vector3(-0.24, A, -0.18), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(0.02, 1.13, 0.78), "", HHClipsShared.aim(-4.0, 0.0)) })),
		HHClipsShared.key(1.0, w),
	]
	HHClipsShared.keyed(t, keys, b)
	var sh := HHClipsShared.shake(t, 0.333, 0.3, 15.0)
	b.rot("chest", Vector3(2.5 * sh, 0.0, 0.0))
	b.rot("head", Vector3(3.0 * sh, 0.0, 0.0))


static func _slam(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, { "move:root": Vector3(0, -0.05, 0), "hips": Vector3(6, 0, 0), "chest": Vector3(-12, 0, 0), "head": Vector3(-6, 0, 0),
			"foot_l": [Vector3(0.25, A, 0.3), 0.0], "foot_r": [Vector3(-0.25, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 1.95, -0.05), "", HHClipsShared.aim(82.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(0.133, { "move:root": Vector3(0, -0.42, 0.1), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0), "neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.38), 0.0], "foot_r": [Vector3(-0.26, A, -0.32), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 0.86, 0.5), "", HHClipsShared.aim(-42.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }, "snap"),
		HHClipsShared.key(0.36, { "move:root": Vector3(0, -0.4, 0.1), "hips": Vector3(26, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0), "neck": Vector3(-4, 0, 0), "head": Vector3(-12, 0, 0),
			"foot_l": [Vector3(0.26, A, 0.38), 0.0], "foot_r": [Vector3(-0.26, A, -0.32), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 0.84, 0.52), "", HHClipsShared.aim(-44.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(0.72, { "move:root": Vector3(0, -0.14, 0.08), "hips": Vector3(6, 4, 0), "spine": Vector3(-2, 2, 0), "chest": Vector3(-4, 4, 0), "head": Vector3(-4, -4, 0),
			"foot_l": [Vector3(0.24, A, 0.34), 0.0], "foot_r": [Vector3(-0.24, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.12, 1.2, 0.3), "", HHClipsShared.aim(12.0, 0.0)), "hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r") }),
		HHClipsShared.key(1.1, w),
	]
	HHClipsShared.keyed(t, keys, b)
	var sh := HHClipsShared.shake(t, 0.133, 0.4, 11.0)
	b.move("root", Vector3(0.0, 0.015 * sh, 0.0))
	b.rot("chest", Vector3(3.0 * sh, 0.0, 0.0))
	b.rot("head", Vector3(4.0 * sh, 0.0, 0.0))


static func _guard(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.apply(b, {
		"move:root": Vector3(0, -0.14, 0.02),
		"hips": Vector3(8, 6, 0), "spine": Vector3(6, 2, 0), "chest": Vector3(10, 4, 0), "neck": Vector3(-8, -4, 0), "head": Vector3(-10, -6, 0),
		"foot_l": [Vector3(0.26, A, 0.28), 0.0], "foot_r": [Vector3(-0.28, A, -0.3), 0.0],
		"hand_r": HHClipsShared.hand(Vector3(-0.34, 1.22, 0.3), "", HHClipsShared.aim(6.0, 84.0)),
		"hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r"),
	})
	HHClipsShared.breath(b, t, 1.2, 0.5)
	var s := sin(TAU * t / 1.2)
	b.move("root", Vector3(0.0, 0.006 * s, 0.0))
	b.rot("chest", Vector3(0.0, 0.0, 0.6 * sin(TAU * t * 5.0)))          # the brace is tense


static func _swap(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.25, { "move:root": Vector3(0, -0.15, 0.05), "hips": Vector3(22, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(12, 0, 0), "neck": Vector3(4, 0, 0), "head": Vector3(8, 0, 0),
			"foot_l": [Vector3(0.2, A, 0.25), 0.0], "foot_r": [Vector3(-0.22, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 0.72, 0.42), "", HHClipsShared.aim(82.0, 0.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.1, 1.3, 0.22), "", null, Vector3(0.8, -0.3, -0.2)) }, "snap"),
		HHClipsShared.key(0.55, { "move:root": Vector3(0, -0.16, 0.05), "hips": Vector3(24, 0, 0), "spine": Vector3(12, 0, 0), "chest": Vector3(14, 0, 0), "neck": Vector3(8, 0, 0), "head": Vector3(16, 0, 0),
			"foot_l": [Vector3(0.2, A, 0.25), 0.0], "foot_r": [Vector3(-0.22, A, -0.3), 0.0],
			"hand_r": HHClipsShared.hand(Vector3(-0.1, 0.72, 0.42), "", HHClipsShared.aim(84.0, 0.0)),
			"hand_l": HHClipsShared.hand(Vector3(0.08, 1.32, 0.2), "", null, Vector3(0.8, -0.3, -0.2)) }),
		HHClipsShared.key(0.9, w),
	]
	HHClipsShared.keyed(t, keys, b)


# ------------------------------------------------------------------ the string (H60 Lane X, H70 Lane X2)
# Three hits on Black | White's strike rig (HHClipsShared.beats / rooted /
# plant / impact) with the H70 spins (turn / spin_pose / spot): the stab
# does not turn, the slam turns once in the air, the spiral twice. Hits
# 2 and 3 start from the same loaded stance (combo_ready) and every turn
# ends on a whole circle at the contact, facing the target.

const PLANT_L := Vector3(0.2, A, 0.3)          ## the guard's plants (wield())
const PLANT_R := Vector3(-0.22, A, -0.3)


## The guard in the root frame: rooted(_wr()) is exactly wield().
static func _wr() -> Dictionary:
	var w := wield()
	var r: Vector3 = w["move:root"]
	var h: Dictionary = (w.hand_r as Dictionary).duplicate()
	h.pos = (h.pos as Vector3) - r
	w.hand_r = h
	return w


static func _hr(pos: Vector3, pitch: float, yaw: float) -> Dictionary:
	return HHClipsShared.hand(pos, "", HHClipsShared.aim(pitch, yaw))


static func _k(t: float, base: Dictionary, over: Dictionary, ease_kind: String = "ss") -> Dictionary:
	return HHClipsShared.rkey(t, HHClipsShared.merge(base, over), ease_kind)


## Between hits (H70: one shared stance, "the finish and coil can be the
## same"): low and loaded, the lance drawn back at the right hip, point on
## the target, feet on the guard's plants.
static func ready_pose() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.12, -0.04),
		"hips": Vector3(6, 28, 0), "spine": Vector3(3, 10, 0), "chest": Vector3(4, 20, 0), "neck": Vector3(-2, -16, 0), "head": Vector3(-4, -22, 0),
		"hand_r": _hr(Vector3(-0.28, 1.32, -0.26), 5.0, -6.0) })


## HIT 1, the stab (wind-up 12, recovery 5; no turn). From B|W
## _strike_polearm on _strike_sword's body: the shaft drawn to the rear
## hip, a stepping lunge, both hands down the line, hit-stop, hop home.
## H70: the coil winds the hips and chest well round to the right and the
## stab unwinds them, so the stab reads from the front, not only the side.
static func _combo_stab(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(12, 5, 10)
	var w := _wr()
	var keys := [
		HHClipsShared.rkey(0.0, w),
		_k(bt.wind, w, { "move:root": Vector3(0, -0.08, -0.02), "hips": Vector3(2, 26, 0), "neck": Vector3(0, -16, 0), "head": Vector3(-2, -24, 0) }),
		_k(bt.coil, w, { "move:root": Vector3(0, -0.18, -0.08), "hips": Vector3(8, 52, 0), "spine": Vector3(4, 16, 0), "chest": Vector3(4, 40, 0),
			"neck": Vector3(0, -34, 0), "head": Vector3(-2, -44, 0), "hand_r": _hr(Vector3(-0.3, 1.3, -0.48), 6.0, -4.0) }, "coil"),
		_k(bt.launch, w, { "move:root": Vector3(0, -0.21, -0.06), "hips": Vector3(8, 48, 0), "spine": Vector3(4, 14, 0), "chest": Vector3(4, 38, 0),
			"neck": Vector3(0, -32, 0), "head": Vector3(-2, -42, 0), "hand_r": _hr(Vector3(-0.29, 1.28, -0.46), 6.0, -4.0) }),
		_k(bt.land, w, { "move:root": Vector3(0, -0.1, 0.2), "hips": Vector3(6, 6, 0), "spine": Vector3(4, -2, 0), "chest": Vector3(6, -8, 0),
			"neck": Vector3(-2, 2, 0), "head": Vector3(-4, 2, 0), "hand_r": _hr(Vector3(-0.12, 1.34, 0.24), 1.0, 0.0) }, "lin"),
		_k(bt.hit, w, { "move:root": Vector3(0, -0.13, 0.34), "hips": Vector3(8, -22, 0), "spine": Vector3(4, -10, 0), "chest": Vector3(8, -30, 0),
			"neck": Vector3(-4, 10, 0), "head": Vector3(-6, 16, 0), "hand_r": _hr(Vector3(0.0, 1.34, 0.52), -3.0, 0.0) }, "snap"),
		_k(bt.stop, w, { "move:root": Vector3(0, -0.135, 0.35), "hips": Vector3(8, -23, 0), "spine": Vector3(4, -10, 0), "chest": Vector3(8, -31, 0),
			"neck": Vector3(-4, 10, 0), "head": Vector3(-6, 16, 0), "hand_r": _hr(Vector3(0.0, 1.34, 0.53), -3.0, 0.0) }),
		_k(bt.over, w, { "move:root": Vector3(0, -0.13, 0.34), "hips": Vector3(8, -26, 0), "spine": Vector3(4, -12, 0), "chest": Vector3(10, -36, 0),
			"neck": Vector3(-4, 12, 0), "head": Vector3(-6, 18, 0), "hand_r": _hr(Vector3(0.02, 1.32, 0.5), -5.0, 2.0) }, "over"),
		_k(bt.settle, w, { "move:root": Vector3(0, -0.12, 0.3), "hips": Vector3(6, -14, 0), "spine": Vector3(4, -6, 0), "chest": Vector3(6, -20, 0),
			"neck": Vector3(-2, 6, 0), "head": Vector3(-4, 10, 0), "hand_r": _hr(Vector3(-0.06, 1.32, 0.36), -2.0, -2.0) }),
		_k(bt.hop_start, w, { "move:root": Vector3(0, -0.17, 0.24), "hips": Vector3(6, 10, 0), "spine": Vector3(4, 4, 0), "chest": Vector3(4, 6, 0),
			"neck": Vector3(0, -8, 0), "head": Vector3(-2, -10, 0), "hand_r": _hr(Vector3(-0.18, 1.3, 0.1), 2.0, -4.0) }),
		_k(bt.hop_end, ready_pose(), { "move:root": Vector3(0, -0.08, 0.0) }),
		HHClipsShared.rkey(bt.end, ready_pose()),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L], [bt.coil + 0.02, bt.land, Vector3(0.2, A, 0.62)], [bt.hop_start, bt.hop_end, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, bt.hit, Vector3(-0.22, A, -0.08)], [bt.hop_start + 0.02, bt.hop_end + 0.03, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.25, 2.5)


## HIT 2, the leaping slam (wind-up 14, recovery 12; one turn, to her left).
## The lance is pulled back and up until the point is over the right
## shoulder behind her (the pull: B|W strike_axe's coil), she springs and
## turns a full circle in the air (B|W _strike_spin: off both feet, the
## head spotting), and the lance comes over the top as she lands, the slam
## on the contact (strike_axe's line; B|W leap's squashed landing).
static func _combo_leap_slam(t: float, b: HHPlayerBody) -> void:
	var r := ready_pose()
	var launch := 0.21
	var land := 0.45                               # contact 0.467 (14 ticks)
	var hit := 0.467
	var keys := [
		HHClipsShared.rkey(0.0, r),
		_k(0.1, r, { "move:root": Vector3(0, -0.16, -0.12), "hips": Vector3(8, 34, 0), "chest": Vector3(-2, 26, 0), "head": Vector3(-4, -26, 0),
			"hand_r": _hr(Vector3(-0.3, 1.5, -0.42), 34.0, -10.0) }),
		_k(0.18, r, { "move:root": Vector3(0, -0.32, -0.1), "hips": Vector3(24, 30, 0), "spine": Vector3(8, 6, 0), "chest": Vector3(-8, 14, 0),
			"neck": Vector3(-4, -10, 0), "head": Vector3(-8, -16, 0), "hand_r": _hr(Vector3(-0.22, 1.74, -0.18), 30.0, 175.0) }, "coil"),
		_k(launch + 0.02, r, { "move:root": Vector3(0, 0.08, 0.06), "hips": Vector3(4, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(-12, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0), "hand_r": _hr(Vector3(-0.16, 1.86, -0.14), 24.0, 178.0) }, "snap"),
		_k(0.33, r, { "move:root": Vector3(0, 0.4, 0.24), "hips": Vector3(16, 0, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(-10, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0), "hand_r": _hr(Vector3(-0.14, 1.86, -0.1), 20.0, 178.0) }),
		_k(0.41, r, { "move:root": Vector3(0, 0.22, 0.38), "hips": Vector3(18, 0, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(-4, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0), "hand_r": _hr(Vector3(-0.1, 1.95, 0.2), 70.0, 0.0) }),
		_k(land, r, { "move:root": Vector3(0, -0.2, 0.44), "hips": Vector3(22, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-10, 0, 0), "hand_r": _hr(Vector3(-0.1, 1.55, 0.44), 4.0, 0.0) }, "lin"),
		_k(hit, r, { "move:root": Vector3(0, -0.38, 0.46), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.3, 0.52), -20.0, 0.0) }, "snap"),
		_k(hit + 0.067, r, { "move:root": Vector3(0, -0.39, 0.46), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.29, 0.52), -21.0, 0.0) }),
		_k(0.6, r, { "move:root": Vector3(0, -0.35, 0.45), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(6, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.31, 0.5), -17.0, 0.0) }, "over"),
		_k(0.78, r, { "move:root": Vector3(0, -0.36, 0.45), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(7, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.3, 0.51), -19.0, 0.0) }),
		_k(0.88, r, { "move:root": Vector3(0, -0.22, 0.3), "hips": Vector3(12, 16, 0), "chest": Vector3(0, 10, 0), "head": Vector3(-6, -12, 0),
			"hand_r": _hr(Vector3(-0.2, 1.32, 0.0), 8.0, -4.0) }),
		_k(0.95, r, { "move:root": Vector3(0, -0.08, 0.02) }),
		_k(1.02, r, { "move:root": Vector3(0, -0.15, -0.04) }),
		HHClipsShared.rkey(1.1, r),
	]
	HHClipsShared.spin_hit(t, b, keys,
		[[0, 0, PLANT_L], [launch, land, Vector3(0.24, A, 0.72), 0.55], [0.88, 0.95, PLANT_L]],
		[[0, 0, PLANT_R], [launch + 0.01, land + 0.005, Vector3(-0.24, A, 0.16), 0.6], [0.89, 0.96, PLANT_R]],
		[[launch + 0.03, land - 0.015, 360.0]], hit, 0.4, 3.5, 13.0)


## HIT 3, the rising spiral (wind-up 18, recovery 17: the finisher; two
## turns, to her right). A deep crouch wound to the left with the point
## low behind her, a spring, and the body corkscrews UP through a full turn
## while the lance spirals up from low-behind to high through the target
## (B|W _strike_uppercut's drive up through the toes, _strike_spin's
## airborne turn); the contact is the top of the rise. The second turn is
## the fall: the lance whirled flat overhead, and a big squashed landing
## with the point driven down (B|W leap), held, then home to the guard.
static func _combo_spiral(t: float, b: HHPlayerBody) -> void:
	var r := ready_pose()
	var w := _wr()
	var launch := 0.27
	var hit := 0.6
	var land := 0.86
	var keys := [
		HHClipsShared.rkey(0.0, r),
		_k(0.12, r, { "move:root": Vector3(0, -0.22, -0.02), "hips": Vector3(16, 40, 0), "spine": Vector3(6, 14, 0), "chest": Vector3(4, 34, 0),
			"neck": Vector3(-2, -26, 0), "head": Vector3(-6, -34, 0), "hand_r": _hr(Vector3(-0.3, 1.16, -0.34), -10.0, -60.0) }),
		_k(0.24, r, { "move:root": Vector3(0, -0.38, -0.04), "hips": Vector3(30, 48, 0), "spine": Vector3(10, 16, 0), "chest": Vector3(6, 40, 0),
			"neck": Vector3(-4, -30, 0), "head": Vector3(-8, -40, 0), "hand_r": _hr(Vector3(-0.32, 1.08, -0.36), -28.0, -150.0) }, "coil"),
		_k(launch + 0.03, r, { "move:root": Vector3(0, 0.02, 0.06), "hips": Vector3(2, 20, 0), "spine": Vector3(0, 8, 0), "chest": Vector3(-8, 14, 0),
			"neck": Vector3(-4, -10, 0), "head": Vector3(-6, -14, 0), "hand_r": _hr(Vector3(-0.34, 1.2, -0.2), -16.0, -120.0) }, "snap"),
		_k(0.43, r, { "move:root": Vector3(0, 0.36, 0.2), "hips": Vector3(-2, 0, 0), "spine": Vector3(-2, 0, 0), "chest": Vector3(-10, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-8, 0, 0), "hand_r": _hr(Vector3(-0.36, 1.46, 0.06), 12.0, -80.0) }),
		_k(0.53, r, { "move:root": Vector3(0, 0.74, 0.32), "hips": Vector3(-4, -10, 0), "spine": Vector3(-4, -4, 0), "chest": Vector3(-14, -10, 0),
			"neck": Vector3(-8, 4, 0), "head": Vector3(-12, 6, 0), "hand_r": _hr(Vector3(-0.2, 1.62, 0.32), 32.0, -30.0) }),
		_k(hit, r, { "move:root": Vector3(0, 0.9, 0.38), "hips": Vector3(-4, -16, 0), "spine": Vector3(-4, -6, 0), "chest": Vector3(-16, -18, 0),
			"neck": Vector3(-8, 8, 0), "head": Vector3(-14, 10, 0), "hand_r": _hr(Vector3(-0.06, 1.78, 0.46), 48.0, 0.0) }, "snap"),
		_k(hit + 0.05, r, { "move:root": Vector3(0, 0.92, 0.38), "hips": Vector3(-4, -16, 0), "spine": Vector3(-4, -6, 0), "chest": Vector3(-16, -18, 0),
			"neck": Vector3(-8, 8, 0), "head": Vector3(-14, 10, 0), "hand_r": _hr(Vector3(-0.06, 1.8, 0.44), 50.0, 0.0) }),
		_k(0.72, r, { "move:root": Vector3(0, 0.7, 0.38), "hips": Vector3(8, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(-6, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0), "hand_r": _hr(Vector3(-0.16, 1.92, 0.04), 6.0, -90.0) }),
		_k(0.82, r, { "move:root": Vector3(0, 0.14, 0.38), "hips": Vector3(16, 0, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(0, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-10, 0, 0), "hand_r": _hr(Vector3(-0.12, 1.8, 0.3), 30.0, 0.0) }),
		_k(land, r, { "move:root": Vector3(0, -0.42, 0.4), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.3, 0.5), -20.0, 0.0) }, "snap"),
		_k(0.94, r, { "move:root": Vector3(0, -0.4, 0.4), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(7, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.31, 0.5), -18.0, 0.0) }),
		_k(0.99, w, { "move:root": Vector3(0, -0.2, 0.26), "hips": Vector3(10, 10, 0), "hand_r": _hr(Vector3(-0.16, 1.34, 0.04), 6.0, 0.0) }),
		_k(1.03, w, { "move:root": Vector3(0, -0.04, 0.02) }),
		HHClipsShared.rkey(1.07, w),
	]
	HHClipsShared.spin_hit(t, b, keys,
		[[0, 0, PLANT_L], [launch, land, Vector3(0.24, A, 0.66), 1.05], [0.98, 1.03, PLANT_L]],
		[[0, 0, PLANT_R], [launch + 0.01, land + 0.01, Vector3(-0.24, A, 0.12), 1.1], [0.99, 1.04, PLANT_R]],
		[[launch + 0.03, hit - 0.01, -360.0], [hit + 0.06, land - 0.02, -360.0]], hit, 0.4, 3.5, 13.0)
	HHClipsShared.impact(b, t, land, 0.35, 3.0, 11.0)


## H60: the charged Pierce's brace (CHARGE_CLIP, a loop): the plant's coil
## (the shaft drawn back low, a long planted stance) sunk lower, the chest
## set, and a tremor through the body and the shaft that grows with the
## charge (HHPlayerBody.charge_frac): the lance cannot be broken here
## (H59 super armour), it shakes with what it holds back.
static func _brace(t: float, b: HHPlayerBody) -> void:
	var k := clampf(b.charge_frac, 0.0, 1.0)
	var amp := 0.5 + 2.5 * k
	var j := Vector3(0.0, 0.004 * amp * sin(TAU * t * 13.0), 0.003 * amp * sin(TAU * t * 9.0 + 0.7))
	HHClipsShared.apply(b, {
		"move:root": Vector3(0, -0.18 - 0.06 * k, -0.2),
		"hips": Vector3(4, 36, 0), "spine": Vector3(5, 14, 0), "chest": Vector3(6, 26, 0), "neck": Vector3(-2, -26, 0), "head": Vector3(-6, -32, 0),
		"foot_l": [Vector3(0.22, A, 0.2), 0.0], "foot_r": [Vector3(-0.27, A, -0.54), 0.0],
		"hand_r": HHClipsShared.hand(Vector3(-0.22, 1.02 - 0.03 * k, -0.58) + j, "", HHClipsShared.aim(10.0 - 3.0 * k, -4.0)),
		"hand_l": HHClipsShared.hand(GRIP_L, "socket_weapon_r"),
	})
	HHClipsShared.breath(b, t, 0.9 - 0.3 * k, 0.6 + 0.6 * k)
	var s1 := sin(TAU * t * 11.0)
	var s2 := sin(TAU * t * 17.0 + 1.3)
	b.rot("chest", Vector3(0.6 * amp * s1, 0.0, 0.4 * amp * s2))
	b.rot("head", Vector3(0.4 * amp * s2, 0.0, 0.0))
	b.move("root", Vector3(0.0, -0.002 * amp * absf(s1), 0.0))
