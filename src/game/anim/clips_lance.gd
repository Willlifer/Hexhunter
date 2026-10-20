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
	"dash":        { "duration": 0.36, "contact_tick": -1, "loop": false, "key": 0.12, "note": "H56: the dash, a low forward burst, the weapon trailing" },
	# H60 (Lane X): the string, one dedicated clip per hit, timed to the sim (contact_tick = the hit's wind-up,
	# `recovery` = its recovery ticks, `timed`: plays at full rate through the recovery: the follow-through is keyed);
	# `trail` = [from s, to s, strength, blades] for the swing arc; ready loops hold between hits
	"combo_jab":    { "duration": 0.9, "contact_tick": 12, "recovery": 5, "timed": true, "loop": false, "key": 0.4, "trail": [0.33, 0.5, 0.6, "main"],
		"note": "string hit 1: shaft drawn to the rear hip, a stepping lunge, both hands drive the point down the line, hit-stop, hop home" },
	"combo_cross":  { "duration": 1.1, "contact_tick": 14, "recovery": 12, "timed": true, "loop": false, "key": 0.47, "trail": [0.38, 0.62, 1.0, "main"],
		"note": "string hit 2: the shaft wheels from back-right across the front, the rear foot steps through, follow-through low left" },
	"combo_drive":  { "duration": 1.1, "contact_tick": 18, "recovery": 17, "timed": true, "loop": false, "key": 0.6, "trail": [0.49, 0.66, 1.4, "main"],
		"note": "string finisher: deep crouch, spring, the lance over the top and driven down into the target on the landing, rip out, hop home" },
	"combo_ready1": { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits 1 and 2: loaded to the right, breathing hard" },
	"combo_ready2": { "duration": 1.1, "contact_tick": -1, "loop": true, "key": 0.2, "note": "between hits 2 and 3: the lance raised for the finisher" },
	"brace":        { "duration": 1.0, "contact_tick": -1, "loop": true, "key": 0.5, "note": "H60: the charged Pierce held: wide, low, planted, the shaft drawn back; trembles harder as the charge builds" },
}
const SKILL_CLIPS := { "q": "plant", "w": "swap", "e": "guard", "r": "jump" }
const WINDUP_CLIPS := { "basic": "strike", "pierce": "plant", "exchange": "swap" }
## H57: the basic string; H60: one dedicated clip per hit, and the loop that holds between hits.
const COMBO_CLIPS := { 1: "combo_jab", 2: "combo_cross", 3: "combo_drive" }
const READY_CLIPS := { 1: "combo_ready1", 2: "combo_ready2" }
## H56: the held charge pose; H60: the brace loop, released into the plant from its coil.
const CHARGE_CLIP := "brace"
const CHARGE_FROM := { "plant": 0.26 }
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
		"dash": HHClipsShared.dash(t, b, carry_run())
		"combo_jab": _combo_jab(t, b)
		"combo_cross": _combo_cross(t, b)
		"combo_drive": _combo_drive(t, b)
		"combo_ready1": HHClipsShared.ready_loop(t, b, ready1())
		"combo_ready2": HHClipsShared.ready_loop(t, b, ready2())
		"brace": _brace(t, b)


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


# ------------------------------------------------------------------ the string (H60, Lane X)
# Three dedicated hits on Black | White's strike rig (HHClipsShared.beats /
# rooted / plant / impact): every key sits on a beat retimed onto the hit's
# sim timing, the hands ride the root, the feet only move between plants.
# Hit 1 (jab) comes from the centre line, hit 2 (cross) wheels right to
# left, hit 3 (drive) comes over the top: three directions, rising weight.

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


## Between hits 1 and 2: wound to the right, the point angled out right
## (the cross-cut starts there). Feet on the guard's plants.
static func ready1() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.08, -0.02),
		"hips": Vector3(2, 24, 0), "spine": Vector3(2, 10, 0), "chest": Vector3(4, 18, 0), "neck": Vector3(0, -14, 0), "head": Vector3(-2, -20, 0),
		"hand_r": _hr(Vector3(-0.3, 1.32, -0.14), 4.0, -26.0) })


## Between hits 2 and 3: the lance raised, point up, for the finisher.
static func ready2() -> Dictionary:
	return HHClipsShared.merge(_wr(), { "move:root": Vector3(0, -0.1, 0),
		"hips": Vector3(4, 14, 0), "spine": Vector3(2, 6, 0), "chest": Vector3(2, 10, 0), "neck": Vector3(0, -8, 0), "head": Vector3(-4, -12, 0),
		"hand_r": _hr(Vector3(-0.16, 1.5, -0.12), 36.0, 0.0) })


## HIT 1, the jab (wind-up 12, recovery 5). From B|W _strike_polearm (the
## shaft drawn back to the rear hip in the coil, both hands driven straight
## down the line on the dash, stops dead) on the reference strike's body
## (_strike_sword: coil, compress, the stepping lunge, hit-stop, hop home).
static func _combo_jab(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(12, 5, 10)
	var w := _wr()
	var keys := [
		HHClipsShared.rkey(0.0, w),
		HHClipsShared.rkey(bt.wind, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.07, -0.02), "hips": Vector3(0, 22, 0), "neck": Vector3(0, -14, 0), "head": Vector3(-2, -22, 0) })),
		HHClipsShared.rkey(bt.coil, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.17, -0.08), "hips": Vector3(8, 34, 0), "spine": Vector3(4, 12, 0), "chest": Vector3(4, 28, 0),
			"neck": Vector3(0, -22, 0), "head": Vector3(-2, -30, 0), "hand_r": _hr(Vector3(-0.24, 1.3, -0.46), 6.0, -3.0) }), "coil"),
		HHClipsShared.rkey(bt.launch, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.2, -0.06), "hips": Vector3(8, 30, 0), "spine": Vector3(4, 10, 0), "chest": Vector3(4, 24, 0),
			"neck": Vector3(0, -22, 0), "head": Vector3(-2, -30, 0), "hand_r": _hr(Vector3(-0.23, 1.28, -0.44), 6.0, -3.0) })),
		HHClipsShared.rkey(bt.land, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.1, 0.2), "hips": Vector3(6, 4, 0), "spine": Vector3(4, -2, 0), "chest": Vector3(6, -6, 0),
			"neck": Vector3(-2, 0, 0), "head": Vector3(-4, 2, 0), "hand_r": _hr(Vector3(-0.1, 1.34, 0.24), 1.0, 0.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.13, 0.32), "hips": Vector3(8, -8, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(8, -18, 0),
			"neck": Vector3(-4, 6, 0), "head": Vector3(-6, 10, 0), "hand_r": _hr(Vector3(-0.02, 1.34, 0.5), -3.0, 0.0) }), "snap"),
		HHClipsShared.rkey(bt.stop, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.135, 0.33), "hips": Vector3(8, -8, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(8, -19, 0),
			"neck": Vector3(-4, 6, 0), "head": Vector3(-6, 10, 0), "hand_r": _hr(Vector3(-0.02, 1.34, 0.51), -3.0, 0.0) })),
		HHClipsShared.rkey(bt.over, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.13, 0.32), "hips": Vector3(8, -10, 0), "spine": Vector3(4, -9, 0), "chest": Vector3(10, -22, 0),
			"neck": Vector3(-4, 6, 0), "head": Vector3(-6, 10, 0), "hand_r": _hr(Vector3(0.0, 1.32, 0.48), -5.0, 2.0) }), "over"),
		HHClipsShared.rkey(bt.settle, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.12, 0.28), "hips": Vector3(6, -4, 0), "spine": Vector3(4, -4, 0), "chest": Vector3(6, -12, 0),
			"neck": Vector3(-2, 4, 0), "head": Vector3(-4, 6, 0), "hand_r": _hr(Vector3(-0.06, 1.32, 0.36), -2.0, -2.0) })),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.16, 0.22), "hips": Vector3(6, 6, 0), "spine": Vector3(4, 2, 0), "chest": Vector3(4, 4, 0),
			"neck": Vector3(0, -6, 0), "head": Vector3(-2, -8, 0), "hand_r": _hr(Vector3(-0.16, 1.3, 0.12), 0.0, -6.0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.04, 0.02), "hips": Vector3(2, 18, 0), "chest": Vector3(4, 14, 0),
			"hand_r": _hr(Vector3(-0.24, 1.32, -0.1), 3.0, -18.0) })),
		HHClipsShared.rkey(bt.end, ready1()),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L], [bt.coil + 0.02, bt.land, Vector3(0.2, A, 0.6)], [bt.hop_start, bt.hop_end, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, bt.hit, Vector3(-0.22, A, -0.1)], [bt.hop_start + 0.02, bt.hop_end + 0.03, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.25, 2.5)


## HIT 2, the cross (wind-up 14, recovery 12). From B|W anim_skill _sweep
## (the shaft swung level from back-right, across the front, through to
## the left; hips and chest turn with it) with _strike_spin's head spotting
## the target, and a step-through: the rear foot crosses to the front on
## the cut, the hop home brings it back.
static func _combo_cross(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(14, 12, 7)
	var r1 := ready1()
	var keys := [
		HHClipsShared.rkey(0.0, r1),
		HHClipsShared.rkey(bt.wind, HHClipsShared.merge(r1, { "move:root": Vector3(0.02, -0.1, -0.03), "hips": Vector3(2, 30, 0), "neck": Vector3(0, -22, 0), "head": Vector3(-2, -30, 0) })),
		HHClipsShared.rkey(bt.coil, HHClipsShared.merge(r1, { "move:root": Vector3(0.04, -0.16, -0.06), "hips": Vector3(4, 56, 0), "spine": Vector3(2, 20, 0), "chest": Vector3(2, 44, 0),
			"neck": Vector3(0, -38, 0), "head": Vector3(-2, -50, 0), "hand_r": _hr(Vector3(-0.34, 1.3, -0.26), 4.0, -100.0) }), "coil"),
		HHClipsShared.rkey(bt.launch, HHClipsShared.merge(r1, { "move:root": Vector3(0.03, -0.17, -0.02), "hips": Vector3(4, 40, 0), "spine": Vector3(2, 14, 0), "chest": Vector3(2, 30, 0),
			"neck": Vector3(0, -30, 0), "head": Vector3(-2, -40, 0), "hand_r": _hr(Vector3(-0.34, 1.28, -0.22), 3.0, -96.0) })),
		HHClipsShared.rkey(bt.land, HHClipsShared.merge(r1, { "move:root": Vector3(0.0, -0.12, 0.18), "hips": Vector3(6, 12, 0), "spine": Vector3(4, 4, 0), "chest": Vector3(6, 4, 0),
			"neck": Vector3(-2, -4, 0), "head": Vector3(-4, -6, 0), "hand_r": _hr(Vector3(-0.24, 1.24, 0.18), 0.0, -45.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(r1, { "move:root": Vector3(-0.02, -0.15, 0.26), "hips": Vector3(6, -12, 0), "spine": Vector3(4, -8, 0), "chest": Vector3(6, -22, 0),
			"neck": Vector3(-2, 8, 0), "head": Vector3(-4, 12, 0), "hand_r": _hr(Vector3(-0.02, 1.22, 0.38), -3.0, 4.0) }), "lin"),
		HHClipsShared.rkey(bt.stop, HHClipsShared.merge(r1, { "move:root": Vector3(-0.03, -0.155, 0.27), "hips": Vector3(6, -18, 0), "spine": Vector3(4, -10, 0), "chest": Vector3(6, -28, 0),
			"neck": Vector3(-2, 10, 0), "head": Vector3(-4, 16, 0), "hand_r": _hr(Vector3(0.06, 1.21, 0.36), -4.0, 16.0) })),
		HHClipsShared.rkey(bt.over, HHClipsShared.merge(r1, { "move:root": Vector3(-0.06, -0.18, 0.26), "hips": Vector3(6, -46, 0), "spine": Vector3(2, -18, 0), "chest": Vector3(6, -58, 0),
			"neck": Vector3(0, 22, 0), "head": Vector3(-2, 34, 0), "hand_r": _hr(Vector3(0.3, 1.18, 0.18), -8.0, 72.0) }), "over"),
		HHClipsShared.rkey(bt.settle, HHClipsShared.merge(r1, { "move:root": Vector3(-0.05, -0.17, 0.25), "hips": Vector3(6, -40, 0), "spine": Vector3(2, -16, 0), "chest": Vector3(6, -50, 0),
			"neck": Vector3(0, 20, 0), "head": Vector3(-2, 30, 0), "hand_r": _hr(Vector3(0.28, 1.18, 0.16), -8.0, 64.0) })),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(r1, { "move:root": Vector3(-0.02, -0.18, 0.2), "hips": Vector3(4, -8, 0), "spine": Vector3(2, -4, 0), "chest": Vector3(4, -10, 0),
			"neck": Vector3(0, 4, 0), "head": Vector3(-2, 6, 0), "hand_r": _hr(Vector3(0.06, 1.22, 0.1), 4.0, 20.0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(r1, { "move:root": Vector3(0, -0.08, 0.02), "hips": Vector3(2, 10, 0), "spine": Vector3(2, 4, 0), "chest": Vector3(2, 6, 0),
			"neck": Vector3(0, -6, 0), "head": Vector3(-2, -8, 0), "hand_r": _hr(Vector3(-0.12, 1.32, -0.08), 14.0, 4.0) })),
		HHClipsShared.rkey(bt.end, ready2()),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, bt.hit, Vector3(-0.08, A, 0.46)], [bt.hop_start, bt.hop_end, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.3, 3.0)


## HIT 3, the drive (wind-up 18, recovery 17: the finisher). From B|W
## anim_skill leap (crouch and load, spring, tucked in the air, a deep
## squashed landing held a beat, rise) with strike_axe's overhead line
## (the head goes up behind in the coil, over the top and down through
## the target); the hit-stop is the longest, the shudder the biggest.
static func _combo_drive(t: float, b: HHPlayerBody) -> void:
	var bt := HHClipsShared.beats(18, 14, 0)
	# the finisher holds its landing longer than the reference: the rip-out and
	# the hop home are packed into the last of the recovery (review round 2)
	bt.settle = 0.84
	bt.hop_start = 0.93
	bt.hop_end = 0.99
	var r2 := ready2()
	var w := _wr()
	var apex := lerpf(bt.launch, bt.land, 0.45)
	var keys := [
		HHClipsShared.rkey(0.0, r2),
		HHClipsShared.rkey(bt.wind, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.16, -0.02), "hips": Vector3(10, 10, 0), "chest": Vector3(0, 8, 0), "head": Vector3(-6, -10, 0),
			"hand_r": _hr(Vector3(-0.16, 1.6, -0.1), 52.0, 0.0) })),
		HHClipsShared.rkey(bt.coil, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.32, -0.06), "hips": Vector3(26, 4, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(-8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-10, -4, 0), "hand_r": _hr(Vector3(-0.14, 2.06, -0.12), 78.0, 0.0) }), "coil"),
		HHClipsShared.rkey(bt.launch, HHClipsShared.merge(r2, { "move:root": Vector3(0, 0.06, 0.12), "hips": Vector3(4, 0, 0), "spine": Vector3(0, 0, 0), "chest": Vector3(-10, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-8, 0, 0), "hand_r": _hr(Vector3(-0.12, 2.1, 0.0), 70.0, 0.0) }), "snap"),
		HHClipsShared.rkey(apex, HHClipsShared.merge(r2, { "move:root": Vector3(0, 0.3, 0.3), "hips": Vector3(14, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(-14, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0), "hand_r": _hr(Vector3(-0.12, 2.0, 0.08), 30.0, 0.0) })),
		HHClipsShared.rkey(bt.land, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.18, 0.42), "hips": Vector3(20, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(2, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-10, 0, 0), "hand_r": _hr(Vector3(-0.1, 1.5, 0.42), -8.0, 0.0) }), "lin"),
		HHClipsShared.rkey(bt.hit, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.4, 0.46), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.3, 0.52), -20.0, 0.0) }), "snap"),
		HHClipsShared.rkey(bt.stop, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.41, 0.46), "hips": Vector3(30, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(8, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-14, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.29, 0.52), -21.0, 0.0) })),
		HHClipsShared.rkey(bt.over, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.36, 0.45), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(6, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.32, 0.5), -17.0, 0.0) }), "over"),
		HHClipsShared.rkey(bt.settle, HHClipsShared.merge(r2, { "move:root": Vector3(0, -0.37, 0.45), "hips": Vector3(28, 0, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(7, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "hand_r": _hr(Vector3(-0.08, 1.31, 0.51), -19.0, 0.0) })),
		HHClipsShared.rkey(bt.hop_start, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.22, 0.34), "hips": Vector3(12, 8, 0), "spine": Vector3(4, 4, 0), "chest": Vector3(-2, 6, 0),
			"neck": Vector3(0, -4, 0), "head": Vector3(-6, -6, 0), "hand_r": _hr(Vector3(-0.14, 1.36, 0.12), 12.0, 0.0) })),
		HHClipsShared.rkey(bt.hop_end, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.06, 0.04), "hand_r": _hr(Vector3(-0.14, 1.32, -0.08), 5.0, 0.0) })),
		HHClipsShared.rkey(lerpf(bt.hop_end, bt.end, 0.5), HHClipsShared.merge(w, { "move:root": Vector3(0, -0.09, 0.0) })),
		HHClipsShared.rkey(bt.end, w),
	]
	HHClipsShared.keyed(t, keys, b)
	HHClipsShared.feet(t, b,
		[[0, 0, PLANT_L], [bt.launch - 0.02, bt.land, Vector3(0.22, A, 0.78), 0.45], [bt.hop_start + 0.01, bt.hop_end + 0.02, PLANT_L]],
		[[0, 0, PLANT_R], [bt.launch, bt.land + 0.01, Vector3(-0.24, A, 0.12), 0.5], [bt.hop_start, bt.hop_end, PLANT_R]])
	HHClipsShared.impact(b, t, bt.hit, 0.45, 4.0, 13.0)


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
