class_name HHRimeslitheClips
extends RefCounted
## Rimeslithe's clips: pose functions of time on an HHMonsterBody (H305, the
## Swampfang pattern). The heaviest monster (H13): every attack is a long
## coil, a short release and a held contact; the body settles slowly. It
## stands on its knuckles: the arms (bones hip_/knee_/ankle_/toe_ fl|fr) are
## shoulder, forearm (elbow to wrist), wrist and fist; the hind legs are
## hl|hr. Crystals ride the spine bones (chest, spine_1, spine_0, hips) and
## the head crest, so a spine shiver is a crystal shiver.
##
## CLIPS: { name: { duration (s), contact_tick (30 Hz tick when damage lands;
## -1 none), loop, key (the preview moment, s), note } }. HHRimeslithe starts
## the clip and the telegraph on the same tick with a window of contact_tick
## x TUNE.windup_mult (2.0) and plays the clip at speed contact / window, so
## the danger shape resolves exactly as the body lands the blow (H306, H38).
##
## Axes (HHMonsterBody.rot): pitch about X (+ drops a forward tip; on a
## downward bone such as the shoulder, + swings the tip backward and - swings
## it forward), yaw about Y (+ swings a tip to the monster's left), roll about
## Z (+ lifts the monster's left side).

const T := 1.0 / 30.0

const CLIPS := {
	"calm_sit":        { "duration": 6.0, "contact_tick": -1, "loop": true,  "key": 2.0, "note": "sunk onto its haunches in the shade, arms folded in, head low, slow breath" },
	"frost_over":      { "duration": 4.0, "contact_tick": -1, "loop": true,  "key": 2.0, "note": "sitting; a shiver runs up the spine and the crystals tremble as the cold charges" },
	"aggravated_idle": { "duration": 3.2, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "up on its knuckles, weight rocking fist to fist, head low and scanning, jaw ajar" },
	"roar":            { "duration": 2.6, "contact_tick": -1, "loop": false, "key": 1.1, "note": "crouch (0-0.7), rears up with both fists off the ground (0.7-0.9), held roar with shake, settle" },
	"walk":            { "duration": 2.0, "contact_tick": -1, "loop": true,  "key": 0.5, "note": "knuckle-walk: long arm strides, hind legs shuffle, the hump rolls, head bobs" },
	"frost_beam":      { "duration": 2.6, "contact_tick": 42, "loop": false, "key": 1.4, "note": "head coils up and back (0-0.9), thrusts level (0.9-1.3), beam held with a slow sweep (1.3-2.0), recover" },
	"cold_slam":       { "duration": 2.8, "contact_tick": 45, "loop": false, "key": 1.2, "note": "both fists rise (0-0.6), slam down and PLANT wide (0.6-0.95), held planted = the tell (0.95-1.35), heave (1.35-1.5), shockwave hold, recover" },
	"shoulder_charge": { "duration": 2.4, "contact_tick": 36, "loop": false, "key": 1.0, "note": "weight back and the left shoulder drops (0-0.7), drives forward fists tucked (0.7-1.2), held, recover" },
	"bite":            { "duration": 2.0, "contact_tick": 30, "loop": false, "key": 0.85, "note": "neck draws back jaws wide (0-0.6), lunges down-forward (0.6-1.0), snaps shut, recover" },
	"arm_swipe":       { "duration": 2.4, "contact_tick": 36, "loop": false, "key": 1.05, "note": "right arm lifts out wide and back (0-0.75), sweeps across the front (0.75-1.2), follow-through, recover" },
	"mist_breath":     { "duration": 3.0, "contact_tick": 36, "loop": false, "key": 1.3, "note": "chest fills head up (0-0.8), head drops and exhales (0.8-1.2), long held breath sweeping side to side, recover" },
	"meteor_drop":     { "duration": 3.4, "contact_tick": 45, "loop": false, "key": 1.45, "note": "right arm reaches back to the crystals (0-0.7), rips (0.7-0.95), hurls overhead (0.95-1.5), watches the sky, arm down" },
	"freeze_pillar":   { "duration": 2.6, "contact_tick": 39, "loop": false, "key": 1.2, "note": "fists plant, head goes to the ground (0-0.8), a breath down into the rock with a crystal shiver (0.8-1.3), hold, recover" },
	"hit_react":       { "duration": 0.6, "contact_tick": -1, "loop": false, "key": 0.1, "note": "head yanks aside, hump shudders" },
	"stagger":         { "duration": 1.6, "contact_tick": -1, "loop": false, "key": 0.5, "note": "sags onto splayed arms, head drops, wobbles, slow recover" },
	"collapse":        { "duration": 2.2, "contact_tick": -1, "loop": false, "key": 1.8, "note": "down onto the belly, arms and legs splay, chin on the ground, holds" },
	"death":           { "duration": 3.2, "contact_tick": -1, "loop": false, "key": 2.8, "note": "collapse, then rolls onto its side, holds" },
}

const SPINE := ["hips", "spine_0", "spine_1", "chest"]
const NECK := ["neck", "head"]
const TAIL := ["tail_0", "tail_1", "tail_2", "tail_3"]
const ARMS := ["fl", "fr"]
const HIND := ["hl", "hr"]
const SIT := -0.3        ## root drop when sitting (m): the legs fold to keep knuckles and toes on the floor
## The digitigrade hind leg's fold per metre the hips drop (H653): hip, knee, hock
## pitch; the metatarsus keeps its angle so the ball of the foot stays down.
const SPLAY_DROP := 0.6   ## how far the splayed hind legs fold (m of hip drop)
const HIND_FOLD := Vector3(-28.0, 56.0, -28.0)


static func clip_list() -> PackedStringArray:
	return PackedStringArray(CLIPS.keys())


static func pose(clip: String, t: float, b: HHMonsterBody) -> void:
	match clip:
		"calm_sit": _calm_sit(t, b)
		"frost_over": _frost_over(t, b)
		"aggravated_idle": _aggravated_idle(t, b)
		"roar": _roar(t, b)
		"walk": _walk(t, b)
		"frost_beam": _frost_beam(t, b)
		"cold_slam": _cold_slam(t, b)
		"shoulder_charge": _shoulder_charge(t, b)
		"bite": _bite(t, b)
		"arm_swipe": _arm_swipe(t, b)
		"mist_breath": _mist_breath(t, b)
		"meteor_drop": _meteor_drop(t, b)
		"freeze_pillar": _freeze_pillar(t, b)
		"hit_react": _hit_react(t, b)
		"stagger": _stagger(t, b)
		"collapse": _collapse(t, b)
		"death": _death(t, b)


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


## Roll the whole body about its long axis at height `h` (H307).
static func _roll_about(b: HHMonsterBody, roll_deg: float, h: float) -> void:
	var c := Vector3(0.0, h, 0.0)
	b.rot("root", Vector3(0.0, 0.0, roll_deg))
	b.move("root", c - Basis(Vector3.BACK, deg_to_rad(roll_deg)) * c)


static func _jaw(b: HHMonsterBody, open_deg: float) -> void:
	b.rot("jaw", Vector3(open_deg, 0.0, 0.0))


static func _sign(side: String) -> float:
	return 1.0 if side.ends_with("l") else -1.0


## One arm: shoulder (pitch, yaw, roll), forearm pitch (- lifts the wrist),
## wrist pitch (- lifts the fist's knuckles).
static func _arm(b: HHMonsterBody, side: String, sh: Vector3, fore: float, wrist: float = 0.0) -> void:
	b.rot("hip_" + side, sh)
	b.rot("knee_" + side, Vector3(fore, 0.0, 0.0))
	b.rot("ankle_" + side, Vector3(wrist, 0.0, 0.0))


## Both arms planted: elbows out, shoulders rolled outward, forearms pressing.
static func _plant(b: HHMonsterBody, amt: float) -> void:
	for side in ARMS:
		var s := _sign(side)
		_arm(b, side, Vector3(-4.0 * amt, 0.0, s * 16.0 * amt), 6.0 * amt, -4.0 * amt)


## An arm's stride: phase 0..1 (0 = fist plants). Stance drags the body over
## the fist; swing lifts the wrist (forearm -pitch), carries the arm forward.
static func _arm_step(b: HHMonsterBody, side: String, ph: float, stride_deg: float, lift_deg: float) -> void:
	ph = fposmod(ph, 1.0)
	if ph < 0.58:
		var u := ph / 0.58
		_arm(b, side, Vector3(lerpf(-stride_deg, stride_deg, u), 0.0, 0.0), lerpf(3.0, -3.0, u), lerpf(-2.0, 4.0, u))
	else:
		var u := (ph - 0.58) / 0.42
		var arc := sin(u * PI)
		_arm(b, side, Vector3(lerpf(stride_deg, -stride_deg, smoothstep(0.0, 1.0, u)), 0.0, 0.0), -lift_deg * arc, lift_deg * 0.5 * arc)


## A hind leg's stride (Swampfang's _leg): a downward bone swings forward with -pitch.
static func _leg_step(b: HHMonsterBody, leg: String, ph: float, stride_deg: float, lift_deg: float) -> void:
	ph = fposmod(ph, 1.0)
	if ph < 0.6:
		var u := ph / 0.6
		b.rot("hip_" + leg, Vector3(lerpf(-stride_deg, stride_deg, u), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lerpf(-4.0, 6.0, u), 0.0, 0.0))
	else:
		var u := (ph - 0.6) / 0.4
		var arc := sin(u * PI)
		b.rot("hip_" + leg, Vector3(lerpf(stride_deg, -stride_deg, smoothstep(0.0, 1.0, u)), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lift_deg * arc, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-lift_deg * 0.6 * arc, 0.0, 0.0))


static func _tail_sway(b: HHMonsterBody, t: float, period: float, amp_deg: float, lag: float = 0.22) -> void:
	for k in TAIL.size():
		var ph := TAU * (t / period - lag * k)
		b.rot(TAIL[k], Vector3(0.0, sin(ph) * amp_deg * (0.6 + 0.4 * k), 0.0))


static func _breath(b: HHMonsterBody, t: float, period: float, amt: float) -> void:
	var s := 0.5 - 0.5 * cos(TAU * t / period)
	b.move("spine_1", Vector3(0.0, 0.07 * amt * s, 0.0))
	b.rot("spine_0", Vector3(-1.2 * amt * s, 0.0, 0.0))
	b.rot("chest", Vector3(1.0 * amt * s, 0.0, 0.0))
	b.rot("neck", Vector3(-1.0 * amt * s, 0.0, 0.0))


## The sitting stance: haunches down, arms folded in so the fists stay on the ground.
static func _sit(b: HHMonsterBody, amt: float) -> void:
	b.move("root", Vector3(0.0, SIT * amt, 0.0))
	b.bend(SPINE, Vector3(7.0 * amt, 0.0, 0.0), 0.8)
	b.rot("neck", Vector3(2.0 * amt, 0.0, 0.0))
	b.rot("head", Vector3(-6.0 * amt, 0.0, 0.0))
	for side in ARMS:
		var s := _sign(side)
		_arm(b, side, Vector3(8.0 * amt, 0.0, s * 10.0 * amt), -12.0 * amt, 8.0 * amt)
	for leg in HIND:
		var s := _sign(leg)
		_hind_fold(b, leg, -SIT * amt)
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 10.0 * amt))
	b.bend(TAIL, Vector3(-6.0 * amt, 0.0, 0.0))


## Fold one digitigrade hind leg for a hip drop of `drop` metres (H653).
static func _hind_fold(b: HHMonsterBody, leg: String, drop: float) -> void:
	var k := drop / 0.3
	b.rot("hip_" + leg, Vector3(HIND_FOLD.x * k * 0.3, 0.0, 0.0))
	b.rot("knee_" + leg, Vector3(HIND_FOLD.y * k * 0.3, 0.0, 0.0))
	b.rot("ankle_" + leg, Vector3(HIND_FOLD.z * k * 0.3, 0.0, 0.0))


## Arms and legs splayed under a fallen body (stagger, collapse).
static func _splay(b: HHMonsterBody, amt: float) -> void:
	for side in ARMS:
		var s := _sign(side)
		_arm(b, side, Vector3(-6.0 * amt, 0.0, s * 38.0 * amt), -22.0 * amt, 8.0 * amt)
	for leg in HIND:
		var s := _sign(leg)
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 24.0 * amt))
		_hind_fold(b, leg, SPLAY_DROP * amt)


# ------------------------------------------------------------------ idles

static func _calm_sit(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 6.0)
	_sit(b, 1.0)
	_breath(b, t, 6.0, 0.8)
	b.rot("head", Vector3(2.0 * s, 5.0 * sin(TAU * t / 12.0), 0.0))
	_jaw(b, 2.0)
	_tail_sway(b, t, 6.0, 5.0, 0.18)


static func _frost_over(t: float, b: HHMonsterBody) -> void:
	# sitting, and a shiver rolls up the spine every two seconds: the crystals tremble
	_sit(b, 1.0)
	_breath(b, t, 4.0, 0.6)
	var env := pow(maxf(0.0, sin(TAU * t / 2.0)), 3.0)
	var sh := sin(t * TAU * 11.0) * env
	for k in SPINE.size():
		b.rot(SPINE[k], Vector3(0.0, 0.0, 1.6 * sh * (0.5 + 0.5 * k)))
	b.rot("neck", Vector3(6.0 * env, 0.0, 2.0 * sh))
	b.rot("head", Vector3(5.0 * env, 0.0, 0.0))
	b.move("root", Vector3(0.012 * sh, 0.0, 0.0))
	_jaw(b, 0.0)


static func _aggravated_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 3.2)
	_breath(b, t, 3.2, 1.0)
	_roll_about(b, 2.5 * s, 1.7)
	b.rot("hip_fl", Vector3(-2.0 * s, 0.0, 0.0))
	b.rot("hip_fr", Vector3(2.0 * s, 0.0, 0.0))
	b.rot("neck", Vector3(-4.0, 8.0 * sin(TAU * t / 6.4), 0.0))
	b.rot("head", Vector3(-2.0 + 2.0 * s, 5.0 * sin(TAU * t / 6.4 + 0.5), 0.0))
	_jaw(b, 8.0 + 3.0 * s)
	_tail_sway(b, t, 3.2, 12.0)


static func _walk(t: float, b: HHMonsterBody) -> void:
	var ph := t / 2.0
	_arm_step(b, "fl", ph, 26.0, 34.0)
	_arm_step(b, "fr", ph + 0.5, 26.0, 34.0)
	_leg_step(b, "hr", ph + 0.05, 14.0, 24.0)
	_leg_step(b, "hl", ph + 0.55, 14.0, 24.0)
	var roll := sin(TAU * ph) * 5.0
	_roll_about(b, roll, 1.7)
	b.move("root", Vector3(0.0, -0.05 + 0.09 * cos(TAU * ph * 2.0), 0.0))
	b.bend(SPINE, Vector3(0.0, -5.0 * sin(TAU * ph), -roll * 0.4), 1.2)
	b.rot("neck", Vector3(-3.0 - 3.0 * cos(TAU * ph * 2.0), 4.0 * sin(TAU * ph), 0.0))
	b.rot("head", Vector3(2.0 * cos(TAU * ph * 2.0 + 0.5), 0.0, 0.0))
	_jaw(b, 6.0)
	_tail_sway(b, t, 2.0, 14.0, 0.2)


static func _roar(t: float, b: HHMonsterBody) -> void:
	# crouch (0-0.7), rear up with both fists off the ground (0.7-0.9), held roar (0.9-1.9), settle
	var a := _ss(t, 0.0, 0.7)
	var up := _over(t, 0.7, 0.9, 1.25, 0.2)
	var rel := _ss(t, 1.9, 2.6)
	var hold := _snap(t, 0.7, 0.9) * (1.0 - rel)
	var crouch := a * (1.0 - _snap(t, 0.7, 0.9))
	var sh := _shake(t, 0.9, 1.0, 10.0) * hold
	var rear := up * (1.0 - rel)
	b.move("root", Vector3(0.0, -0.3 * crouch + 0.35 * rear, -0.2 * crouch))
	b.rot("root", Vector3(-6.0 * rear, 0.0, 0.0))
	b.bend(SPINE, Vector3(6.0 * crouch - 12.0 * rear, 0.0, 0.0), 1.4)
	b.rot("neck", Vector3(10.0 * crouch - 24.0 * rear, 3.0 * sh, 0.0))
	b.rot("head", Vector3(4.0 * crouch - 18.0 * rear, 2.0 * sh, 0.0))
	_jaw(b, 4.0 * crouch + 44.0 * hold + 3.0 * sh)
	for side in ARMS:
		var s := _sign(side)
		# the fists come a metre off the floor and spread, bear-style; the forearms stay low
		_arm(b, side, Vector3(10.0 * crouch - 18.0 * rear, 0.0, s * (6.0 * crouch + 14.0 * rear)), -10.0 * crouch - 8.0 * rear, 8.0 * rear)
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(-10.0 * crouch + 22.0 * rear, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(14.0 * crouch - 10.0 * rear, 0.0, 0.0))
	b.bend(TAIL, Vector3(-8.0 * crouch + 16.0 * rear, 0.0, 0.0), 1.3)
	_tail_sway(b, t, 2.6, 5.0 + 8.0 * hold, 0.25)


# ------------------------------------------------------------------ reactions

static func _hit_react(t: float, b: HHMonsterBody) -> void:
	var k := _snap(t, 0.0, 0.08) * (1.0 - _ss(t, 0.2, 0.6))
	b.rot("neck", Vector3(-8.0 * k, 16.0 * k, 0.0))
	b.rot("head", Vector3(-6.0 * k, 12.0 * k, 0.0))
	b.bend(SPINE, Vector3(0.0, 5.0 * k, 3.0 * k))
	b.move("root", Vector3(0.0, -0.05 * k, -0.1 * k))
	_jaw(b, 16.0 * k)
	var sh := _shake(t, 0.05, 0.4, 14.0)
	b.rot("chest", Vector3(0.0, 0.0, 2.0 * sh))
	_tail_sway(b, t, 0.6, 8.0 * k)


static func _stagger(t: float, b: HHMonsterBody) -> void:
	var sag := _snap(t, 0.0, 0.25) * (1.0 - _ss(t, 1.0, 1.6))
	var wobble := _shake(t, 0.25, 1.1, 3.0)
	b.move("root", Vector3(0.0, -0.4 * sag, 0.0))
	_roll_about(b, 9.0 * wobble * sag, 1.4)
	_splay(b, 0.7 * sag)
	b.bend(SPINE, Vector3(5.0 * sag, 9.0 * wobble * sag, 0.0))
	b.rot("neck", Vector3(8.0 * sag, 10.0 * wobble * sag, 0.0))
	b.rot("head", Vector3(4.0 * sag, 0.0, 0.0))
	_jaw(b, 14.0 * sag)
	_tail_sway(b, t, 1.6, 10.0 * sag)


static func _collapse(t: float, b: HHMonsterBody) -> void:
	var d := _ss(t, 0.0, 1.4)
	var bounce := _shake(t, 1.4, 0.6, 2.5) * 0.05
	b.move("root", Vector3(0.0, -1.1 * d + bounce, 0.0))
	_splay(b, d)
	b.bend(SPINE, Vector3(2.0 * d, 0.0, 0.0), 0.8)
	b.rot("neck", Vector3(-6.0 * d, 0.0, 0.0))
	b.rot("head", Vector3(-4.0 * d, 0.0, 0.0))
	_jaw(b, 22.0 * d)
	b.bend(TAIL, Vector3(16.0 * d, 0.0, 0.0))


static func _death(t: float, b: HHMonsterBody) -> void:
	_collapse(minf(t, 2.0), b)
	var r := _ss(t, 1.6, 2.8)
	_roll_about(b, 65.0 * r, 0.9)
	b.move("root", Vector3(0.0, 0.35 * r, 0.0))
	b.rot("neck", Vector3(0.0, 0.0, -10.0 * r))
	_jaw(b, 24.0 * r)
	for side in ARMS:
		b.rot("hip_" + side, Vector3(-30.0 * r, 0.0, 0.0))
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(-25.0 * r, 0.0, 0.0))


# ------------------------------------------------------------------ attacks

static func _frost_beam(t: float, b: HHMonsterBody) -> void:
	# coil: head up and back (0-0.9); thrust level (0.9-1.3, contact 1.4); beam held sweeping; recover
	var c := _coil(t, 0.0, 0.9)
	var th := _snap(t, 0.9, 1.3)
	var rec := _ss(t, 2.0, 2.6)
	var k := c * (1.0 - th)
	var push := th * (1.0 - rec)
	var sweep := sin(TAU * (t - 1.3) / 1.4) * push * _ss(t, 1.3, 1.5)
	b.move("root", Vector3(0.0, 0.1 * k, -0.15 * k + 0.25 * push))
	b.bend(SPINE, Vector3(-5.0 * k - 3.0 * push, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-26.0 * k + 2.0 * push, 10.0 * sweep, 0.0))
	b.rot("head", Vector3(-12.0 * k + 8.0 * push, 8.0 * sweep, 0.0))
	_jaw(b, 10.0 * c + 36.0 * push + 2.0 * _shake(t, 1.3, 0.8, 18.0) * push)
	for side in ARMS:
		_arm(b, side, Vector3(6.0 * k + 8.0 * push, 0.0, 0.0), -3.0 * k, 0.0)       # braces back, then shoves
	_tail_sway(b, t, 2.6, 6.0, 0.25)


static func _cold_slam(t: float, b: HHMonsterBody) -> void:
	# fists rise (0-0.6), slam down and plant wide (0.6-0.95), held planted = the tell
	# (0.95-1.35), the heave (1.35-1.5, contact 1.5), shockwave hold, recover
	var lift := _ss(t, 0.0, 0.6) * (1.0 - _snap(t, 0.6, 0.95))
	var planted := _snap(t, 0.6, 0.95) * (1.0 - _ss(t, 2.2, 2.8))
	var heave := _snap(t, 1.35, 1.5) * (1.0 - _ss(t, 2.0, 2.8))
	var sh := _shake(t, 1.5, 0.7, 6.0)
	b.move("root", Vector3(0.0, 0.25 * lift - 0.3 * heave + 0.03 * sh, -0.1 * lift + 0.15 * heave))
	b.bend(SPINE, Vector3(-8.0 * lift + 6.0 * planted + 10.0 * heave, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-10.0 * lift + 10.0 * planted + 12.0 * heave, 0.0, 0.0))
	b.rot("head", Vector3(-6.0 * lift + 4.0 * planted + 6.0 * heave, 0.0, 0.0))
	_jaw(b, 6.0 * lift + 8.0 * planted + 20.0 * heave)
	for side in ARMS:
		var s := _sign(side)
		# raised: shoulders swing forward and up, forearms fold up; planted: elbows out and locked
		_arm(b, side, Vector3(-60.0 * lift - 2.0 * planted + 6.0 * heave, 0.0, s * (10.0 * lift + 20.0 * planted)),
			-34.0 * lift + 6.0 * planted + 3.0 * heave, 16.0 * lift - 4.0 * planted)
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(6.0 * lift - 8.0 * heave, 0.0, 0.0))
	b.bend(TAIL, Vector3(10.0 * lift - 8.0 * heave, 0.0, 0.0), 1.3)


static func _shoulder_charge(t: float, b: HHMonsterBody) -> void:
	# weight back, left shoulder drops (0-0.7); drive (0.7-1.2, contact 1.2); hold; recover
	var c := _coil(t, 0.0, 0.7)
	var dr := _snap(t, 0.7, 1.2)
	var rec := _ss(t, 1.6, 2.4)
	var k := c * (1.0 - dr)
	var push := dr * (1.0 - rec)
	b.move("root", Vector3(0.0, -0.15 * k + 0.1 * push, -0.35 * k + 0.9 * push))
	_roll_about(b, -8.0 * k - 16.0 * push, 1.9)
	b.bend(SPINE, Vector3(4.0 * k - 3.0 * push, 10.0 * k - 12.0 * push, 0.0), 1.2)
	b.rot("neck", Vector3(8.0 * k + 4.0 * push, 16.0 * k - 6.0 * push, 0.0))
	b.rot("head", Vector3(4.0 * k, 10.0 * k - 6.0 * push, 0.0))
	_jaw(b, 6.0 * k + 18.0 * push)
	for side in ARMS:
		var s := _sign(side)
		_arm(b, side, Vector3(18.0 * k - 10.0 * push, 0.0, s * 8.0 * push), -6.0 * k - 12.0 * push, 8.0 * push)
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(-10.0 * k + 18.0 * push, 0.0, 0.0))
	_tail_sway(b, t, 2.4, 6.0 + 8.0 * push, 0.25)


static func _bite(t: float, b: HHMonsterBody) -> void:
	# draw back jaws wide (0-0.6), lunge down-forward (0.6-1.0, contact 1.0), snap, recover
	var d := _ss(t, 0.0, 0.6)
	var l := _snap(t, 0.6, 1.0)
	var shut := _snap(t, 0.95, 1.05)
	var rec := _ss(t, 1.3, 2.0)
	var k := d * (1.0 - l)
	var push := l * (1.0 - rec)
	b.move("root", Vector3(0.0, 0.05 * k, -0.12 * k + 0.5 * push))
	b.bend(SPINE, Vector3(-3.0 * k + 6.0 * push, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-18.0 * k + 6.0 * push, 0.0, 0.0))
	b.rot("head", Vector3(-12.0 * k + 2.0 * push, 0.0, 0.0))
	_jaw(b, (30.0 * d + 20.0 * l) * (1.0 - shut) + 4.0 * shut * (1.0 - rec))
	for side in ARMS:
		_arm(b, side, Vector3(6.0 * k - 12.0 * push, 0.0, 0.0), -3.0 * k, 0.0)
	_tail_sway(b, t, 2.0, 6.0, 0.25)


static func _arm_swipe(t: float, b: HHMonsterBody) -> void:
	# the right arm lifts out wide and back (0-0.75), sweeps across the front (0.75-1.2,
	# contact 1.2), follows through (1.2-1.6), recover
	var w := _ss(t, 0.0, 0.75)
	var sw := _snap(t, 0.75, 1.2)
	var ft := _ss(t, 1.2, 1.6)
	var rec := _ss(t, 1.7, 2.4)
	var k := w * (1.0 - sw)
	var cross := sw * (1.0 - rec)
	# the right arm: back and out, then across to the left
	_arm(b, "fr", Vector3(-45.0 * k - 55.0 * cross, -40.0 * k + (55.0 + 20.0 * ft) * cross, -25.0 * k - 10.0 * cross),
		-40.0 * k - 20.0 * cross, 10.0 * k + 10.0 * cross)
	# the left arm braces
	_arm(b, "fl", Vector3(8.0 * k - 4.0 * cross, 0.0, 12.0 * (k + cross)), -2.0 * k, 0.0)
	b.bend(SPINE, Vector3(0.0, -14.0 * k + (18.0 + 8.0 * ft) * cross, 6.0 * k - 8.0 * cross), 1.2)
	_roll_about(b, 5.0 * k - 6.0 * cross, 1.8)
	b.rot("neck", Vector3(4.0 * k, -10.0 * k + 14.0 * cross, 0.0))
	b.rot("head", Vector3(2.0 * k, -8.0 * k + 10.0 * cross, 0.0))
	_jaw(b, 8.0 * k + 24.0 * cross)
	b.bend(TAIL, Vector3(0.0, 16.0 * k - 20.0 * cross, 0.0), 1.2)


static func _mist_breath(t: float, b: HHMonsterBody) -> void:
	# chest fills, head up (0-0.8); head drops and exhales (0.8-1.2, contact 1.2);
	# the breath is held sweeping side to side (1.2-2.4); recover
	var inh := _ss(t, 0.0, 0.8)
	var ex := _snap(t, 0.8, 1.2)
	var rec := _ss(t, 2.4, 3.0)
	var k := inh * (1.0 - ex)
	var out := ex * (1.0 - rec)
	var sweep := sin(TAU * (t - 1.2) / 2.4) * out * _ss(t, 1.2, 1.4)
	b.move("spine_1", Vector3(0.0, 0.12 * k + 0.05 * out, 0.0))
	b.move("root", Vector3(0.0, 0.1 * k - 0.05 * out, 0.1 * out))
	b.bend(SPINE, Vector3(-6.0 * k + 4.0 * out, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-16.0 * k + 2.0 * out, 22.0 * sweep, 0.0))
	b.rot("head", Vector3(-6.0 * k + 6.0 * out, 14.0 * sweep, 0.0))
	_jaw(b, 10.0 * k + 34.0 * out + 2.0 * _shake(t, 1.2, 1.2, 9.0) * out)
	for side in ARMS:
		_arm(b, side, Vector3(-4.0 * k + 4.0 * out, 0.0, 0.0), 0.0, 0.0)
	_tail_sway(b, t, 3.0, 6.0, 0.25)


static func _meteor_drop(t: float, b: HHMonsterBody) -> void:
	# the right arm reaches back to the crystals on its shoulder (0-0.7), rips one off
	# (0.7-0.95), hurls it overhead (0.95-1.5, contact 1.5 = release), watches, arm down
	var reach := _ss(t, 0.0, 0.7)
	var rip := _snap(t, 0.7, 0.95)
	var hurl := _snap(t, 0.95, 1.5)
	var down := _ss(t, 2.4, 3.4)
	var back := reach * (1.0 - hurl)
	var up := hurl * (1.0 - down)
	var yank := _shake(t, 0.75, 0.4, 8.0) * rip
	# shoulder pitch: back over the shoulder (+), then swung far forward and up (-)
	_arm(b, "fr", Vector3(95.0 * back - 130.0 * up + 4.0 * yank, -20.0 * back + 10.0 * up, -20.0 * back - 12.0 * up),
		-70.0 * back - 30.0 * up, 20.0 * back + 10.0 * up)
	_arm(b, "fl", Vector3(6.0 * back + 4.0 * up, 0.0, 14.0 * (back + up)), -2.0 * back, 0.0)
	b.move("root", Vector3(0.0, -0.1 * back + 0.25 * up, -0.1 * back))
	b.bend(SPINE, Vector3(4.0 * back - 12.0 * up, -14.0 * back + 6.0 * up, 6.0 * back + 3.0 * yank), 1.2)
	_roll_about(b, 6.0 * back - 4.0 * up, 1.8)
	b.rot("neck", Vector3(6.0 * back - 24.0 * up, -18.0 * back + 4.0 * up, 0.0))
	b.rot("head", Vector3(4.0 * back - 14.0 * up, -10.0 * back, 0.0))
	_jaw(b, 6.0 * back + 18.0 * rip * (1.0 - down))
	b.bend(TAIL, Vector3(-6.0 * back + 10.0 * up, 10.0 * back, 0.0), 1.2)


static func _freeze_pillar(t: float, b: HHMonsterBody) -> void:
	# fists plant and the head goes to the ground (0-0.8); a breath down into the rock
	# with a crystal shiver (0.8-1.3, contact 1.3); hold; recover
	var dn := _ss(t, 0.0, 0.8)
	var ex := _snap(t, 0.8, 1.3)
	var rec := _ss(t, 1.9, 2.6)
	var low := dn * (1.0 - rec)
	var out := ex * (1.0 - rec)
	var sh := _shake(t, 0.8, 1.1, 12.0) * out
	_plant(b, low)
	b.move("root", Vector3(0.0, -0.15 * low, 0.0))
	b.bend(SPINE, Vector3(8.0 * low, 0.0, 2.0 * sh), 1.2)
	b.rot("neck", Vector3(20.0 * low, 0.0, 0.0))
	b.rot("head", Vector3(8.0 * low, 3.0 * sh, 0.0))
	_jaw(b, 16.0 * low + 22.0 * out)
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(8.0 * low, 0.0, 0.0))
	b.bend(TAIL, Vector3(12.0 * low, 0.0, 0.0), 1.3)
