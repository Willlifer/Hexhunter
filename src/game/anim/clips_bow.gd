class_name HHClipsBow
extends RefCounted
## The bow clip set (Lane B): the recurve in the LEFT hand (socket_offhand_l),
## the right hand IK'd to the string in the bow's own frame (second_hand point
## z = -0.183, pulled back to -0.62 at full draw). The arrow is nocked only
## while a clip asks for it (draws), and HHPlayerBody lays it from the string
## hand to the bow hand. Shots: a long draw is the anticipation, the release
## is one frame, the follow-through is the string hand flying back and the
## bow hand kicking forward.

const A := HHClipsShared.ANKLE_Y
const STRING := Vector3(0.0, 0.0, -0.183)
const DRAW := Vector3(0.0, 0.02, -0.62)
const DRAW_POLE := Vector3(-0.9, 0.5, -0.3)          ## the draw elbow: out to the right, high, back
const LOOSE := Vector3(-0.2, 0.06, -0.78)            ## the string hand after release (elbow still bent)

const CLIPS := {
	"idle":            { "duration": 4.0, "contact_tick": -1, "loop": true,  "key": 1.0, "note": "bow hanging at the left side, breathing" },
	"wield_idle":      { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "half-raised, bow canted, string hand at the hip, scanning" },
	"walk":            { "duration": 0.436, "contact_tick": -1, "loop": true, "key": 0.1, "stride": 2.4, "note": "jog, the bow carried low-forward" },
	"run":             { "duration": 0.4325, "contact_tick": -1, "loop": true, "key": 0.05, "stride": 3.46, "note": "sprint, bow hand steadier, right arm pumps" },
	"strike":          { "duration": 0.8, "contact_tick": 8, "loop": false, "key": 0.27, "note": "the basic: snap shot, short draw, release at 0.27, string hand flies back" },
	"sweep":           { "duration": 0.9, "contact_tick": 10, "loop": false, "key": 0.33, "note": "the bow swung like a club, limb-first" },
	"spin":            { "duration": 1.0, "contact_tick": 12, "loop": false, "key": 0.4, "note": "hop-spin with the bow out" },
	"jump":            { "duration": 0.87, "contact_tick": -1, "loop": false, "key": 0.45, "note": "tuck, bow raised" },
	"jump_attack":     { "duration": 0.8, "contact_tick": 5, "loop": false, "key": 0.2, "note": "landing point-blank shot down-forward" },
	"kneel_shot":      { "duration": 1.4, "contact_tick": 16, "loop": false, "key": 0.53, "note": "Energized shot: drops to the right knee, long draw, heavy release, rises" },
	"draw":            { "duration": 2.0, "contact_tick": -1, "loop": true,  "key": 0.6, "note": "full draw held on the target, aim sway, breathing" },
	"lob":             { "duration": 1.0, "contact_tick": 14, "loop": false, "key": 0.47, "note": "arcing lob: aim 50 degrees up, release, watch it go" },
	"arrowstorm_leap": { "duration": 0.87, "contact_tick": -1, "loop": false, "key": 0.5, "note": "the rise: bow raised, back arched, a fistful of arrows from the quiver, aiming down by the apex" },
	"volley":          { "duration": 1.2, "contact_tick": 6, "loop": false, "key": 0.2, "note": "landing: crouched, three quick shots down-forward" },
	"swap":            { "duration": 0.9, "contact_tick": -1, "loop": false, "key": 0.4, "note": "Elemental Exchange: quiver flip, the bow spun in the left hand" },
	"stagger":         { "duration": 1.0, "contact_tick": -1, "loop": false, "key": 0.3, "note": "knocked back a step" },
	"hit_react":       { "duration": 0.45, "contact_tick": -1, "loop": false, "key": 0.08, "note": "flinch" },
	"death":           { "duration": 1.5, "contact_tick": -1, "loop": false, "key": 1.3, "note": "falls onto the back" },
	"dash":            { "duration": 0.36, "contact_tick": -1, "loop": false, "key": 0.12, "note": "H56: the dash, a low forward burst, the bow trailing" },
}
const SKILL_CLIPS := { "q": "kneel_shot", "w": "swap", "e": "lob", "r": "arrowstorm_leap" }
const WINDUP_CLIPS := { "basic": "strike", "kneel_shot": "kneel_shot", "lob": "lob", "energized": "kneel_shot", "exchange": "swap" }
## H56: the held draw while Q charges (no basic string on the bow, H57).
const CHARGE_CLIP := "draw"
const LANDING_CLIPS := { "arrowstorm_leap": "volley", "jump": "jump_attack" }


static func pose(clip: String, t: float, b: HHPlayerBody) -> void:
	match clip:
		"idle": HHClipsShared.idle(t, b, carry_idle())
		"wield_idle": _wield_idle(t, b)
		"walk": HHClipsShared.walk(t, b, carry_run(), 0.3, 1.0)
		"run": HHClipsShared.run(t, b, carry_run(), 0.3, 1.0)
		"strike": _strike(t, b)
		"sweep": _sweep(t, b)
		"spin": _spin(t, b)
		"jump": HHClipsShared.jump(t, b, carry_air(), float(CLIPS.jump.duration))
		"jump_attack": _jump_attack(t, b)
		"kneel_shot": _kneel_shot(t, b)
		"draw": _draw(t, b)
		"lob": _lob(t, b)
		"arrowstorm_leap": _arrowstorm_leap(t, b)
		"volley": _volley(t, b)
		"swap": _swap(t, b)
		"stagger": HHClipsShared.stagger(t, b, wield())
		"hit_react": HHClipsShared.hit_react(t, b, wield())
		"death": HHClipsShared.death(t, b, wield())
		"dash": HHClipsShared.dash(t, b, carry_run())


# ------------------------------------------------------------------ poses

static func _noreach(h: Dictionary) -> Dictionary:
	var out := h.duplicate()
	out.reach = false
	return out


static func carry_idle() -> Dictionary:
	return {
		"hand_l": HHClipsShared.hand(Vector3(0.3, 0.98, 0.12), "", HHClipsShared.bow_aim(-12.0, 18.0, 30.0)),
		"upper_arm_r": Vector3(3, 0, 22), "forearm_r": Vector3(-14, 0, 0),
	}


static func carry_run() -> Dictionary:
	return { "hand_l": _noreach(HHClipsShared.hand(Vector3.ZERO, "", HHClipsShared.bow_aim(-35.0, 25.0, 25.0))) }


static func carry_air() -> Dictionary:
	return {
		"hand_l": HHClipsShared.hand(Vector3(0.3, 1.7, 0.2), "", HHClipsShared.bow_aim(20.0, 20.0, 15.0)),
		"upper_arm_r": Vector3(-30, 0, -45), "forearm_r": Vector3(-40, 0, 0),
	}


## Ready: side-on (left shoulder to the target), the bow half-raised and
## canted, the string hand resting at the right hip.
static func wield() -> Dictionary:
	return {
		"move:root": Vector3(0, -0.04, 0),
		"hips": Vector3(2, 22, 0), "spine": Vector3(2, 10, 0), "chest": Vector3(2, 16, 0), "neck": Vector3(0, -16, 0), "head": Vector3(-2, -22, 0),
		"foot_l": [Vector3(0.22, A, 0.3), 0.0], "foot_r": [Vector3(-0.24, A, -0.26), 0.0],
		"hand_l": HHClipsShared.hand(Vector3(0.22, 1.25, 0.4), "", HHClipsShared.bow_aim(-25.0, 10.0, 20.0)),
		"hand_r": HHClipsShared.hand(Vector3(-0.22, 1.08, 0.0), "", null, Vector3(-0.8, -0.3, -0.5)),
	}


## Aiming at the target: the bow arm straight forward, the string hand at the cheek.
static func aimed(pitch_deg: float = 0.0, cant_deg: float = 8.0) -> Dictionary:
	var up := sin(deg_to_rad(pitch_deg))
	return {
		"move:root": Vector3(0, -0.05, 0),
		"hips": Vector3(2, 30, 0), "spine": Vector3(-pitch_deg * 0.15, 14, 0), "chest": Vector3(-pitch_deg * 0.3, 20, 0), "neck": Vector3(-pitch_deg * 0.2, -24, 0), "head": Vector3(-4 - pitch_deg * 0.3, -32, 0),
		"foot_l": [Vector3(0.24, A, 0.32), 0.0], "foot_r": [Vector3(-0.24, A, -0.3), 0.0],
		"hand_l": HHClipsShared.hand(Vector3(0.06, 1.6 + 0.3 * up, 0.54 * cos(deg_to_rad(pitch_deg))), "", HHClipsShared.bow_aim(pitch_deg, 0.0, cant_deg)),
		"hand_r": HHClipsShared.hand(DRAW, "socket_offhand_l", null, DRAW_POLE),
		"nock": true,
	}


static func _wield_idle(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.apply(b, wield())
	HHClipsShared.breath(b, t, 3.0, 0.8)
	var s := sin(TAU * t / 3.0)
	b.rot("head", Vector3(0.0, 8.0 * sin(TAU * t / 6.0), 0.0))
	b.move("root", Vector3(0.0, 0.0, 0.015 * s))


static func _draw(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.apply(b, aimed(0.0))
	HHClipsShared.breath(b, t, 2.0, 0.4)
	var s := sin(TAU * t / 2.0)
	var s2 := sin(TAU * t / 3.1 + 0.7)
	b.rot("chest", Vector3(0.6 * s2, 0.8 * s, 0.0))             # aim sway


# ------------------------------------------------------------------ shots

## A shot: `keys` from wield through a draw to a release at `rt`, then the
## follow-through and back. `pitch` aims up/down; `draw_from` starts the draw.
static func _shot_keys(rt: float, draw_from: float, pitch: float, end_t: float, base: Dictionary) -> Array:
	var up := aimed(pitch)
	var half := up.duplicate()
	half.hand_r = HHClipsShared.hand(STRING, "socket_offhand_l", null, DRAW_POLE)
	var loose := up.duplicate()
	loose.hand_r = HHClipsShared.hand(LOOSE, "socket_offhand_l", null, DRAW_POLE)
	loose.nock = false
	loose["hand_l"] = HHClipsShared.hand((up.hand_l.pos as Vector3) + Vector3(0.0, 0.05, 0.06), "", HHClipsShared.bow_aim(pitch + 10.0, -4.0, 8.0))
	loose["chest"] = (up.chest as Vector3) + Vector3(-5, -4, 0)
	loose["head"] = (up.head as Vector3) + Vector3(-3, 0, 0)
	return [
		HHClipsShared.key(0.0, base),
		HHClipsShared.key(draw_from, half),
		HHClipsShared.key(rt - 0.01, up, "coil"),
		HHClipsShared.key(rt, loose, "snap"),
		HHClipsShared.key(rt + 0.12, loose),
		HHClipsShared.key(end_t, base),
	]


static func _strike(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.keyed(t, _shot_keys(0.267, 0.12, 0.0, 0.8, wield()), b)
	b.rot("chest", Vector3(1.5 * HHClipsShared.shake(t, 0.267, 0.2, 16.0), 0.0, 0.0))


static func _lob(t: float, b: HHPlayerBody) -> void:
	HHClipsShared.keyed(t, _shot_keys(0.467, 0.14, 50.0, 1.0, wield()), b)
	b.rot("head", Vector3(-8.0 * HHClipsShared.ss(t, 0.5, 0.7) * (1.0 - HHClipsShared.ss(t, 0.8, 1.0)), 0.0, 0.0))    # watches it go


static func _kneel_shot(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var knee := {
		"move:root": Vector3(0, -0.46, 0.05),
		"hips": Vector3(6, 28, 0), "spine": Vector3(-2, 12, 0), "chest": Vector3(-4, 18, 0), "neck": Vector3(0, -22, 0), "head": Vector3(-4, -30, 0),
		"foot_l": [Vector3(0.24, A, 0.42), 0.0], "foot_r": [Vector3(-0.22, A + 0.06, -0.78), 60.0],
	}
	var up := HHClipsShared.merge(aimed(-4.0, 6.0), knee)
	var half := up.duplicate()
	half.hand_r = HHClipsShared.hand(STRING, "socket_offhand_l", null, DRAW_POLE)
	var loose := up.duplicate()
	loose.hand_r = HHClipsShared.hand(LOOSE + Vector3(0, 0.08, -0.1), "socket_offhand_l", null, DRAW_POLE)
	loose.nock = false
	loose["hand_l"] = HHClipsShared.hand((up.hand_l.pos as Vector3) + Vector3(0.0, 0.12, 0.04), "", HHClipsShared.bow_aim(16.0, -6.0, 6.0))
	loose["chest"] = (up.chest as Vector3) + Vector3(-12, -6, 0)
	loose["spine"] = (up.spine as Vector3) + Vector3(-6, 0, 0)
	loose["head"] = (up.head as Vector3) + Vector3(-6, 0, 0)
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.22, HHClipsShared.merge(half, knee), "snap"),
		HHClipsShared.key(0.52, up, "coil"),
		HHClipsShared.key(0.533, loose, "snap"),
		HHClipsShared.key(0.72, loose),
		HHClipsShared.key(1.0, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.2, 0.0) })),
		HHClipsShared.key(1.4, w),
	]
	HHClipsShared.keyed(t, keys, b)
	var sh := HHClipsShared.shake(t, 0.533, 0.35, 12.0)
	b.rot("chest", Vector3(3.0 * sh, 0.0, 0.0))
	b.rot("head", Vector3(3.0 * sh, 0.0, 0.0))


static func _jump_attack(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var crouch := {
		"move:root": Vector3(0, -0.3, 0.08), "hips": Vector3(26, 10, 0), "spine": Vector3(6, 6, 0), "chest": Vector3(4, 8, 0), "head": Vector3(-14, -12, 0),
		"foot_l": [Vector3(0.26, A, 0.34), 0.0], "foot_r": [Vector3(-0.26, A, -0.3), 0.0],
	}
	var up := HHClipsShared.merge(aimed(-35.0, 10.0), crouch)
	up.hand_l = HHClipsShared.hand(Vector3(0.08, 1.05, 0.5), "", HHClipsShared.bow_aim(-35.0, 0.0, 10.0))
	var loose := up.duplicate()
	loose.hand_r = HHClipsShared.hand(LOOSE, "socket_offhand_l", null, DRAW_POLE)
	loose.nock = false
	var keys := [
		HHClipsShared.key(0.0, HHClipsShared.merge(carry_air(), { "hips": Vector3(6, 0, 0), "thigh_l": Vector3(-25, 0, 0), "shin_l": Vector3(20, 0, 0), "thigh_r": Vector3(-25, 0, 0), "shin_r": Vector3(20, 0, 0) })),
		HHClipsShared.key(0.16, up, "snap"),
		HHClipsShared.key(0.167, loose, "snap"),
		HHClipsShared.key(0.35, loose),
		HHClipsShared.key(0.8, w),
	]
	HHClipsShared.keyed(t, keys, b)


static func _arrowstorm_leap(t: float, b: HHPlayerBody) -> void:
	var d := float(CLIPS.arrowstorm_leap.duration)
	var keys := [
		HHClipsShared.key(0.0, { "move:root": Vector3(0, 0.0, 0), "hips": Vector3(-6, 0, 0), "chest": Vector3(-14, 0, 0), "head": Vector3(-10, 0, 0),
			"thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(30, 0, 0), "thigh_r": Vector3(0, 0, 0), "shin_r": Vector3(40, 0, 0),
			"hand_l": HHClipsShared.hand(Vector3(0.25, 1.9, 0.1), "", HHClipsShared.bow_aim(70.0, 10.0, 20.0)),
			"hand_r": HHClipsShared.hand(Vector3(-0.2, 1.15, -0.1), "", null, Vector3(-0.8, -0.3, -0.5)) }),
		HHClipsShared.key(d * 0.4, { "move:root": Vector3(0, 0.1, 0), "hips": Vector3(-16, 0, 0), "spine": Vector3(-8, 0, 0), "chest": Vector3(-18, 0, 0), "head": Vector3(-6, 0, 0),
			"thigh_l": Vector3(-60, 0, 0), "shin_l": Vector3(80, 0, 0), "thigh_r": Vector3(-50, 0, 0), "shin_r": Vector3(90, 0, 0),
			"hand_l": HHClipsShared.hand(Vector3(0.2, 2.0, -0.1), "", HHClipsShared.bow_aim(85.0, 0.0, 10.0)),
			"hand_r": HHClipsShared.hand(Vector3(0.0, 0.12, -0.14), "socket_back", null, Vector3(-0.9, 0.3, -0.3)) }),
		HHClipsShared.key(d * 0.75, { "move:root": Vector3(0, 0.1, 0), "hips": Vector3(16, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(14, 0, 0), "head": Vector3(10, 0, 0),
			"thigh_l": Vector3(-55, 0, 0), "shin_l": Vector3(70, 0, 0), "thigh_r": Vector3(-45, 0, 0), "shin_r": Vector3(75, 0, 0),
			"hand_l": HHClipsShared.hand(Vector3(0.1, 1.1, 0.5), "", HHClipsShared.bow_aim(-65.0, 0.0, 10.0)),
			"hand_r": HHClipsShared.hand(DRAW, "socket_offhand_l", null, Vector3(-0.9, 0.6, -0.2)), "nock": true }),
		HHClipsShared.key(d, { "move:root": Vector3(0, 0.0, 0), "hips": Vector3(20, 0, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(12, 0, 0), "head": Vector3(8, 0, 0),
			"thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(25, 0, 0), "thigh_r": Vector3(-30, 0, 0), "shin_r": Vector3(25, 0, 0),
			"hand_l": HHClipsShared.hand(Vector3(0.1, 1.0, 0.55), "", HHClipsShared.bow_aim(-60.0, 0.0, 10.0)),
			"hand_r": HHClipsShared.hand(DRAW, "socket_offhand_l", null, Vector3(-0.9, 0.6, -0.2)), "nock": true }),
	]
	HHClipsShared.keyed(t, keys, b)


## Landing: crouched, aiming down-forward, three quick draws and releases
## (0.2, 0.45, 0.7), then up.
static func _volley(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var crouch := {
		"move:root": Vector3(0, -0.34, 0.1), "hips": Vector3(30, 14, 0), "spine": Vector3(8, 8, 0), "chest": Vector3(6, 10, 0), "neck": Vector3(-4, -10, 0), "head": Vector3(-12, -16, 0),
		"foot_l": [Vector3(0.28, A, 0.36), 0.0], "foot_r": [Vector3(-0.28, A, -0.32), 0.0],
	}
	var up := HHClipsShared.merge(aimed(-45.0, 8.0), crouch)
	up.hand_l = HHClipsShared.hand(Vector3(0.1, 0.95, 0.56), "", HHClipsShared.bow_aim(-45.0, 0.0, 8.0))
	var loose := up.duplicate()
	loose.hand_r = HHClipsShared.hand(LOOSE, "socket_offhand_l", null, DRAW_POLE)
	loose.nock = false
	var half := up.duplicate()
	half.hand_r = HHClipsShared.hand(STRING, "socket_offhand_l", null, DRAW_POLE)
	var keys := [HHClipsShared.key(0.0, HHClipsShared.merge(half, { "hand_l": HHClipsShared.hand(Vector3(0.1, 1.0, 0.55), "", HHClipsShared.bow_aim(-60.0, 0.0, 10.0)) }))]
	for rt in [0.2, 0.45, 0.7]:
		keys.append(HHClipsShared.key(float(rt) - 0.11, half))
		keys.append(HHClipsShared.key(float(rt) - 0.01, up, "coil"))
		keys.append(HHClipsShared.key(float(rt), loose, "snap"))
		keys.append(HHClipsShared.key(float(rt) + 0.06, loose))
	keys.append(HHClipsShared.key(0.95, HHClipsShared.merge(w, { "move:root": Vector3(0, -0.15, 0) })))
	keys.append(HHClipsShared.key(1.2, w))
	HHClipsShared.keyed(t, keys, b)
	for rt in [0.2, 0.45, 0.7]:
		b.rot("chest", Vector3(2.0 * HHClipsShared.shake(t, float(rt), 0.12, 18.0), 0.0, 0.0))


# ------------------------------------------------------------------ melee, air, swap

static func _sweep(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.22, HHClipsShared.merge(w, { "move:root": Vector3(0.04, -0.08, -0.08), "hips": Vector3(2, 42, 0), "spine": Vector3(2, 18, 0), "chest": Vector3(2, 28, 0), "neck": Vector3(0, -28, 0), "head": Vector3(-2, -36, 0),
			"hand_l": HHClipsShared.hand(Vector3(0.5, 1.3, -0.2), "", HHClipsShared.aim(10.0, 120.0)),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.0, -0.1), "", null, Vector3(-0.8, -0.3, -0.5)) }), "coil"),
		HHClipsShared.key(0.333, HHClipsShared.merge(w, { "move:root": Vector3(-0.04, -0.1, 0.14), "hips": Vector3(6, -8, 0), "spine": Vector3(2, -8, 0), "chest": Vector3(4, -14, 0), "neck": Vector3(0, 6, 0), "head": Vector3(-2, 8, 0),
			"foot_l": [Vector3(0.24, A, 0.42), 0.0],
			"hand_l": HHClipsShared.hand(Vector3(-0.1, 1.15, 0.48), "", HHClipsShared.aim(0.0, 15.0)),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.0, 0.1), "", null, Vector3(-0.8, -0.3, -0.5)) }), "snap"),
		HHClipsShared.key(0.5, HHClipsShared.merge(w, { "move:root": Vector3(-0.08, -0.1, 0.12), "hips": Vector3(6, -26, 0), "spine": Vector3(2, -14, 0), "chest": Vector3(4, -26, 0), "neck": Vector3(0, 12, 0), "head": Vector3(-2, 16, 0),
			"foot_l": [Vector3(0.24, A, 0.42), 0.0],
			"hand_l": HHClipsShared.hand(Vector3(-0.42, 1.1, 0.2), "", HHClipsShared.aim(-5.0, -60.0)),
			"hand_r": HHClipsShared.hand(Vector3(-0.3, 1.0, 0.1), "", null, Vector3(-0.8, -0.3, -0.5)) })),
		HHClipsShared.key(0.9, w),
	]
	HHClipsShared.keyed(t, keys, b)


static func _spin(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var yaw := 0.0
	if t < 0.15:
		yaw = -45.0 * HHClipsShared.coil(t / 0.15)
	elif t < 0.4:
		yaw = lerpf(-45.0, 360.0, (t - 0.15) / 0.25)
	else:
		yaw = 360.0
	var air := HHClipsShared.ss(t, 0.12, 0.2) * (1.0 - HHClipsShared.ss(t, 0.4, 0.52))
	var base := HHClipsShared.merge(w, {
		"move:root": Vector3(0, -0.08 + 0.28 * air, 0.0),
		"hand_l": HHClipsShared.hand(Vector3(0.6, 1.15, 0.0), "", HHClipsShared.aim(0.0, 100.0)),
		"hand_r": HHClipsShared.hand(Vector3(-0.45, 1.1, 0.0), "", null, Vector3(-0.8, -0.3, -0.5)),
	})
	if air > 0.01:
		base.erase("foot_l")
		base.erase("foot_r")
		base["thigh_l"] = Vector3(-40 * air, 0, 0)
		base["shin_l"] = Vector3(60 * air, 0, 0)
		base["thigh_r"] = Vector3(-40 * air, 0, 0)
		base["shin_r"] = Vector3(60 * air, 0, 0)
	var rotated := HHClipsShared.rotate_pose(base, yaw)
	HHClipsShared.apply(b, HHClipsShared.mix(rotated, HHClipsShared.merge(w, { "root": Vector3(0, 360, 0) }), HHClipsShared.ss(t, 0.52, 1.0)))


static func _swap(t: float, b: HHPlayerBody) -> void:
	var w := wield()
	var spin := 360.0 * HHClipsShared.ss(t, 0.3, 0.7)
	var keys := [
		HHClipsShared.key(0.0, w),
		HHClipsShared.key(0.25, HHClipsShared.merge(w, { "chest": Vector3(-4, 10, 0), "head": Vector3(-6, -30, 0),
			"hand_r": HHClipsShared.hand(Vector3(0.0, 0.14, -0.14), "socket_back", null, Vector3(-0.9, 0.4, -0.3)) }), "snap"),
		HHClipsShared.key(0.45, HHClipsShared.merge(w, { "hand_r": HHClipsShared.hand(Vector3(-0.1, 1.5, 0.3), "", null, Vector3(-0.8, 0.0, -0.5)), "nock": true,
			"hand_l": HHClipsShared.hand(Vector3(0.22, 1.3, 0.4), "", HHClipsShared.bow_aim(-25.0 + spin, 10.0, 20.0)) })),
		HHClipsShared.key(0.7, HHClipsShared.merge(w, { "hand_r": HHClipsShared.hand(Vector3(-0.2, 1.1, 0.05), "", null, Vector3(-0.8, -0.3, -0.5)),
			"hand_l": HHClipsShared.hand(Vector3(0.22, 1.28, 0.4), "", HHClipsShared.bow_aim(-25.0 + spin, 10.0, 20.0)) })),
		HHClipsShared.key(0.9, w),
	]
	HHClipsShared.keyed(t, keys, b)
