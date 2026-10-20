class_name HHSpirewalkerClips
extends RefCounted
## Spirewalker's clips: pose functions of time on an HHMonsterBody (H305),
## the HHSwampfangClips pattern. Heavy, planted, sudden: long anticipations
## on six splayed legs, one short release, a held contact, follow-through in
## the reeds and tail. The ground shapes carry the danger (H13); the reeds
## carry the tells (fold flat before the squash, arcs before the pollen).
##
## CLIPS: { name: { duration (s), contact_tick (30 Hz tick when damage lands;
## -1 none), loop, key (preview moment, s), note } }. The brain
## (HHSpirewalker) starts the clip and the telegraph on the same tick with a
## window of contact_tick x windup_mult (H38) and plays the clip slowed to match.
##
## Bone names (art/monsters/monsters.json): root, hips, spine_0, spine_1,
## chest, neck, head, jaw, tail_0..tail_2, reed_0 (rear) reed_1 (mid) reed_2
## (front; vertical bones on the back), and per leg fl / fr (forearms) ml /
## mr / hl / hr: hip_, knee_, ankle_, toe_.
## Axes (HHMonsterBody.rot): pitch about X (+ drops a forward tip, lifts a
## tail tip, leans a reed forward), yaw about Y (+ swings a forward tip to
## the monster's left, so a LEFT leg's tip goes backward and a right leg's
## forward), roll about Z (+ lifts a left leg, drops a right one).

const T := 1.0 / 30.0

const CLIPS := {
	"calm_soak":        { "duration": 6.0, "contact_tick": -1, "loop": true,  "key": 1.5, "note": "motionless, planted low, reeds raised to the sky; the only motion is a spark shiver in the reeds and a slow breath" },
	"aggravated_idle":  { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "up on the legs, head scanning, jaw ajar, reeds swaying, forearms shifting" },
	"walk":             { "duration": 1.8, "contact_tick": -1, "loop": true,  "key": 0.45, "note": "six-leg crab tripod gait: fl+mr+hl against fr+ml+hr, body rocks, reeds lag" },
	"reeds_fold":       { "duration": 0.8, "contact_tick": -1, "loop": false, "key": 0.6, "note": "the squash tell: the reed bed slams flat backward, the body crouches" },
	"leaping_squash":   { "duration": 2.4, "contact_tick": 36, "loop": false, "key": 1.25, "note": "reeds fold (0-0.5), deep crouch legs splayed (0.4-0.9), launch and tuck (0.9-1.1), lands flat and wide at 1.2, reeds whip forward, recover" },
	"forearm_punch":    { "duration": 2.0, "contact_tick": 30, "loop": false, "key": 1.0, "note": "left forearm rears high and back (0-0.8), hammers down-forward (0.8-1.0), held, recover" },
	"bite":             { "duration": 1.8, "contact_tick": 27, "loop": false, "key": 0.9, "note": "head rears up and back jaws wide (0-0.6), lunges down-forward, snaps at 0.9, shakes, recover" },
	"barb_throw":       { "duration": 2.0, "contact_tick": 33, "loop": false, "key": 1.1, "note": "both forearms raise wide (0-0.7), whip inward-forward fast (0.7-1.1): the bristles fire, recover" },
	"reed_lash":        { "duration": 2.2, "contact_tick": 36, "loop": false, "key": 1.2, "note": "reeds coil back (0-0.9), whip forward past vertical at 1.2, shudder, return" },
	"tail_drag":        { "duration": 2.0, "contact_tick": 33, "loop": false, "key": 1.1, "note": "hips swing one way, tail lifts and sweeps across the rear arc at 1.1, drags back" },
	"pollen_shake":     { "duration": 2.6, "contact_tick": 36, "loop": false, "key": 1.3, "note": "rises tall, reeds erect, a shake grows (0-1.2), full shudder at 1.2-1.9 (the cloud), settles" },
	"thunder_breath":   { "duration": 2.2, "contact_tick": 33, "loop": false, "key": 1.1, "note": "head back and up, jaws wide, chest fills (0-0.9); head thrusts forward at 1.1, held with a crackle jitter" },
	"dark_breath":      { "duration": 2.2, "contact_tick": 33, "loop": false, "key": 1.1, "note": "head low and back (0-0.9), sweeps forward and side to side from 1.1, held, recover" },
	"spore_spread":     { "duration": 2.4, "contact_tick": 36, "loop": false, "key": 1.2, "note": "hunkers, reeds fan apart front and back (0-1.0), a body heave at 1.2 throws the spores, trembling" },
	"hit_react":        { "duration": 0.6, "contact_tick": -1, "loop": false, "key": 0.1, "note": "head yanks aside, body dips, reeds rattle" },
	"stagger":          { "duration": 1.5, "contact_tick": -1, "loop": false, "key": 0.5, "note": "legs buckle, belly to the ground, head low, slow recover" },
	"collapse":         { "duration": 2.0, "contact_tick": -1, "loop": false, "key": 1.6, "note": "down onto the belly, six legs splay flat, reeds droop, holds" },
	"death":            { "duration": 3.0, "contact_tick": -1, "loop": false, "key": 2.6, "note": "collapse, then rolls onto its side with the legs curling in, reeds flat, holds" },
	"reeds_burnt_idle": { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "reeds flat and limp, body low and sluggish, head hanging: no pollen" },
}

const SPINE := ["hips", "spine_0", "spine_1", "chest"]
const NECK := ["neck", "head"]
const TAIL := ["tail_0", "tail_1", "tail_2"]
const REEDS := ["reed_0", "reed_1", "reed_2"]
const ARMS := ["fl", "fr"]
const LEGS := ["fl", "fr", "ml", "mr", "hl", "hr"]
const TRIPOD_A := ["fl", "mr", "hl"]
const TRIPOD_B := ["fr", "ml", "hr"]
const FOLD_DEG := -82.0      ## reed pitch when the bed lies flat backward
const AXIS_H := 1.1          ## height of the body's long axis (rolls pivot here)


static func clip_list() -> PackedStringArray:
	return PackedStringArray(CLIPS.keys())


static func pose(clip: String, t: float, b: HHMonsterBody) -> void:
	match clip:
		"calm_soak": _calm_soak(t, b)
		"aggravated_idle": _aggravated_idle(t, b)
		"walk": _walk(t, b)
		"reeds_fold": _reeds_fold(t, b)
		"leaping_squash": _leaping_squash(t, b)
		"forearm_punch": _forearm_punch(t, b)
		"bite": _bite(t, b)
		"barb_throw": _barb_throw(t, b)
		"reed_lash": _reed_lash(t, b)
		"tail_drag": _tail_drag(t, b)
		"pollen_shake": _pollen_shake(t, b)
		"thunder_breath": _thunder_breath(t, b)
		"dark_breath": _dark_breath(t, b)
		"spore_spread": _spore_spread(t, b)
		"hit_react": _hit_react(t, b)
		"stagger": _stagger(t, b)
		"collapse": _collapse(t, b)
		"death": _death(t, b)
		"reeds_burnt_idle": _reeds_burnt_idle(t, b)


# ------------------------------------------------------------------ helpers

static func _ss(t: float, a: float, c: float) -> float:
	if c <= a:
		return 1.0 if t >= c else 0.0
	return smoothstep(0.0, 1.0, clampf((t - a) / (c - a), 0.0, 1.0))


static func _snap(t: float, a: float, c: float) -> float:
	var u := clampf((t - a) / maxf(c - a, 1e-4), 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


static func _coil(t: float, a: float, c: float) -> float:
	var u := clampf((t - a) / maxf(c - a, 1e-4), 0.0, 1.0)
	return u * u * u


static func _shake(t: float, t0: float, life: float, hz: float) -> float:
	if t < t0:
		return 0.0
	var u := (t - t0) / maxf(life, 1e-4)
	if u >= 1.0:
		return 0.0
	return sin((t - t0) * TAU * hz) * (1.0 - u) * (1.0 - u)


static func _over(t: float, a: float, c: float, end: float, amt: float) -> float:
	if t <= c:
		return _snap(t, a, c)
	var u := clampf((t - c) / maxf(end - c, 1e-4), 0.0, 1.0)
	return 1.0 + amt * sin(u * PI) * (1.0 - u)


## Roll the whole body about its long axis at height h (H307), never the ground origin.
static func _roll_about(b: HHMonsterBody, roll_deg: float, h: float) -> void:
	var c := Vector3(0.0, h, 0.0)
	b.rot("root", Vector3(0.0, 0.0, roll_deg))
	b.move("root", c - Basis(Vector3.BACK, deg_to_rad(roll_deg)) * c)


static func _side(leg: String) -> float:
	return 1.0 if leg.ends_with("l") else -1.0


## The reed bed: `raise` 0 = flat backward (FOLD_DEG), 1 = erect; plus a
## sway (pitch) and a rattle (roll) applied to every row with a lag.
static func _reeds(b: HHMonsterBody, raise: float, sway_deg: float = 0.0, rattle_deg: float = 0.0) -> void:
	for k in REEDS.size():
		var lag := 1.0 - 0.15 * k
		b.rot(REEDS[k], Vector3(FOLD_DEG * (1.0 - raise) + sway_deg * lag, 0.0, rattle_deg * (1.0 if k % 2 == 0 else -1.0)))


static func _jaw(b: HHMonsterBody, open_deg: float) -> void:
	b.rot("jaw", Vector3(open_deg, 0.0, 0.0))


## Breathing: the carapace lifts a touch on the legs.
static func _breath(b: HHMonsterBody, t: float, period: float, amt: float) -> void:
	var s := 0.5 - 0.5 * cos(TAU * t / period)
	b.move("root", Vector3(0.0, 0.05 * amt * s, 0.0))
	b.rot("chest", Vector3(-1.5 * amt * s, 0.0, 0.0))
	b.rot("neck", Vector3(1.0 * amt * s, 0.0, 0.0))


## The tail: a yaw wave travelling down the chain.
static func _tail_sway(b: HHMonsterBody, t: float, period: float, amp_deg: float, lag: float = 0.25) -> void:
	for k in TAIL.size():
		var ph := TAU * (t / period - lag * k)
		b.rot(TAIL[k], Vector3(0.0, sin(ph) * amp_deg * (0.6 + 0.4 * k), 0.0))


## One crab leg through a stride phase 0..1 (0 = plants): stride is a yaw
## about the hip, lift a roll (signed by side) that raises the knee.
static func _leg(b: HHMonsterBody, leg: String, ph: float, stride_deg: float, lift_deg: float) -> void:
	ph = fposmod(ph, 1.0)
	var s := _side(leg)
	if ph < 0.6:
		var u := ph / 0.6
		b.rot("hip_" + leg, Vector3(0.0, s * lerpf(-stride_deg, stride_deg, u), 0.0))     # planted ahead, pushes back under the body
		b.rot("knee_" + leg, Vector3(0.0, 0.0, s * lerpf(-3.0, 4.0, u)))
	else:
		var u := (ph - 0.6) / 0.4
		var arc := sin(u * PI)
		b.rot("hip_" + leg, Vector3(0.0, s * lerpf(stride_deg, -stride_deg, smoothstep(0.0, 1.0, u)), s * lift_deg * arc))
		b.rot("knee_" + leg, Vector3(0.0, 0.0, -s * lift_deg * 0.7 * arc))
		b.rot("ankle_" + leg, Vector3(0.0, 0.0, s * lift_deg * 0.3 * arc))


## Splay: knees go out and down (the body sinks), `amt` 0..1.
static func _splay(b: HHMonsterBody, amt: float, legs: Array = LEGS) -> void:
	for leg in legs:
		var s := _side(leg)
		b.rot("hip_" + leg, Vector3(0.0, 0.0, -s * 26.0 * amt))
		b.rot("knee_" + leg, Vector3(0.0, 0.0, s * 34.0 * amt))


## Stand tall: legs straighten and push the body up, `amt` 0..1.
static func _rise(b: HHMonsterBody, amt: float) -> void:
	for leg in LEGS:
		var s := _side(leg)
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 14.0 * amt))
		b.rot("knee_" + leg, Vector3(0.0, 0.0, -s * 20.0 * amt))
	b.move("root", Vector3(0.0, 0.3 * amt, 0.0))


## A forearm: `up` lifts it off the ground (roll), `back` draws it back (yaw;
## negative swings it forward), `fold` bends the elbow.
static func _arm(b: HHMonsterBody, leg: String, up_deg: float, back_deg: float, fold_deg: float) -> void:
	var s := _side(leg)
	b.rot("hip_" + leg, Vector3(0.0, s * back_deg, s * up_deg))
	b.rot("knee_" + leg, Vector3(0.0, 0.0, s * fold_deg))


# ------------------------------------------------------------------ idles

static func _calm_soak(t: float, b: HHMonsterBody) -> void:
	# planted low, reeds raised and still but for a spark shiver; the breath is slow
	_breath(b, t, 6.0, 0.6)
	_splay(b, 0.3)
	b.move("root", Vector3(0.0, -0.1, 0.0))
	b.rot("neck", Vector3(6.0, 0.0, 0.0))
	b.rot("head", Vector3(4.0, 2.0 * sin(TAU * t / 6.0), 0.0))
	var shiver := _shake(t, 1.0, 0.5, 22.0) + _shake(t, 3.6, 0.4, 26.0)
	_reeds(b, 1.0, 6.0 + 1.5 * sin(TAU * t / 6.0), 1.5 * shiver)
	b.bend(TAIL, Vector3(-4.0, 3.0 * sin(TAU * t / 6.0 + 1.0), 0.0))


static func _aggravated_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 3.0)
	_breath(b, t, 3.0, 1.0)
	_rise(b, 0.5)
	_roll_about(b, 1.5 * s, AXIS_H)
	b.rot("neck", Vector3(-8.0, 7.0 * sin(TAU * t / 6.0), 0.0))
	b.rot("head", Vector3(-5.0 + 2.0 * s, 5.0 * sin(TAU * t / 6.0 + 0.6), 0.0))
	_jaw(b, 6.0 + 3.0 * s)
	_reeds(b, 1.0, 4.0 * s, 2.0 * sin(TAU * t / 1.1))
	_tail_sway(b, t, 3.0, 12.0)
	_arm(b, "fl", 6.0 * maxf(s, 0.0), 4.0 * s, 0.0)
	_arm(b, "fr", 6.0 * maxf(-s, 0.0), -4.0 * s, 0.0)


static func _walk(t: float, b: HHMonsterBody) -> void:
	var ph := t / 1.8
	for leg in TRIPOD_A:
		_leg(b, leg, ph, 22.0, 30.0)
	for leg in TRIPOD_B:
		_leg(b, leg, ph + 0.5, 22.0, 30.0)
	_rise(b, 0.4)
	var rock := sin(TAU * ph) * 4.0
	_roll_about(b, rock, AXIS_H)
	b.move("root", Vector3(0.0, 0.06 * cos(TAU * ph * 2.0), 0.0))
	b.bend(SPINE, Vector3(0.0, -4.0 * sin(TAU * ph), -rock * 0.4), 1.2)
	b.rot("neck", Vector3(-6.0 - 2.0 * cos(TAU * ph * 2.0), 3.0 * sin(TAU * ph), 0.0))
	b.rot("head", Vector3(-2.0 + 2.0 * cos(TAU * ph * 2.0 + 0.5), 0.0, 0.0))
	_jaw(b, 4.0)
	_reeds(b, 1.0, -5.0 * cos(TAU * ph * 2.0 - 0.6), 3.0 * sin(TAU * ph))
	_tail_sway(b, t, 1.8, 14.0, 0.2)


# ------------------------------------------------------------------ tells

static func _reeds_fold(t: float, b: HHMonsterBody) -> void:
	var f := _snap(t, 0.05, 0.5)
	_reeds(b, 1.0 - f, 0.0, 4.0 * _shake(t, 0.5, 0.3, 16.0))
	_splay(b, 0.5 * f)
	b.move("root", Vector3(0.0, -0.25 * f, 0.0))
	b.rot("neck", Vector3(8.0 * f, 0.0, 0.0))
	b.rot("head", Vector3(6.0 * f, 0.0, 0.0))


# ------------------------------------------------------------------ attacks

static func _leaping_squash(t: float, b: HHMonsterBody) -> void:
	# tell: reeds fold flat (0-0.5); coil: deep crouch on splayed legs
	# (0.4-0.9); launch (0.9-1.0); air tuck (1.0-1.2); slam at 1.2: body flat
	# and wide, reeds whip forward; recover (1.6-2.4). The sim flies the unit
	# (begin_leap); the clip never moves the root horizontally.
	var fold := _snap(t, 0.0, 0.5)
	var crouch := _coil(t, 0.4, 0.9)
	var launch := _snap(t, 0.9, 1.0)
	var tuck := _ss(t, 1.0, 1.15)
	var slam := _snap(t, 1.15, 1.25)
	var rec := _ss(t, 1.6, 2.4)
	var down := crouch * (1.0 - launch)
	var splat := slam * (1.0 - rec)
	var whip := _over(t, 1.15, 1.3, 1.8, 0.4) * slam * (1.0 - rec)
	b.move("root", Vector3(0.0, -0.45 * down + 0.35 * launch * (1.0 - tuck) - 0.5 * splat, 0.0))
	_splay(b, 0.8 * down + 1.0 * splat)
	for leg in LEGS:
		var s := _side(leg)
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 30.0 * launch * (1.0 - slam)))     # legs drive and then tuck
		b.rot("knee_" + leg, Vector3(0.0, 0.0, s * 45.0 * tuck * (1.0 - slam)))
	b.bend(SPINE, Vector3(6.0 * down - 10.0 * launch * (1.0 - slam) + 4.0 * splat, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(12.0 * down - 16.0 * launch * (1.0 - slam) + 14.0 * splat, 0.0, 0.0))
	b.rot("head", Vector3(8.0 * down - 8.0 * launch * (1.0 - slam) + 10.0 * splat, 0.0, 0.0))
	_jaw(b, 4.0 * down + 24.0 * launch * (1.0 - rec))
	_reeds(b, (1.0 - fold) * (1.0 - slam) + whip * 0.9 * (1.0 - rec) + rec, 65.0 * whip * (1.0 - rec), 6.0 * _shake(t, 1.25, 0.6, 14.0))
	b.bend(TAIL, Vector3(-20.0 * down + 30.0 * launch * (1.0 - slam) - 12.0 * splat, 0.0, 0.0), 1.3)


static func _forearm_punch(t: float, b: HHMonsterBody) -> void:
	# the left forearm rears high and back (0-0.8), hammers down and forward (0.8-1.0, contact 1.0)
	var a := _ss(t, 0.0, 0.8)
	var w := _snap(t, 0.8, 1.0)
	var rec := _ss(t, 1.4, 2.0)
	var k := a * (1.0 - w)
	var hit := w * (1.0 - rec)
	_arm(b, "fl", 70.0 * k - 6.0 * hit, 35.0 * k - 75.0 * hit, -40.0 * k + 24.0 * hit)   # rears up and back, hammers out in front
	_arm(b, "fr", 0.0, 12.0 * k - 8.0 * hit, 0.0)
	_roll_about(b, 7.0 * k - 5.0 * hit, AXIS_H)
	b.move("root", Vector3(0.0, 0.12 * k - 0.18 * hit, 0.0))
	b.bend(SPINE, Vector3(-4.0 * k + 5.0 * hit, 10.0 * k - 14.0 * hit, 0.0), 1.2)
	b.rot("neck", Vector3(-8.0 * k + 10.0 * hit, 14.0 * k - 12.0 * hit, 0.0))
	b.rot("head", Vector3(0.0, 8.0 * k - 6.0 * hit, 0.0))
	_jaw(b, 6.0 * k + 18.0 * hit)
	_reeds(b, 1.0, -10.0 * k + 18.0 * hit, 4.0 * _shake(t, 1.0, 0.5, 14.0))
	_splay(b, 0.3 * k + 0.5 * hit, ["ml", "mr", "hl", "hr"])
	_tail_sway(b, t, 2.0, 8.0)


static func _bite(t: float, b: HHMonsterBody) -> void:
	# head rears up and back with the jaws wide (0-0.6); lunge down-forward,
	# snap shut at 0.9; a shake; recover
	var a := _ss(t, 0.0, 0.6)
	var l := _snap(t, 0.6, 0.9)
	var rec := _ss(t, 1.3, 1.8)
	var k := a * (1.0 - l)
	var lunge := l * (1.0 - rec)
	var sh := _shake(t, 0.9, 0.5, 9.0) * lunge
	b.move("root", Vector3(0.0, 0.15 * k - 0.1 * lunge, -0.15 * k + 0.35 * lunge))
	b.bend(SPINE, Vector3(-8.0 * k + 6.0 * lunge, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-30.0 * k + 18.0 * lunge, 3.0 * sh, 0.0))
	b.rot("head", Vector3(-18.0 * k + 16.0 * lunge, 4.0 * sh, 0.0))
	_jaw(b, 38.0 * a * (1.0 - l) + 4.0 * lunge)
	_arm(b, "fl", 10.0 * k, -8.0 * k + 14.0 * lunge, 0.0)
	_arm(b, "fr", 10.0 * k, 8.0 * k - 14.0 * lunge, 0.0)
	_splay(b, 0.35 * lunge, ["hl", "hr"])
	_reeds(b, 1.0, -8.0 * k + 12.0 * lunge, 3.0 * sh)
	b.bend(TAIL, Vector3(10.0 * k - 8.0 * lunge, 0.0, 0.0))


static func _barb_throw(t: float, b: HHMonsterBody) -> void:
	# both forearms raise out wide and back (0-0.7), whip inward-forward
	# fast (0.7-1.1): the bristles fire on the swing; recover
	var a := _ss(t, 0.0, 0.7)
	var w := _snap(t, 0.7, 1.1)
	var rec := _ss(t, 1.4, 2.0)
	var k := a * (1.0 - w)
	var fire := w * (1.0 - rec)
	for leg in ARMS:
		_arm(b, leg, 55.0 * k + 10.0 * fire, 50.0 * k - 50.0 * fire, -30.0 * k + 20.0 * fire)
	b.move("root", Vector3(0.0, 0.2 * k - 0.05 * fire, -0.1 * k + 0.15 * fire))
	b.bend(SPINE, Vector3(-8.0 * k + 6.0 * fire, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-14.0 * k + 10.0 * fire, 0.0, 0.0))
	b.rot("head", Vector3(-6.0 * k + 6.0 * fire, 0.0, 0.0))
	_jaw(b, 10.0 * k + 14.0 * fire)
	_splay(b, 0.4 * k, ["ml", "mr", "hl", "hr"])
	_reeds(b, 1.0, -6.0 * k + 10.0 * fire, 5.0 * _shake(t, 1.05, 0.5, 18.0))
	_tail_sway(b, t, 2.0, 8.0)


static func _reed_lash(t: float, b: HHMonsterBody) -> void:
	# the reeds coil back (0-0.9), whip forward past vertical at 1.2, shudder, return
	var c := _coil(t, 0.0, 0.9)
	var w := _snap(t, 0.9, 1.2)
	var rec := _ss(t, 1.6, 2.2)
	var k := c * (1.0 - w)
	var whip := w * (1.0 - rec)
	var sh := _shake(t, 1.2, 0.6, 12.0) * whip
	_reeds(b, 1.0, -55.0 * k + 75.0 * whip + 6.0 * sh, 3.0 * sh)
	b.move("root", Vector3(0.0, 0.12 * k - 0.1 * whip, -0.1 * k + 0.2 * whip))
	b.bend(SPINE, Vector3(-6.0 * k + 8.0 * whip, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(6.0 * k - 2.0 * whip, 0.0, 0.0))
	b.rot("head", Vector3(6.0 * k, 0.0, 0.0))
	_jaw(b, 4.0 * k + 10.0 * whip)
	_splay(b, 0.3 * k + 0.4 * whip, ["ml", "mr", "hl", "hr"])
	_arm(b, "fl", 0.0, 6.0 * k - 10.0 * whip, 0.0)
	_arm(b, "fr", 0.0, -6.0 * k + 10.0 * whip, 0.0)
	b.bend(TAIL, Vector3(14.0 * k - 10.0 * whip, 0.0, 0.0), 1.2)


static func _tail_drag(t: float, b: HHMonsterBody) -> void:
	# hips and tail swing to the right and lift (0-0.8); sweep across the rear
	# arc to the left and down at 1.1 (contact); drag back; settle
	var c := _ss(t, 0.0, 0.8)
	var w := _snap(t, 0.8, 1.1)
	var back := _ss(t, 1.1, 1.7)
	var rec := _ss(t, 1.7, 2.0)
	var yaw := -40.0 * c + 100.0 * w - 70.0 * back
	yaw *= (1.0 - rec)
	b.bend(TAIL, Vector3(26.0 * c * (1.0 - w) + 20.0 * w * (1.0 - back), yaw, 0.0), 0.5)   # swung from the base (a curl would hide it), lifted through the sweep
	b.bend(SPINE, Vector3(0.0, -yaw * 0.18, 0.0), 0.7)
	_roll_about(b, 6.0 * c * (1.0 - w) - 8.0 * w * (1.0 - back), AXIS_H)
	b.rot("neck", Vector3(4.0 * c, -yaw * 0.25, 0.0))
	b.rot("head", Vector3(0.0, -yaw * 0.15, 0.0))
	_splay(b, 0.35 * c + 0.3 * w * (1.0 - back), ["hl", "hr", "ml", "mr"])
	_reeds(b, 1.0, -4.0 * c, 4.0 * _shake(t, 1.1, 0.5, 12.0))


static func _pollen_shake(t: float, b: HHMonsterBody) -> void:
	# rises tall and the reeds stand erect (0-1.2) while a shudder builds; the
	# full shake at 1.2-1.9 shakes the pollen out; settles
	var up := _ss(t, 0.0, 1.0)
	var rec := _ss(t, 1.9, 2.6)
	var grow := clampf(t / 1.2, 0.0, 1.0)
	var full := _ss(t, 1.1, 1.25) * (1.0 - rec)
	var amp := 3.0 * grow * grow * (1.0 - full) + 11.0 * full
	var hz := 5.0 + 6.0 * full
	var sh := sin(t * TAU * hz)
	var sh2 := sin(t * TAU * hz * 0.5 + 0.7)
	_rise(b, 0.9 * up * (1.0 - rec))
	_reeds(b, 1.0, 10.0 * up + 2.0 * amp * sh2, amp * sh)
	_roll_about(b, 0.25 * amp * sh, AXIS_H)
	b.move("root", Vector3(0.0, 0.01 * amp * absf(sh), 0.0))
	b.rot("neck", Vector3(-14.0 * up, 0.0, 0.0))
	b.rot("head", Vector3(-10.0 * up, 0.15 * amp * sh2, 0.0))
	_jaw(b, 12.0 * up)
	_tail_sway(b, t, 0.6 / maxf(0.2, grow), 6.0 + 0.5 * amp, 0.2)
	for leg in ARMS:
		_arm(b, leg, 14.0 * up, 0.0, -10.0 * up)


static func _thunder_breath(t: float, b: HHMonsterBody) -> void:
	# the head draws back and up with the jaws wide while the chest fills
	# (0-0.9); it thrusts forward at 1.1 (contact) and holds with a crackle
	var a := _ss(t, 0.0, 0.9)
	var w := _snap(t, 0.9, 1.1)
	var rec := _ss(t, 1.7, 2.2)
	var k := a * (1.0 - w)
	var hold := w * (1.0 - rec)
	var jit := _shake(t, 1.1, 0.7, 24.0) * hold
	b.move("root", Vector3(0.0, 0.15 * k, -0.2 * k + 0.25 * hold))
	_rise(b, 0.4 * a * (1.0 - rec))
	b.bend(SPINE, Vector3(-8.0 * k + 3.0 * hold, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-34.0 * k - 2.0 * hold, 1.5 * jit, 0.0))
	b.rot("head", Vector3(-16.0 * k + 6.0 * hold, 2.0 * jit, 0.0))
	_jaw(b, 20.0 * a * (1.0 - rec) + 22.0 * hold)
	_reeds(b, 1.0, 8.0 * k - 4.0 * hold, 3.0 * jit + 1.5 * _shake(t, 0.3, 0.9, 20.0) * k)
	for leg in ARMS:
		_arm(b, leg, 0.0, -10.0 * k + 8.0 * hold, 0.0)
	_tail_sway(b, t, 2.2, 6.0)


static func _dark_breath(t: float, b: HHMonsterBody) -> void:
	# the head drops low and draws back (0-0.9), sweeps forward and side to
	# side from 1.1 (contact), held, recover
	var a := _ss(t, 0.0, 0.9)
	var w := _snap(t, 0.9, 1.1)
	var rec := _ss(t, 1.7, 2.2)
	var k := a * (1.0 - w)
	var hold := w * (1.0 - rec)
	var sweep := sin((t - 1.1) * TAU / 0.7) * hold
	b.move("root", Vector3(0.0, -0.12 * k - 0.05 * hold, -0.15 * k + 0.2 * hold))
	_splay(b, 0.35 * a * (1.0 - rec))
	b.bend(SPINE, Vector3(6.0 * k, 6.0 * sweep, 0.0), 1.3)
	b.rot("neck", Vector3(16.0 * k + 4.0 * hold, 18.0 * sweep, 0.0))
	b.rot("head", Vector3(10.0 * k - 2.0 * hold, 12.0 * sweep, 0.0))
	_jaw(b, 12.0 * a * (1.0 - rec) + 24.0 * hold)
	_reeds(b, 1.0, -6.0 * k, 2.0 * _shake(t, 1.1, 0.6, 10.0))
	b.bend(TAIL, Vector3(8.0 * k, -14.0 * sweep, 0.0))


static func _spore_spread(t: float, b: HHMonsterBody) -> void:
	# hunkers; the front rows lean forward and the rear rows back (the bed
	# fans open, 0-1.0); a body heave at 1.2 throws the spores on the wind; trembling
	var a := _ss(t, 0.0, 1.0)
	var h := _over(t, 1.0, 1.2, 1.6, 0.5)
	var rec := _ss(t, 1.8, 2.4)
	var heave := h * (1.0 - rec)
	var trem := _shake(t, 1.2, 0.9, 16.0)
	var fan := a * (1.0 - rec)
	b.rot("reed_0", Vector3(-40.0 * fan - 12.0 * heave, 0.0, 3.0 * trem))
	b.rot("reed_1", Vector3(4.0 * heave, 0.0, -3.0 * trem))
	b.rot("reed_2", Vector3(40.0 * fan + 12.0 * heave, 0.0, 3.0 * trem))
	_splay(b, 0.45 * a * (1.0 - heave * 0.5))
	b.move("root", Vector3(0.0, -0.22 * a + 0.4 * heave, 0.0))
	b.bend(SPINE, Vector3(-6.0 * heave, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(10.0 * a - 12.0 * heave, 0.0, 0.0))
	b.rot("head", Vector3(6.0 * a - 6.0 * heave, 0.0, 0.0))
	_jaw(b, 6.0 * a + 16.0 * heave)
	b.bend(TAIL, Vector3(-8.0 * a + 18.0 * heave, 0.0, 0.0), 1.2)


# ------------------------------------------------------------------ reactions

static func _hit_react(t: float, b: HHMonsterBody) -> void:
	var k := _snap(t, 0.0, 0.08) * (1.0 - _ss(t, 0.2, 0.6))
	b.rot("neck", Vector3(-8.0 * k, 16.0 * k, 0.0))
	b.rot("head", Vector3(-6.0 * k, 12.0 * k, 0.0))
	b.bend(SPINE, Vector3(0.0, 5.0 * k, 3.0 * k))
	b.move("root", Vector3(0.0, -0.08 * k, -0.1 * k))
	_jaw(b, 14.0 * k)
	_reeds(b, 1.0, -6.0 * k, 5.0 * _shake(t, 0.05, 0.45, 16.0))
	_tail_sway(b, t, 0.6, 8.0 * k)


static func _stagger(t: float, b: HHMonsterBody) -> void:
	var sag := _snap(t, 0.0, 0.25) * (1.0 - _ss(t, 0.9, 1.5))
	var wobble := _shake(t, 0.25, 1.0, 3.0)
	b.move("root", Vector3(0.0, -0.5 * sag, 0.0))
	_roll_about(b, 8.0 * wobble * sag, AXIS_H * 0.8)
	_splay(b, 0.9 * sag)
	b.bend(SPINE, Vector3(4.0 * sag, 8.0 * wobble * sag, 0.0))
	b.rot("neck", Vector3(16.0 * sag, 10.0 * wobble * sag, 0.0))
	b.rot("head", Vector3(10.0 * sag, 0.0, 0.0))
	_jaw(b, 12.0 * sag)
	_reeds(b, 1.0 - 0.45 * sag, 0.0, 4.0 * wobble * sag)
	_tail_sway(b, t, 1.5, 10.0 * sag)


static func _collapse(t: float, b: HHMonsterBody) -> void:
	var d := _ss(t, 0.0, 1.3)
	var bounce := _shake(t, 1.3, 0.6, 2.5) * 0.05
	b.move("root", Vector3(0.0, -0.7 * d + bounce, 0.0))
	_splay(b, 1.0 * d)
	b.bend(SPINE, Vector3(5.0 * d, 0.0, 0.0), 0.8)
	b.rot("neck", Vector3(18.0 * d, 0.0, 0.0))
	b.rot("head", Vector3(10.0 * d, 0.0, 0.0))
	_jaw(b, 18.0 * d)
	_reeds(b, 1.0 - 0.7 * d, 0.0, 0.0)
	b.bend(TAIL, Vector3(-8.0 * d, 0.0, 0.0))


static func _death(t: float, b: HHMonsterBody) -> void:
	# collapse (0-1.3), then the legs draw in under the carapace like a dead
	# crab's, the body lists 18 deg onto the left legs, the head rolls aside;
	# the reeds lie flat. A wide flat body never rolls over (unlike Swampfang).
	_collapse(minf(t, 2.0), b)
	var r := _ss(t, 1.4, 2.7)
	_roll_about(b, 18.0 * r, 0.45)
	b.move("root", Vector3(0.0, 0.12 * r, 0.0))
	b.rot("neck", Vector3(6.0 * r, 14.0 * r, -16.0 * r))
	b.rot("head", Vector3(0.0, 10.0 * r, -10.0 * r))
	_jaw(b, 16.0 * r)
	for leg in LEGS:
		var s := _side(leg)
		b.rot("hip_" + leg, Vector3(0.0, s * 14.0 * r, s * 38.0 * r))     # knees lift and draw in ...
		b.rot("knee_" + leg, Vector3(0.0, 0.0, -s * 52.0 * r))            # ... the shins fold under
	_reeds(b, 0.12 * (1.0 - r), 0.0, 0.0)


static func _reeds_burnt_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 3.0)
	_breath(b, t, 3.0, 0.7)
	_splay(b, 0.3)
	b.move("root", Vector3(0.0, -0.15, 0.0))
	b.rot("neck", Vector3(12.0, 4.0 * sin(TAU * t / 6.0), 0.0))
	b.rot("head", Vector3(8.0 + 1.0 * s, 0.0, 0.0))
	_jaw(b, 8.0 + 2.0 * s)
	_reeds(b, 0.1, 2.0 * s, 0.0)                                  # flat and limp
	_tail_sway(b, t, 3.0, 6.0)
