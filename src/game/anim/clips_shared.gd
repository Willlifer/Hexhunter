class_name HHClipsShared
extends RefCounted
## The clip machinery and the clips every weapon set shares (Lane B).
##
## POSES are dictionaries of channels (all offsets from the A-pose rest):
##   "<bone>": Vector3(pitch, yaw, roll) degrees about the model axes (HHPlayerBody.rot)
##   "move:<bone>": Vector3 model metres (HHPlayerBody.move)
##   "foot_l" / "foot_r": [Vector3 ankle position (model), pitch deg]        (IK, sole level)
##   "hand_l" / "hand_r": { pos, anchor ("" | socket), aim (Basis | null), pole (Vector3 | null) }
##   "nock": bool
## KEYS are [{ t, pose, ease }] in time order; `keyed(t, keys, b)` finds the
## segment, eases u, blends the two poses channel by channel and applies
## them. Clips are keys plus procedural layers (breath, shake, cycles).
##
## Axis reminders (model: +Y up, +Z forward, +X the character's left):
##   hanging limb forward swing = -pitch;  knee bend = +pitch on the shin;
##   elbow flex = -pitch on the forearm;  +roll lifts a hanging tip to the
##   left (abducts the left arm, adducts the right);  +yaw turns a tip left.
##
## Locomotion (H31): run 8 m/s, stride 3.46 m per cycle (two 1.73 m hex
## steps); walk 5.5 m/s (a jog), stride 2.4 m. The stance foot is IK-planted
## and travels back at exactly the root speed; HHPlayerBody plays the loop at
## speed_mps / stride so the feet never skid.

const T := 1.0 / 30.0
const RUN_STRIDE := 3.46
const WALK_STRIDE := 2.4
const ANKLE_Y := 0.09
const HIP_Y := 1.0

const SPINE := ["hips", "spine", "chest"]
const ARM_L := ["upper_arm_l", "forearm_l", "hand_l"]
const ARM_R := ["upper_arm_r", "forearm_r", "hand_r"]


# ------------------------------------------------------------------ easing

static func ss(t: float, a: float, c: float) -> float:
	if c <= a:
		return 1.0 if t >= c else 0.0
	return smoothstep(0.0, 1.0, clampf((t - a) / (c - a), 0.0, 1.0))


## fast out (a snap): 1 - (1 - u)^3
static func snap(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


## slow in (a coil): u^3
static func coil(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u


static func ease_u(u: float, kind: String) -> float:
	match kind:
		"snap": return snap(u)
		"coil": return coil(u)
		"lin": return clampf(u, 0.0, 1.0)
		"over":                                # snaps to 1 by 55%, swings past, settles
			var v := clampf(u, 0.0, 1.0)
			if v < 0.55:
				return snap(v / 0.55)
			var k := (v - 0.55) / 0.45
			return 1.0 + 0.15 * sin(k * PI) * (1.0 - k)
		_: return smoothstep(0.0, 1.0, clampf(u, 0.0, 1.0))


## A decaying shake: sin at `hz`, amplitude falling over `life` from `t0`.
static func shake(t: float, t0: float, life: float, hz: float) -> float:
	if t < t0:
		return 0.0
	var u := (t - t0) / maxf(life, 1e-4)
	if u >= 1.0:
		return 0.0
	return sin((t - t0) * TAU * hz) * (1.0 - u) * (1.0 - u)


# ------------------------------------------------------------------ poses

## A hand channel.
static func hand(pos: Vector3, anchor: String = "", aim: Variant = null, pole: Variant = null) -> Dictionary:
	return { "pos": pos, "anchor": anchor, "aim": aim, "pole": pole }


## A basis whose +Y points along `dir` (a weapon's shaft / blade) with +Z as
## forward as possible: the hand aim that points a held weapon at `dir`.
static func along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-4:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## `along` from pitch (up +) and yaw (left +) in degrees.
static func aim(pitch_deg: float, yaw_deg: float, roll_deg: float = 0.0) -> Basis:
	var p := deg_to_rad(pitch_deg)
	var yw := deg_to_rad(yaw_deg)
	var dir := Vector3(sin(yw) * cos(p), sin(p), cos(yw) * cos(p))
	var b := along(dir)
	if roll_deg != 0.0:
		b = b * Basis(Vector3.UP, deg_to_rad(roll_deg))
	return b


## A bow's basis: +Z (the arrow) toward pitch (up +) / yaw (left +), +Y up,
## then canted about the arrow by `cant_deg`.
static func bow_aim(pitch_deg: float, yaw_deg: float, cant_deg: float = 0.0) -> Basis:
	var p := deg_to_rad(pitch_deg)
	var yw := deg_to_rad(yaw_deg)
	var dir := Vector3(sin(yw) * cos(p), sin(p), cos(yw) * cos(p))
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	var b := Basis.looking_at(-dir, up)
	if cant_deg != 0.0:
		b = b * Basis(Vector3.BACK, deg_to_rad(cant_deg))
	return b


## The pose turned about the model's up axis (spin clips: IK targets live in
## model space, so they must turn with the root). Adds the root yaw itself.
static func rotate_pose(pose: Dictionary, yaw_deg: float) -> Dictionary:
	var r := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var out := {}
	for k in pose:
		var ks := str(k)
		var v: Variant = pose[k]
		if ks.begins_with("foot_"):
			var arr: Array = (v as Array).duplicate()
			arr[0] = r * (arr[0] as Vector3)
			out[k] = arr
		elif ks.begins_with("hand_"):
			var h: Dictionary = (v as Dictionary).duplicate()
			if str(h.anchor) == "":
				h.pos = r * (h.pos as Vector3)
			if h.aim is Basis:
				h.aim = r * (h.aim as Basis)
			if h.get("pole") is Vector3:
				h.pole = r * (h.pole as Vector3)
			out[k] = h
		elif ks == "move:root":
			out[k] = r * (v as Vector3)
		else:
			out[k] = v
	out["root"] = (out.get("root", Vector3.ZERO) as Vector3) + Vector3(0.0, yaw_deg, 0.0)
	return out


static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out


## Blend two poses (channel union; a missing channel is rest / zero weight).
static func mix(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for k in keys:
		var has_a := a.has(k)
		var has_b := b.has(k)
		var va: Variant = a.get(k)
		var vb: Variant = b.get(k)
		var ks := str(k)
		if ks == "nock":
			out[k] = (vb == true) if u >= 0.5 else (va == true)
		elif ks.begins_with("foot_"):
			var pa: Array = va if has_a else vb
			var pb: Array = vb if has_b else va
			var w := 1.0 if (has_a and has_b) else (1.0 - u if has_a else u)
			out[k] = [(pa[0] as Vector3).lerp(pb[0], u), lerpf(float(pa[1]), float(pb[1]), u), w]
		elif ks.begins_with("hand_"):
			var ha: Dictionary = va if has_a else vb
			var hb: Dictionary = vb if has_b else va
			var w := 1.0 if (has_a and has_b) else (1.0 - u if has_a else u)
			var h := {}
			if str(ha.anchor) == str(hb.anchor):
				h = { "pos": (ha.pos as Vector3).lerp(hb.pos, u), "anchor": ha.anchor, "w": w }
			else:
				var src: Dictionary = hb if u >= 0.5 else ha
				h = { "pos": src.pos, "anchor": src.anchor, "w": w * absf(u * 2.0 - 1.0) }
			var aa: Variant = ha.get("aim")
			var ab: Variant = hb.get("aim")
			if aa is Basis and ab is Basis:
				h.aim = Basis((aa as Basis).get_rotation_quaternion().slerp((ab as Basis).get_rotation_quaternion(), u))
			elif aa is Basis or ab is Basis:
				var pick: Variant = ab if u >= 0.5 else aa
				if pick is Basis:
					h.aim = pick
			var pole: Variant = hb.get("pole") if u >= 0.5 else ha.get("pole")
			if pole == null:
				pole = hb.get("pole") if hb.get("pole") != null else ha.get("pole")
			if pole != null:
				h.pole = pole
			h.reach = bool(ha.get("reach", true)) and bool(hb.get("reach", true))
			out[k] = h
		else:
			var a3: Vector3 = va if has_a else Vector3.ZERO
			var b3: Vector3 = vb if has_b else Vector3.ZERO
			out[k] = a3.lerp(b3, u)
	return out


## Apply a pose to the body (scaled by `w`).
static func apply(b: HHPlayerBody, pose: Dictionary, w: float = 1.0) -> void:
	for k in pose:
		var ks := str(k)
		var v: Variant = pose[k]
		if ks == "nock":
			b.nock(bool(v))
		elif ks.begins_with("foot_"):
			var arr: Array = v
			var fw := float(arr[2]) if arr.size() > 2 else 1.0
			b.ik_foot(ks.trim_prefix("foot_"), arr[0], float(arr[1]), fw * w)
		elif ks.begins_with("hand_"):
			var h: Dictionary = v
			var hw := float(h.get("w", 1.0)) * w
			var am: Variant = h.get("aim")
			b.ik_hand(ks.trim_prefix("hand_"), h.pos, str(h.anchor), hw, am if am is Basis else null, h.get("pole"), bool(h.get("reach", true)))
		elif ks.begins_with("move:"):
			b.move(ks.trim_prefix("move:"), (v as Vector3) * w)
		else:
			b.rot(ks, (v as Vector3) * w)


## Sample `keys` at `t` and apply. Before the first key: the first pose;
## after the last: the last (a hold).
static func keyed(t: float, keys: Array, b: HHPlayerBody, w: float = 1.0) -> void:
	apply(b, sample(t, keys), w)


static func sample(t: float, keys: Array) -> Dictionary:
	if keys.is_empty():
		return {}
	if t <= float(keys[0].t):
		return keys[0].pose
	for i in range(1, keys.size()):
		var k1: Dictionary = keys[i]
		if t <= float(k1.t):
			var k0: Dictionary = keys[i - 1]
			var u := (t - float(k0.t)) / maxf(float(k1.t) - float(k0.t), 1e-5)
			return mix(k0.pose, k1.pose, ease_u(u, str(k1.get("ease", "ss"))))
	return keys[keys.size() - 1].pose


static func key(t: float, pose: Dictionary, ease_kind: String = "ss") -> Dictionary:
	return { "t": t, "pose": pose, "ease": ease_kind }


# ------------------------------------------------------------------ layers

## Breathing: the chest rises, the shoulders lift a touch.
static func breath(b: HHPlayerBody, t: float, period: float, amt: float) -> void:
	var s := 0.5 - 0.5 * cos(TAU * t / period)
	b.rot("spine", Vector3(-1.2 * amt * s, 0.0, 0.0))
	b.rot("chest", Vector3(1.6 * amt * s, 0.0, 0.0))
	b.rot("neck", Vector3(-0.8 * amt * s, 0.0, 0.0))
	b.rot("shoulder_l", Vector3(0.0, 0.0, 2.0 * amt * s))
	b.rot("shoulder_r", Vector3(0.0, 0.0, -2.0 * amt * s))


## Standing weight shift and a slow look-around (idles).
static func sway(b: HHPlayerBody, t: float, amt: float) -> void:
	var s := sin(TAU * t / 6.0)
	var s2 := sin(TAU * t / 9.0 + 1.1)
	b.move("root", Vector3(0.02 * amt * s, 0.0, 0.0))
	b.rot("hips", Vector3(0.0, 0.0, 1.5 * amt * s))
	b.rot("spine", Vector3(0.0, 2.0 * amt * s2, -1.0 * amt * s))
	b.rot("head", Vector3(1.5 * amt * s2, 6.0 * amt * s2, 0.0))


## Arms hanging at the sides from the A-pose, elbows soft.
static func arms_down(b: HHPlayerBody, bend_deg: float = 12.0) -> void:
	b.rot("upper_arm_l", Vector3(2.0, 0.0, -22.0))
	b.rot("upper_arm_r", Vector3(2.0, 0.0, 22.0))
	b.rot("forearm_l", Vector3(-bend_deg, 0.0, 0.0))
	b.rot("forearm_r", Vector3(-bend_deg, 0.0, 0.0))


## One foot of a gait cycle: phase 0 = contact. Stance for `fs` of the
## cycle (the ankle travels back at the root speed), then a swing arc.
static func foot_cycle(ph: float, stride: float, fs: float, lift: float) -> Array:
	ph = fposmod(ph, 1.0)
	var half := stride * fs * 0.5
	if ph < fs:
		var z := half - stride * ph
		return [Vector3(0.0, ANKLE_Y, z), 0.0]
	var u := (ph - fs) / (1.0 - fs)
	var z2 := lerpf(-half, half, smoothstep(0.0, 1.0, u))
	var arc := sin(pow(u, 0.85) * PI)
	var y := ANKLE_Y + lift * arc
	var pitch := 28.0 * arc * (1.0 - u) - 14.0 * u * u
	return [Vector3(0.0, y, z2), pitch]


## The run cycle (loop, stride RUN_STRIDE). `carry` poses the arms and the
## weapon; `pump` scales the arm swing it adds on top (0 = none).
static func run(t: float, b: HHPlayerBody, carry: Dictionary, pump_l: float = 1.0, pump_r: float = 1.0) -> void:
	var d := float(b.duration("run"))
	var ph := fposmod(t / maxf(d, 1e-4), 1.0)
	var fs := 0.3
	var lift := 0.42
	var fl := foot_cycle(ph, RUN_STRIDE, fs, lift)
	var fr := foot_cycle(ph + 0.5, RUN_STRIDE, fs, lift)
	b.ik_foot("l", Vector3(0.12, (fl[0] as Vector3).y, (fl[0] as Vector3).z), float(fl[1]))
	b.ik_foot("r", Vector3(-0.12, (fr[0] as Vector3).y, (fr[0] as Vector3).z), float(fr[1]))
	# the body: low at mid-stance, high mid-flight; lean into the speed
	var c2 := cos(TAU * (ph - fs * 0.5) * 2.0)         # 1 at mid-stance (twice per cycle)
	b.move("root", Vector3(0.0, -0.06 * c2 + 0.02, 0.0))
	var s1 := sin(TAU * ph)                            # left leg forward at ph ~ 0
	b.rot("hips", Vector3(6.0, -8.0 * s1, 2.5 * s1))
	b.rot("spine", Vector3(8.0, 5.0 * s1, -1.5 * s1))
	b.rot("chest", Vector3(8.0, 7.0 * s1, 0.0))
	b.rot("neck", Vector3(-8.0, -2.0 * s1, 0.0))
	b.rot("head", Vector3(-10.0, -3.0 * s1, 0.0))
	apply(b, carry)
	# arms counter to the legs: the right arm drives forward with the left leg
	var swing := 38.0
	b.rot("upper_arm_r", Vector3(-swing * s1 * pump_r, 0.0, 10.0 * pump_r))
	b.rot("forearm_r", Vector3(-(70.0 + 25.0 * s1) * pump_r, 0.0, 0.0))
	b.rot("upper_arm_l", Vector3(swing * s1 * pump_l, 0.0, -10.0 * pump_l))
	b.rot("forearm_l", Vector3(-(70.0 - 25.0 * s1) * pump_l, 0.0, 0.0))


## The walk (a 5.5 m/s jog): shorter stride, less lean, softer arms.
static func walk(t: float, b: HHPlayerBody, carry: Dictionary, pump_l: float = 1.0, pump_r: float = 1.0) -> void:
	var d := float(b.duration("walk"))
	var ph := fposmod(t / maxf(d, 1e-4), 1.0)
	var fs := 0.42
	var lift := 0.2
	var fl := foot_cycle(ph, WALK_STRIDE, fs, lift)
	var fr := foot_cycle(ph + 0.5, WALK_STRIDE, fs, lift)
	b.ik_foot("l", Vector3(0.12, (fl[0] as Vector3).y, (fl[0] as Vector3).z), float(fl[1]))
	b.ik_foot("r", Vector3(-0.12, (fr[0] as Vector3).y, (fr[0] as Vector3).z), float(fr[1]))
	var c2 := cos(TAU * (ph - fs * 0.5) * 2.0)
	b.move("root", Vector3(0.0, -0.035 * c2, 0.0))
	var s1 := sin(TAU * ph)
	b.rot("hips", Vector3(3.0, -6.0 * s1, 2.0 * s1))
	b.rot("spine", Vector3(3.0, 4.0 * s1, -1.0 * s1))
	b.rot("chest", Vector3(3.0, 5.0 * s1, 0.0))
	b.rot("neck", Vector3(-3.0, -2.0 * s1, 0.0))
	b.rot("head", Vector3(-4.0, -2.0 * s1, 0.0))
	apply(b, carry)
	var swing := 22.0
	b.rot("upper_arm_r", Vector3(-swing * s1 * pump_r, 0.0, 14.0 * pump_r))
	b.rot("forearm_r", Vector3(-(35.0 + 12.0 * s1) * pump_r, 0.0, 0.0))
	b.rot("upper_arm_l", Vector3(swing * s1 * pump_l, 0.0, -14.0 * pump_l))
	b.rot("forearm_l", Vector3(-(35.0 - 12.0 * s1) * pump_l, 0.0, 0.0))


## Relaxed idle: feet planted shoulder width, weight shifting, breathing.
static func idle(t: float, b: HHPlayerBody, carry: Dictionary) -> void:
	b.ik_foot("l", Vector3(0.14, ANKLE_Y, 0.04), 0.0)
	b.ik_foot("r", Vector3(-0.14, ANKLE_Y, -0.04), 0.0)
	b.move("root", Vector3(0.0, -0.015, 0.0))
	b.rot("thigh_l", Vector3(0.0, 6.0, 0.0))
	b.rot("thigh_r", Vector3(0.0, -6.0, 0.0))
	breath(b, t, 3.4, 1.0)
	sway(b, t, 1.0)
	apply(b, carry)


## Stagger: knocked back a step, the arms flail, slow recover (speed-scaled
## by the body to the sim's stagger ticks).
static func stagger(t: float, b: HHPlayerBody, carry: Dictionary) -> void:
	var keys := [
		key(0.0, merge(carry, { "move:root": Vector3(0, 0, 0), "foot_l": [Vector3(0.14, ANKLE_Y, 0.05), 0.0], "foot_r": [Vector3(-0.14, ANKLE_Y, -0.05), 0.0] })),
		key(0.12, { "move:root": Vector3(0, -0.08, -0.35), "hips": Vector3(-12, 0, 0), "spine": Vector3(-10, 6, 0), "chest": Vector3(-14, 0, 0),
			"neck": Vector3(-10, 0, 0), "head": Vector3(-14, 0, 6),
			"upper_arm_l": Vector3(-50, 0, 30), "upper_arm_r": Vector3(-40, 0, -35), "forearm_l": Vector3(-40, 0, 0), "forearm_r": Vector3(-50, 0, 0),
			"foot_l": [Vector3(0.16, ANKLE_Y, 0.02), 0.0], "foot_r": [Vector3(-0.16, ANKLE_Y, -0.55), 0.0] }, "snap"),
		key(0.45, { "move:root": Vector3(0, -0.12, -0.42), "hips": Vector3(-6, 0, 0), "spine": Vector3(-4, 4, 0), "chest": Vector3(-6, 0, 0),
			"neck": Vector3(2, 0, 0), "head": Vector3(6, 0, -4),
			"upper_arm_l": Vector3(-25, 0, 20), "upper_arm_r": Vector3(-20, 0, -25), "forearm_l": Vector3(-50, 0, 0), "forearm_r": Vector3(-55, 0, 0),
			"foot_l": [Vector3(0.16, ANKLE_Y, -0.1), 0.0], "foot_r": [Vector3(-0.16, ANKLE_Y, -0.6), 0.0] }),
		key(1.0, merge(carry, { "move:root": Vector3(0, -0.02, -0.4), "foot_l": [Vector3(0.14, ANKLE_Y, -0.35), 0.0], "foot_r": [Vector3(-0.14, ANKLE_Y, -0.45), 0.0] })),
	]
	keyed(t, keys, b)
	b.rot("head", Vector3(4.0 * shake(t, 0.1, 0.5, 9.0), 0.0, 3.0 * shake(t, 0.1, 0.5, 7.0)))


## Hit react: a short flinch, the hit side folds, then back.
static func hit_react(t: float, b: HHPlayerBody, carry: Dictionary) -> void:
	var keys := [
		key(0.0, carry),
		key(0.07, merge(carry, { "move:root": Vector3(0, -0.04, -0.08), "hips": Vector3(-4, 0, 0), "spine": Vector3(-8, 5, 3), "chest": Vector3(-10, 4, 0),
			"neck": Vector3(-8, 0, 0), "head": Vector3(-10, -6, 4) }), "snap"),
		key(0.45, carry),
	]
	keyed(t, keys, b)
	b.rot("chest", Vector3(0.0, 0.0, 3.0 * shake(t, 0.07, 0.3, 11.0)))


## Death: the knees go, a half-turn fall onto the back, held.
static func death(t: float, b: HHPlayerBody, carry: Dictionary) -> void:
	var keys := [
		key(0.0, carry),
		key(0.35, { "move:root": Vector3(0, -0.32, 0.0), "hips": Vector3(10, 0, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(10, 0, 0),
			"neck": Vector3(12, 0, 0), "head": Vector3(14, 0, 0),
			"thigh_l": Vector3(-60, 0, 0), "shin_l": Vector3(115, 0, 0), "thigh_r": Vector3(-55, 0, 0), "shin_r": Vector3(110, 0, 0),
			"upper_arm_l": Vector3(-10, 0, -10), "upper_arm_r": Vector3(-10, 0, 10), "forearm_l": Vector3(-20, 0, 0), "forearm_r": Vector3(-20, 0, 0) }),
		key(0.95, { "move:root": Vector3(0, -0.92, -0.25), "root": Vector3(-82, 0, 0), "hips": Vector3(4, 0, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(-2, 0, 0),
			"neck": Vector3(-6, 0, 0), "head": Vector3(-8, 0, 14),
			"thigh_l": Vector3(-20, 0, 0), "shin_l": Vector3(40, 0, 0), "thigh_r": Vector3(-10, 0, 0), "shin_r": Vector3(22, 0, 0),
			"upper_arm_l": Vector3(-30, 0, 45), "upper_arm_r": Vector3(-20, 0, -55), "forearm_l": Vector3(-30, 0, 0), "forearm_r": Vector3(-10, 0, 0) }, "snap"),
		key(1.5, { "move:root": Vector3(0, -0.94, -0.28), "root": Vector3(-86, 0, 0), "hips": Vector3(2, 0, 0), "chest": Vector3(-2, 0, 0),
			"neck": Vector3(-4, 0, 0), "head": Vector3(-4, 0, 18),
			"thigh_l": Vector3(-12, 0, 0), "shin_l": Vector3(24, 0, 0), "thigh_r": Vector3(-6, 0, 0), "shin_r": Vector3(12, 0, 0),
			"upper_arm_l": Vector3(-20, 0, 55), "upper_arm_r": Vector3(-15, 0, -60), "forearm_l": Vector3(-10, 0, 0), "forearm_r": Vector3(-5, 0, 0) }),
	]
	keyed(t, keys, b)


## Airborne (a generic jump, speed-scaled by the body to the leap's air
## time): legs tuck, then reach for the ground; the arms balance.
static func jump(t: float, b: HHPlayerBody, carry: Dictionary, d: float) -> void:
	var keys := [
		key(0.0, merge(carry, { "move:root": Vector3(0, 0.02, 0), "hips": Vector3(6, 0, 0), "chest": Vector3(-6, 0, 0),
			"thigh_l": Vector3(-30, 0, 0), "shin_l": Vector3(20, 0, 0), "thigh_r": Vector3(10, 0, 0), "shin_r": Vector3(45, 0, 0) })),
		key(d * 0.45, merge(carry, { "move:root": Vector3(0, 0.08, 0), "hips": Vector3(12, 0, 0), "chest": Vector3(-4, 0, 0),
			"thigh_l": Vector3(-70, 0, 0), "shin_l": Vector3(85, 0, 0), "thigh_r": Vector3(-60, 0, 0), "shin_r": Vector3(95, 0, 0) })),
		key(d, merge(carry, { "move:root": Vector3(0, 0.0, 0), "hips": Vector3(4, 0, 0), "chest": Vector3(2, 0, 0),
			"thigh_l": Vector3(-25, 0, 0), "shin_l": Vector3(20, 0, 0), "thigh_r": Vector3(-25, 0, 0), "shin_r": Vector3(20, 0, 0),
			"foot_l": [Vector3(0.15, ANKLE_Y + 0.05, 0.1), 10.0], "foot_r": [Vector3(-0.15, ANKLE_Y + 0.05, 0.1), 10.0] })),
	]
	keyed(t, keys, b)


## H56 (Lane W): the dash, 0.36 s. A low forward burst: the hips drop and
## drive forward, the chest pitches over the lead knee, the arms sweep back
## (the weapon trails), the rear leg extends; then it gathers back up. The
## body speed-scales the burst to the sim's dash ticks.
static func dash(t: float, b: HHPlayerBody, carry: Dictionary) -> void:
	var lean := merge(carry, { "move:root": Vector3(0, -0.2, 0.12), "hips": Vector3(22, 0, 0), "spine": Vector3(14, 0, 0), "chest": Vector3(10, 0, 0),
		"neck": Vector3(-14, 0, 0), "head": Vector3(-16, 0, 0),
		"upper_arm_l": Vector3(38, 0, 14), "upper_arm_r": Vector3(38, 0, -14), "forearm_l": Vector3(-18, 0, 0), "forearm_r": Vector3(-18, 0, 0),
		"foot_l": [Vector3(0.15, ANKLE_Y + 0.02, 0.42), 0.0], "foot_r": [Vector3(-0.15, ANKLE_Y + 0.12, -0.62), 25.0] })
	var keys := [
		key(0.0, merge(carry, { "move:root": Vector3(0, -0.06, 0), "hips": Vector3(8, 0, 0), "chest": Vector3(4, 0, 0),
			"foot_l": [Vector3(0.14, ANKLE_Y, 0.08), 0.0], "foot_r": [Vector3(-0.14, ANKLE_Y, -0.1), 0.0] })),
		key(0.06, lean, "snap"),
		key(0.2, lean),
		key(0.36, merge(carry, { "move:root": Vector3(0, -0.04, 0), "hips": Vector3(4, 0, 0),
			"foot_l": [Vector3(0.14, ANKLE_Y, 0.06), 0.0], "foot_r": [Vector3(-0.14, ANKLE_Y, -0.06), 0.0] })),
	]
	keyed(t, keys, b)


# ------------------------------------------------------------------ combo strings (H60, Lane X)
# The melee-string machinery, ported from Black | White's strike rig
# (game/src/game/character/anim_action.gd + anim_clips.gd _strike_sword):
#   * beats: the approved flamberge strike's twelve beats (REF_BEATS),
#     retimed onto each hit's SIM timing (contact = the wind-up ticks, the
#     follow-through over the recovery ticks) like _melee()/_warp() retime
#     the reference per style;
#   * root-frame hands: hands are authored relative to the travelling root
#     (B|W meta hand_frame "root"), so a lunge carries the weapon with it
#     and the cut still lands on the target line;
#   * plants: feet only move between plants, on an arc (B|W's foot plant
#     schedule), so the lunge and the hop home never skate;
#   * impact: the hit-stop's two near-still frames plus a decaying shudder.
# Root travel is view-only (move:root) and every hit returns it to zero.

## Black | White's reference strike beats (frames of the flamberge strike, anim_action.gd).
const REF_BEATS := [0.0, 4.0, 8.0, 10.0, 13.0, 14.0, 18.0, 22.0, 27.0, 30.0, 36.0, 40.0]
const BEAT_NAMES := ["start", "wind", "coil", "launch", "land", "hit", "over", "settle", "hop_start", "hop_end", "recovered", "end"]


## The beats of one string hit, in clip seconds: the reference's wind-up
## (f0-f14) stretched onto `windup` ticks so "hit" is the contact tick, and
## its follow-through (f14-f36) onto the `recovery` ticks plus `settle`
## more (the hop home may run past the sim's root). "end" closes the clip.
## Extra: "stop" = hit + 2 ticks (B|W's two hit-stop frames).
static func beats(windup: int, recovery: int, settle: int = 0) -> Dictionary:
	var out := {}
	var hit := float(windup) * T
	var tail := float(recovery + settle) * T
	for i in REF_BEATS.size():
		var f := float(REF_BEATS[i])
		if f <= 14.0:
			out[BEAT_NAMES[i]] = hit * f / 14.0
		else:
			out[BEAT_NAMES[i]] = hit + tail * (f - 14.0) / 22.0
	out["end"] = minf(float(out.end), hit + tail)
	out["stop"] = hit + 2.0 * T
	return out


## A pose with its hands moved into the root frame (B|W hand_frame "root"):
## an unanchored hand's position is authored relative to the root, so it
## travels with "move:root" (the lunge carries the weapon).
static func rooted(pose: Dictionary) -> Dictionary:
	var r: Vector3 = pose.get("move:root", Vector3.ZERO)
	if r == Vector3.ZERO:
		return pose
	var out := pose.duplicate()
	for k in ["hand_l", "hand_r"]:
		if out.has(k) and str((out[k] as Dictionary).anchor) == "":
			var h: Dictionary = (out[k] as Dictionary).duplicate()
			h.pos = (h.pos as Vector3) + r
			out[k] = h
	return out


## `key` with the pose in the root frame.
static func rkey(t: float, pose: Dictionary, ease_kind: String = "ss") -> Dictionary:
	return key(t, rooted(pose), ease_kind)


## A foot that moves only between plants (B|W's plant schedule): `track`
## is [[t_lift, t_land, ankle pos (model), lift (m, optional)], ...] in time
## order; entry 0 is where the foot starts (its times are ignored). Between
## a lift and its land the ankle swings on a quintic ease with an arc
## (min(lift, 0.05 + 0.22 x distance), B|W's swing), the toes peel down at
## the lift and the heel strikes at the land. Returns [pos, pitch].
static func plant(t: float, track: Array) -> Array:
	var cur: Vector3 = track[0][2]
	for i in range(1, track.size()):
		var e: Array = track[i]
		var t0 := float(e[0])
		var t1 := float(e[1])
		var nxt: Vector3 = e[2]
		if t < t0:
			return [cur, 0.0]
		if t < t1:
			var q := clampf((t - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0)
			var ez := 10.0 * pow(q, 3) - 15.0 * pow(q, 4) + 6.0 * pow(q, 5)
			var pos := cur.lerp(nxt, ez)
			var d := Vector2(nxt.x - cur.x, nxt.z - cur.z).length()
			var lift := float(e[3]) if e.size() > 3 else 0.14
			if e.size() <= 3:
				lift = minf(lift, 0.05 + d * 0.22)
			pos.y += lift * pow(sin(PI * pow(q, 0.8)), 1.2)
			var pitch := 22.0 * sin(PI * q) * (1.0 - q) - 10.0 * q * q * (1.0 - q) * 4.0
			return [pos, pitch]
		cur = nxt
	return [cur, 0.0]


## Both feet from their plant tracks (after the keys: these win).
static func feet(t: float, b: HHPlayerBody, track_l: Array, track_r: Array) -> void:
	var fl := plant(t, track_l)
	var fr := plant(t, track_r)
	b.ik_foot("l", fl[0], float(fl[1]))
	b.ik_foot("r", fr[0], float(fr[1]))


## The contact: B|W's hit-stop (two near-still frames: the keys hold) and a
## shudder through the body that dies over `life` (amp in degrees).
static func impact(b: HHPlayerBody, t: float, t_hit: float, life: float, amp: float, hz: float = 16.0) -> void:
	var sh := shake(t, t_hit, life, hz)
	b.rot("chest", Vector3(amp * sh, 0.0, 0.4 * amp * sh))
	b.rot("head", Vector3(1.3 * amp * sh, 0.0, 0.0))
	b.move("root", Vector3(0.0, -0.004 * amp * absf(sh), 0.0))


## A ready loop between string hits: the hit's last pose, breathing hard.
static func ready_loop(t: float, b: HHPlayerBody, pose: Dictionary) -> void:
	apply(b, rooted(pose))
	breath(b, t, 1.1, 1.0)
	b.move("root", Vector3(0.0, -0.008 * (0.5 - 0.5 * cos(TAU * t / 1.1)), 0.0))
