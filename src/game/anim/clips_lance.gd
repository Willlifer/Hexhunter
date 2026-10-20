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
	"idle":        { "duration": 4.0, "contact_tick": -1, "loop": true,  "key": 1.0, "note": "lance shouldered, weight shifting, breathing" },
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
}
const SKILL_CLIPS := { "q": "plant", "w": "swap", "e": "guard", "r": "jump" }
const WINDUP_CLIPS := { "basic": "strike", "pierce": "plant" }
const LANDING_CLIPS := { "jump": "slam" }


static func pose(clip: String, t: float, b: HHPlayerBody) -> void:
	match clip:
		"idle": HHClipsShared.idle(t, b, carry_idle())
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


# ------------------------------------------------------------------ poses

## Relaxed carry: the lance over the right shoulder, the left arm hanging.
static func carry_idle() -> Dictionary:
	return {
		"hand_r": HHClipsShared.hand(Vector3(-0.24, 1.38, 0.22), "", HHClipsShared.aim(62.0, 180.0)),
		"upper_arm_l": Vector3(2, 0, -22), "forearm_l": Vector3(-12, 0, 0),
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
