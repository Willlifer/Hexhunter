class_name HHColambrosClips
extends RefCounted
## Colambros's clips: pose functions of time on an HHMonsterBody (H305, the
## Swampfang pattern). The REST POSE is the biped stance (kangaroo rear legs,
## arms hanging off the chest, tail out behind as a counterweight). Clips
## that sprint drop it to all fours with `_quad()`: the body pitches nose-down
## about the hips, the rear legs crouch, the arms reach the ground.
##
## Colambros is THE ONE FAST MONSTER (H13): the run and the charge are quick
## and low; everything else still carries weight: a slow coil, a short
## release, a held contact, follow-through in the tail and the quill ridge.
##
## CLIPS: { name: { duration (s), contact_tick (30 Hz tick when damage lands;
## -1 none), loop, key (the preview moment, s), note } }. The brain
## (HHColambros) starts the clip and the telegraph on the same tick with a
## window of contact_tick x windup_mult, slowing the clip to match (H38).
##
## Bone names (art/monsters/monsters.json): root, hips, spine_0, spine_1,
## chest, neck, head, jaw, tail_0..tail_3, quill_0..quill_13 (skull -> tail),
## rear legs hl / hr and arms fl / fr: hip_, knee_, ankle_, toe_.
## Axes (HHMonsterBody.rot): pitch about X (+ drops a forward tip, lifts a
## backward tip), yaw about Y (+ swings a tip to the monster's left), roll about Z.
## Rear leg: hip bone points down-forward (-pitch swings the knee forward),
## knee bone down-back (+pitch folds the shin), ankle bone down-forward
## (+pitch folds the foot). Arm: hip bone down-back (-pitch swings the elbow
## forward), knee bone down-forward (-pitch folds the forearm up, +pitch
## extends it down). Quills point up-back: -pitch flattens them along the spine.

const T := 1.0 / 30.0

const CLIPS := {
	"calm_sprawl":     { "duration": 6.0, "contact_tick": -1, "loop": true,  "key": 1.5, "note": "belly on the warm ground, legs splayed, head resting, slow breathing, quills relaxed" },
	"quill_gnaw":      { "duration": 3.2, "contact_tick": -1, "loop": false, "key": 1.4, "note": "sprawled; head cranes round to its flank, nibbles a loose quill, swings front and spits it out" },
	"aggravated_idle": { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "biped stance, weight shifting foot to foot, arms tucked, quills raised and rippling, head scanning" },
	"rattle_roar":     { "duration": 2.2, "contact_tick": -1, "loop": false, "key": 1.0, "note": "crouch and flatten (0-0.6), snap up with jaws wide (0.6-0.75), quills rattle through the held roar, settle" },
	"walk":            { "duration": 1.4, "contact_tick": -1, "loop": true,  "key": 0.35, "note": "biped theropod walk: alternating rear legs, body bob, tail counter-sway, quill ripple" },
	"run":             { "duration": 0.6, "contact_tick": -1, "loop": true,  "key": 0.15, "note": "quadruped bounding sprint: rear legs together, arms together, spine flexing, quills streaming in a wave" },
	"dirt_scrape":     { "duration": 1.6, "contact_tick": 25, "loop": false, "key": 0.6, "note": "THE CHARGE TELL: head low, one rear foot rakes dirt back twice, quills bristle, tail stiff; go at 0.83 s" },
	"charge":          { "duration": 0.5, "contact_tick": -1, "loop": true,  "key": 0.12, "note": "headlong: lower than run, head straight out, jaws open, quills flat and streaming" },
	"tail_lash":       { "duration": 1.8, "contact_tick": 30, "loop": false, "key": 1.0, "note": "coils the body one way (0-0.8), whips the tail round the other (0.8-1.0, contact), follow-through, settle" },
	"bite":            { "duration": 1.4, "contact_tick": 24, "loop": false, "key": 0.8, "note": "rears back jaws wide (0-0.55), lunges down and forward, jaws snap shut at 0.8, recover" },
	"ember_spit":      { "duration": 2.0, "contact_tick": 33, "loop": false, "key": 1.1, "note": "chest swells and quills raise (0-0.95), head whips forward and three pulses leave the mouth (1.1, 1.3, 1.5)" },
	"leap_stomp":      { "duration": 2.4, "contact_tick": 42, "loop": false, "key": 1.48, "note": "deep crouch (0-0.9), springs (0.9-1.05), tucked in the air, lands in a squash at 1.4, recoils" },
	"back_roll":       { "duration": 3.0, "contact_tick": 36, "loop": false, "key": 1.6, "note": "sits back, flips onto its back (1.2, contact), windmill spin with legs kicking, rolls up BALD: quills flat" },
	"hit_react":       { "duration": 0.5, "contact_tick": -1, "loop": false, "key": 0.1, "note": "head yanks, body shudders, quills flick" },
	"stagger":         { "duration": 1.4, "contact_tick": -1, "loop": false, "key": 0.5, "note": "knees buckle, sags, head low wobble, quills droop, slow recover" },
	"collapse":        { "duration": 2.0, "contact_tick": -1, "loop": false, "key": 1.6, "note": "down onto the belly, legs splay, quills flat, holds" },
	"death":           { "duration": 3.0, "contact_tick": -1, "loop": false, "key": 2.6, "note": "collapse, then rolls onto its side, jaw open, holds" },
	"bald_idle":       { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "the weak window: quills flattened to the spine, hunched, heavy breathing" },
}

const SPINE := ["hips", "spine_0", "spine_1", "chest"]
const NECK := ["neck", "head"]
const TAIL := ["tail_0", "tail_1", "tail_2", "tail_3"]
const REAR := ["hl", "hr"]
const ARMS := ["fl", "fr"]
const N_QUILLS := 14
const HIP_H := 1.75          ## rest height of the hips (m)
const HIP_Z := -0.55         ## rest z of the hips (m)
const SPRAWL := -1.12        ## root drop when the belly is on the ground (m)


static func clip_list() -> PackedStringArray:
	return PackedStringArray(CLIPS.keys())


static func pose(clip: String, t: float, b: HHMonsterBody) -> void:
	match clip:
		"calm_sprawl": _calm_sprawl(t, b)
		"quill_gnaw": _quill_gnaw(t, b)
		"aggravated_idle": _aggravated_idle(t, b)
		"rattle_roar": _rattle_roar(t, b)
		"walk": _walk(t, b)
		"run": _run(t, b)
		"dirt_scrape": _dirt_scrape(t, b)
		"charge": _charge(t, b)
		"tail_lash": _tail_lash(t, b)
		"bite": _bite(t, b)
		"ember_spit": _ember_spit(t, b)
		"leap_stomp": _leap_stomp(t, b)
		"back_roll": _back_roll(t, b)
		"hit_react": _hit_react(t, b)
		"stagger": _stagger(t, b)
		"collapse": _collapse(t, b)
		"death": _death(t, b)
		"bald_idle": _bald_idle(t, b)


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


## Rotate the whole body (pitch, yaw, roll) about the model point `c`
## (not the ground origin, H307).
static func _pivot(b: HHMonsterBody, euler_deg: Vector3, c: Vector3) -> void:
	if euler_deg.is_zero_approx():
		return
	b.rot("root", euler_deg)
	var r := Basis(Vector3.UP, deg_to_rad(euler_deg.y)) * Basis(Vector3.RIGHT, deg_to_rad(euler_deg.x)) * Basis(Vector3.BACK, deg_to_rad(euler_deg.z))
	b.move("root", c - r * c)


## Pitch about the hips: + is nose-down.
static func _pitch_hips(b: HHMonsterBody, deg: float) -> void:
	_pivot(b, Vector3(deg, 0.0, 0.0), Vector3(0.0, HIP_H, HIP_Z))


static func _roll_about(b: HHMonsterBody, roll_deg: float, h: float) -> void:
	_pivot(b, Vector3(0.0, 0.0, roll_deg), Vector3(0.0, h, HIP_Z))


static func _jaw(b: HHMonsterBody, open_deg: float) -> void:
	b.rot("jaw", Vector3(open_deg, 0.0, 0.0))


## The quill ridge: `raise` lifts every quill (+) or flattens it (-); a
## wave of `amp` degrees travels skull -> tail with `lag` cycles per quill.
static func _quills(b: HHMonsterBody, t: float, raise: float, amp: float = 0.0, period: float = 1.0, lag: float = 0.08) -> void:
	for k in N_QUILLS:
		var w := sin(TAU * (t / period - lag * k)) * amp if amp != 0.0 else 0.0
		b.rot("quill_%d" % k, Vector3(raise + w, 0.0, 0.0))


## Quills rattle: a fast out-of-phase shiver, pitch and roll.
static func _rattle(b: HHMonsterBody, t: float, amt: float) -> void:
	if amt <= 0.0:
		return
	for k in N_QUILLS:
		b.rot("quill_%d" % k, Vector3(amt * sin(TAU * t * 13.0 + k * 1.7), 0.0, amt * 0.6 * sin(TAU * t * 9.0 + k * 0.9)))


static func _tail_sway(b: HHMonsterBody, t: float, period: float, amp_deg: float, lag: float = 0.2) -> void:
	for k in TAIL.size():
		var ph := TAU * (t / period - lag * k)
		b.rot(TAIL[k], Vector3(0.0, sin(ph) * amp_deg * (0.6 + 0.4 * k), 0.0))


static func _breath(b: HHMonsterBody, t: float, period: float, amt: float) -> void:
	var s := 0.5 - 0.5 * cos(TAU * t / period)
	b.move("spine_1", Vector3(0.0, 0.05 * amt * s, 0.0))
	b.rot("spine_0", Vector3(-1.5 * amt * s, 0.0, 0.0))
	b.rot("chest", Vector3(1.2 * amt * s, 0.0, 0.0))
	b.rot("neck", Vector3(-1.0 * amt * s, 0.0, 0.0))


## Arms tucked up against the chest (the biped stance), 0..1.
static func _arms_tuck(b: HHMonsterBody, amt: float) -> void:
	for a in ARMS:
		b.rot("hip_" + a, Vector3(12.0 * amt, 0.0, 0.0))
		b.rot("knee_" + a, Vector3(-48.0 * amt, 0.0, 0.0))
		b.rot("ankle_" + a, Vector3(10.0 * amt, 0.0, 0.0))


## One rear leg through a biped stride, phase 0..1 (0 = foot plants).
static func _rear_leg(b: HHMonsterBody, leg: String, ph: float, stride_deg: float, lift_deg: float) -> void:
	ph = fposmod(ph, 1.0)
	if ph < 0.6:
		var u := ph / 0.6
		# stance: the planted foot pushes back under the body (+pitch on the hip)
		b.rot("hip_" + leg, Vector3(lerpf(-stride_deg, stride_deg, u), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lerpf(6.0, -4.0, u), 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(lerpf(-2.0, 6.0, u), 0.0, 0.0))
	else:
		var u := (ph - 0.6) / 0.4
		var arc := sin(u * PI)
		b.rot("hip_" + leg, Vector3(lerpf(stride_deg, -stride_deg, smoothstep(0.0, 1.0, u)), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lift_deg * arc, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(lift_deg * 0.5 * arc, 0.0, 0.0))


## The quadruped stance, 0..1: pitch nose-down about the hips, drop, rear
## legs crouch (flexes sum to zero so the foot stays flat), arms reach the
## ground, the head comes back up level.
static func _quad(b: HHMonsterBody, k: float) -> void:
	if k <= 0.0:
		return
	_pitch_hips(b, 32.0 * k)
	b.move("root", Vector3(0.0, -0.36 * k, 0.0))
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(-16.0 * k, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(28.0 * k, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-12.0 * k, 0.0, 0.0))
	for a in ARMS:
		b.rot("hip_" + a, Vector3(-38.0 * k, 0.0, 0.0))
		b.rot("knee_" + a, Vector3(48.0 * k, 0.0, 0.0))
		b.rot("ankle_" + a, Vector3(-10.0 * k, 0.0, 0.0))
	b.rot("neck", Vector3(-22.0 * k, 0.0, 0.0))
	b.rot("head", Vector3(-14.0 * k, 0.0, 0.0))
	b.bend(TAIL, Vector3(14.0 * k, 0.0, 0.0), 0.8)


## The bound on top of _quad: rear legs together, arms together, spine flexing.
static func _bound(b: HHMonsterBody, t: float, period: float, amp: float) -> void:
	var ph := TAU * t / period
	var s := sin(ph)
	var c := cos(ph)
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(20.0 * amp * s, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(18.0 * amp * maxf(0.0, -c), 0.0, 0.0))
	for a in ARMS:
		b.rot("hip_" + a, Vector3(-22.0 * amp * s, 0.0, 0.0))
		b.rot("knee_" + a, Vector3(16.0 * amp * maxf(0.0, c), 0.0, 0.0))
	b.bend(SPINE, Vector3(-9.0 * amp * c, 0.0, 0.0), 1.2)
	b.move("root", Vector3(0.0, 0.14 * amp * maxf(0.0, s), 0.0))
	b.rot("neck", Vector3(4.0 * amp * c, 0.0, 0.0))
	b.bend(TAIL, Vector3(-10.0 * amp * c, 0.0, 0.0), 1.3)


## Rear legs splayed out to the sides, folded (sprawl, collapse), 0..1.
static func _rear_splay(b: HHMonsterBody, amt: float) -> void:
	for leg in REAR:
		var s := 1.0 if leg == "hl" else -1.0
		b.rot("hip_" + leg, Vector3(-30.0 * amt, 0.0, s * 48.0 * amt))
		b.rot("knee_" + leg, Vector3(40.0 * amt, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-10.0 * amt, 0.0, 0.0))
	for a in ARMS:
		var s := 1.0 if a == "fl" else -1.0
		b.rot("hip_" + a, Vector3(-40.0 * amt, 0.0, s * 30.0 * amt))
		b.rot("knee_" + a, Vector3(10.0 * amt, 0.0, 0.0))


## The sprawl: belly on the ground, body level, head resting, tail flat.
static func _sprawl_pose(b: HHMonsterBody, amt: float) -> void:
	_pitch_hips(b, 12.0 * amt)
	b.move("root", Vector3(0.0, SPRAWL * amt, 0.0))
	_rear_splay(b, amt)
	b.rot("neck", Vector3(6.0 * amt, 0.0, 0.0))
	b.rot("head", Vector3(10.0 * amt, 0.0, 0.0))
	b.bend(TAIL, Vector3(14.0 * amt, 0.0, 0.0), 0.7)


# ------------------------------------------------------------------ idles

static func _calm_sprawl(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 6.0)
	_sprawl_pose(b, 1.0)
	_breath(b, t, 4.0, 1.2)
	b.rot("neck", Vector3(2.0 * s, 10.0 * sin(TAU * t / 12.0), 0.0))
	b.rot("head", Vector3(0.0, 6.0 * sin(TAU * t / 12.0 + 0.5), 0.0))
	_jaw(b, 3.0 + 2.0 * s)
	_quills(b, t, -22.0, 2.0, 6.0, 0.05)
	_tail_sway(b, t, 6.0, 5.0, 0.15)


static func _quill_gnaw(t: float, b: HHMonsterBody) -> void:
	# crane round to the left flank (0-0.8), nibble (0.8-2.0), swing front and spit (2.0-2.5), settle (2.5-3.2)
	var crane := _ss(t, 0.0, 0.8) * (1.0 - _ss(t, 2.0, 2.4))
	var nib := _ss(t, 0.8, 1.0) * (1.0 - _ss(t, 1.9, 2.1))
	var spit := _snap(t, 2.3, 2.45) * (1.0 - _ss(t, 2.6, 3.2))
	_sprawl_pose(b, 1.0)
	_breath(b, t, 4.0, 0.8)
	b.bend(SPINE, Vector3(0.0, 42.0 * crane, -4.0 * crane), 1.6)
	b.rot("neck", Vector3(14.0 * crane, 70.0 * crane, 0.0))
	b.rot("head", Vector3(20.0 * crane - 10.0 * spit, 50.0 * crane, 0.0))
	_jaw(b, 4.0 + (8.0 + 7.0 * sin(TAU * t * 6.0)) * nib + 32.0 * spit)
	b.rot("spine_1", Vector3(0.0, 0.0, 0.0))
	_quills(b, t, -22.0 + 10.0 * nib, 0.0)
	# the gnawed quills (over the hips) twitch as it tugs them
	for k in range(7, 10):
		b.rot("quill_%d" % k, Vector3(14.0 * nib * sin(TAU * t * 6.0 + k), 0.0, 8.0 * nib * sin(TAU * t * 5.0)))
	_tail_sway(b, t, 6.0, 5.0, 0.15)


static func _aggravated_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 3.0)
	_breath(b, t, 3.0, 1.0)
	_roll_about(b, 2.5 * s, 1.0)
	b.move("root", Vector3(0.0, 0.03 * absf(s), 0.0))
	_arms_tuck(b, 1.0)
	# weight shifts foot to foot
	b.rot("hip_hl", Vector3(3.0 * s, 0.0, 0.0))
	b.rot("hip_hr", Vector3(-3.0 * s, 0.0, 0.0))
	b.rot("knee_hl", Vector3(4.0 * maxf(0.0, s), 0.0, 0.0))
	b.rot("knee_hr", Vector3(4.0 * maxf(0.0, -s), 0.0, 0.0))
	b.rot("neck", Vector3(-6.0, 9.0 * sin(TAU * t / 6.0), 0.0))
	b.rot("head", Vector3(-3.0 + 2.0 * s, 6.0 * sin(TAU * t / 6.0 + 0.6), 0.0))
	_jaw(b, 5.0 + 3.0 * s)
	_quills(b, t, 14.0, 5.0, 3.0, 0.07)
	_tail_sway(b, t, 3.0, 12.0)


static func _bald_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 2.2)
	_breath(b, t, 2.2, 1.6)
	_roll_about(b, 1.5 * s, 1.0)
	_arms_tuck(b, 0.8)
	b.move("root", Vector3(0.0, -0.12, 0.0))
	b.bend(SPINE, Vector3(7.0, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(10.0, 5.0 * sin(TAU * t / 4.0), 0.0))
	b.rot("head", Vector3(6.0, 0.0, 0.0))
	_jaw(b, 9.0 + 4.0 * s)
	for leg in REAR:
		b.rot("knee_" + leg, Vector3(10.0, 0.0, 0.0))
		b.rot("hip_" + leg, Vector3(-6.0, 0.0, 0.0))
	_quills(b, t, -78.0, 1.5, 2.2, 0.05)          # bald: the ridge lies flat along the spine
	_tail_sway(b, t, 2.2, 6.0)


static func _rattle_roar(t: float, b: HHMonsterBody) -> void:
	var a := _ss(t, 0.0, 0.6)
	var s := _snap(t, 0.6, 0.75)
	var flare := _over(t, 0.6, 0.75, 1.1, 0.35)
	var rel := _ss(t, 1.6, 2.2)
	var hold := s * (1.0 - rel)
	var crouch := a * (1.0 - s)
	var sh := _shake(t, 0.75, 0.9, 10.0) * hold
	b.move("root", Vector3(0.0, -0.3 * crouch + 0.12 * hold, 0.0))
	_pitch_hips(b, 8.0 * crouch - 10.0 * hold)
	b.bend(SPINE, Vector3(6.0 * crouch - 8.0 * hold, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(16.0 * crouch - 28.0 * hold, 3.0 * sh, 0.0))
	b.rot("head", Vector3(10.0 * crouch - 22.0 * hold, 2.0 * sh, 0.0))
	_jaw(b, 4.0 * crouch + 42.0 * hold + 3.0 * sh)
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(-10.0 * crouch, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(18.0 * crouch - 4.0 * hold, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-8.0 * crouch, 0.0, 0.0))
	_arms_tuck(b, 1.0)
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(-20.0 * hold, 0.0, 0.0))
	_quills(b, t, -30.0 * crouch + 42.0 * flare * s * (1.0 - rel * 0.6), 0.0)
	_rattle(b, t, 14.0 * hold)
	b.bend(TAIL, Vector3(-10.0 * crouch + 16.0 * hold, 0.0, 0.0), 1.3)
	_tail_sway(b, t, 2.2, 6.0 + 10.0 * hold, 0.25)


# ------------------------------------------------------------------ locomotion

static func _walk(t: float, b: HHMonsterBody) -> void:
	var ph := t / 1.4
	_rear_leg(b, "hl", ph, 24.0, 42.0)
	_rear_leg(b, "hr", ph + 0.5, 24.0, 42.0)
	var roll := sin(TAU * ph) * 4.0
	_roll_about(b, roll, 1.0)
	b.move("root", Vector3(0.0, -0.05 + 0.08 * cos(TAU * ph * 2.0), 0.0))
	_pitch_hips(b, 4.0)
	b.bend(SPINE, Vector3(0.0, -5.0 * sin(TAU * ph), -roll * 0.4), 1.2)
	b.rot("neck", Vector3(-4.0 - 2.0 * cos(TAU * ph * 2.0), 4.0 * sin(TAU * ph), 0.0))
	b.rot("head", Vector3(-2.0 + 2.0 * cos(TAU * ph * 2.0 + 0.5), 0.0, 0.0))
	_jaw(b, 4.0)
	_arms_tuck(b, 1.0)
	_quills(b, t, 12.0, 7.0, 1.4, 0.07)
	_tail_sway(b, t, 1.4, 14.0, 0.2)


static func _run(t: float, b: HHMonsterBody) -> void:
	_quad(b, 1.0)
	_bound(b, t, 0.6, 1.0)
	_jaw(b, 8.0)
	_quills(b, t, -6.0, 20.0, 0.6, 0.11)           # the ridge sways in a wave as it runs
	_tail_sway(b, t, 0.6, 8.0, 0.2)


static func _charge(t: float, b: HHMonsterBody) -> void:
	_quad(b, 1.0)
	_pitch_hips(b, 6.0)
	_bound(b, t, 0.5, 1.2)
	b.rot("neck", Vector3(-6.0, 0.0, 0.0))
	b.rot("head", Vector3(-4.0, 0.0, 0.0))
	_jaw(b, 26.0)
	_quills(b, t, -34.0, 14.0, 0.5, 0.12)          # flattened by the wind, streaming
	b.bend(TAIL, Vector3(-6.0, 0.0, 0.0))


# ------------------------------------------------------------------ attacks

static func _dirt_scrape(t: float, b: HHMonsterBody) -> void:
	# head low, body leaning in; the left rear foot rakes back twice (0.1-0.4, 0.5-0.8); go at 0.83
	var lean := _ss(t, 0.0, 0.3) * (1.0 - _ss(t, 1.2, 1.6))
	var rake := 0.0
	var lift := 0.0
	for st in [0.1, 0.5]:
		var u := clampf((t - st) / 0.3, 0.0, 1.0)
		if t >= st and u < 1.0:
			lift = sin(u * PI) * (1.0 - _ss(u, 0.0, 0.35))
			rake = _snap(u, 0.2, 1.0)
	var brace := lean
	b.move("root", Vector3(0.0, -0.16 * brace, 0.0))
	_pitch_hips(b, 12.0 * lean)
	b.bend(SPINE, Vector3(4.0 * lean, 0.0, 0.0), 1.1)
	b.rot("neck", Vector3(22.0 * lean, 0.0, 0.0))
	b.rot("head", Vector3(8.0 * lean, 3.0 * _shake(t, 0.1, 1.2, 4.0), 0.0))
	_jaw(b, 10.0 * lean)
	# the scraping foot: swings forward and lifts, then rakes hard back
	b.rot("hip_hl", Vector3(-40.0 * lift + 40.0 * rake, 0.0, 0.0))
	b.rot("knee_hl", Vector3(60.0 * lift + 8.0 * rake, 0.0, 0.0))
	b.rot("ankle_hl", Vector3(24.0 * lift - 10.0 * rake, 0.0, 0.0))
	# the other leg braces, bent
	b.rot("hip_hr", Vector3(-8.0 * brace, 0.0, 0.0))
	b.rot("knee_hr", Vector3(16.0 * brace, 0.0, 0.0))
	b.rot("ankle_hr", Vector3(-6.0 * brace, 0.0, 0.0))
	_arms_tuck(b, 1.0)
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(-16.0 * lean, 0.0, 0.0))
	_quills(b, t, 30.0 * lean, 0.0)
	_rattle(b, t, 5.0 * lean)
	b.bend(TAIL, Vector3(18.0 * lean, 0.0, 0.0), 1.2)
	_tail_sway(b, t, 1.6, 4.0)


static func _tail_lash(t: float, b: HHMonsterBody) -> void:
	# coil left (0-0.8), whip right (0.8-1.0, contact), follow-through (1.0-1.4), settle (1.4-1.8)
	var c := _ss(t, 0.0, 0.8)
	var w := _snap(t, 0.8, 1.0)
	var f := _ss(t, 1.0, 1.4)
	var rec := _ss(t, 1.4, 1.8)
	var yaw := (24.0 * c - 46.0 * w + 16.0 * f) * (1.0 - rec)
	var tail_yaw := (-45.0 * c + 100.0 * w - 40.0 * f) * (1.0 - rec)
	b.move("root", Vector3(0.0, -0.14 * c * (1.0 - w) - 0.08 * w * (1.0 - rec), 0.0))
	_pivot(b, Vector3(0.0, yaw * 0.35, -6.0 * c * (1.0 - w) + 8.0 * w * (1.0 - rec)), Vector3(0.0, HIP_H, HIP_Z))
	b.bend(SPINE, Vector3(2.0 * c, yaw, 0.0), 1.2)
	b.rot("neck", Vector3(-4.0, yaw * 0.6, 0.0))
	b.rot("head", Vector3(0.0, yaw * 0.4, 0.0))
	b.bend(TAIL, Vector3(10.0 * c * (1.0 - w) - 6.0 * w * (1.0 - rec), tail_yaw, 0.0), 1.3)
	_jaw(b, 8.0 * c + 16.0 * w * (1.0 - rec))
	_arms_tuck(b, 1.0)
	for leg in REAR:
		b.rot("knee_" + leg, Vector3(12.0 * c * (1.0 - w) + 6.0 * w * (1.0 - rec), 0.0, 0.0))
	b.rot("hip_hl", Vector3(-8.0 * c, 0.0, 0.0))
	b.rot("hip_hr", Vector3(8.0 * c, 0.0, 0.0))
	_quills(b, t, 16.0, 0.0)
	_rattle(b, t, 6.0 * w * (1.0 - rec))


static func _bite(t: float, b: HHMonsterBody) -> void:
	# rear back jaws wide (0-0.55), lunge down and forward (0.55-0.8), snap shut at 0.8, recover (1.0-1.4)
	var r := _ss(t, 0.0, 0.55)
	var l := _snap(t, 0.55, 0.8)
	var shut := _snap(t, 0.74, 0.8)
	var rec := _ss(t, 1.0, 1.4)
	var k := r * (1.0 - l)
	var push := l * (1.0 - rec)
	b.move("root", Vector3(0.0, 0.06 * k - 0.1 * push, -0.18 * k + 0.5 * push))
	_pitch_hips(b, -8.0 * k + 16.0 * push)
	b.bend(SPINE, Vector3(-5.0 * k + 6.0 * push, 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-26.0 * k + 22.0 * push, 0.0, 0.0))
	b.rot("head", Vector3(-12.0 * k + 12.0 * push, 0.0, 0.0))
	_jaw(b, 34.0 * r * (1.0 - shut) + 2.0 * shut * (1.0 - rec))
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(6.0 * k - 10.0 * push, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(14.0 * k + 4.0 * push, 0.0, 0.0))
	_arms_tuck(b, 1.0)
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(-24.0 * push, 0.0, 0.0))
	_quills(b, t, 18.0 * r * (1.0 - rec), 0.0)
	b.bend(TAIL, Vector3(12.0 * k - 8.0 * push, 0.0, 0.0), 1.2)
	_tail_sway(b, t, 1.4, 6.0)


static func _ember_spit(t: float, b: HHMonsterBody) -> void:
	# the chest swells and the quills raise (0-0.95); head whips forward (0.95-1.1); three pulses; recover
	var a := _ss(t, 0.0, 0.95)
	var w := _snap(t, 0.95, 1.1)
	var rec := _ss(t, 1.6, 2.0)
	var k := a * (1.0 - w)
	var pulse := 0.0
	for st in [1.1, 1.3, 1.5]:
		pulse += _shake(t, st, 0.18, 5.0)
	b.move("root", Vector3(0.0, 0.1 * k, -0.14 * k + 0.1 * w * (1.0 - rec)))
	_pitch_hips(b, -6.0 * k + 6.0 * w * (1.0 - rec))
	b.move("spine_1", Vector3(0.0, 0.1 * k, 0.0))
	b.bend(SPINE, Vector3(-8.0 * k + 3.0 * w * (1.0 - rec), 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-24.0 * k + 18.0 * w * (1.0 - rec) - 4.0 * pulse, 0.0, 0.0))
	b.rot("head", Vector3(-14.0 * k + 10.0 * w * (1.0 - rec) - 3.0 * pulse, 0.0, 0.0))
	_jaw(b, 10.0 * a + 36.0 * w * (1.0 - rec) + 6.0 * pulse)
	_arms_tuck(b, 1.0)
	for leg in REAR:
		b.rot("knee_" + leg, Vector3(8.0 * k + 6.0 * w * (1.0 - rec), 0.0, 0.0))
	_quills(b, t, 38.0 * a * (1.0 - rec), 0.0)
	_rattle(b, t, 5.0 * k)
	b.bend(TAIL, Vector3(10.0 * k, 0.0, 0.0))
	_tail_sway(b, t, 2.0, 6.0)


static func _leap_stomp(t: float, b: HHMonsterBody) -> void:
	# deep crouch (0-0.9), spring (0.9-1.05), air (1.05-1.4), land 1.4 (contact), recoil (1.6-2.4)
	var cr := _ss(t, 0.0, 0.9)
	var sp := _snap(t, 0.9, 1.05)
	var air := _ss(t, 1.05, 1.2) * (1.0 - _ss(t, 1.35, 1.42))
	var land := _snap(t, 1.38, 1.46)
	var rec := _ss(t, 1.7, 2.4)
	var crouch := cr * (1.0 - sp)
	var squash := land * (1.0 - rec)
	b.move("root", Vector3(0.0, -0.55 * crouch + 0.1 * sp * (1.0 - air) - 0.6 * squash, 0.0))
	_pitch_hips(b, 14.0 * crouch - 12.0 * sp * (1.0 - land) + 10.0 * squash)
	b.bend(SPINE, Vector3(8.0 * crouch - 6.0 * sp * (1.0 - land) + 8.0 * squash, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(10.0 * crouch - 12.0 * sp * (1.0 - land) + 12.0 * squash, 0.0, 0.0))
	b.rot("head", Vector3(6.0 * crouch + 8.0 * squash, 0.0, 0.0))
	_jaw(b, 6.0 * crouch + 20.0 * sp * (1.0 - rec))
	for leg in REAR:
		# crouch folds, spring extends, air trails, landing folds again
		b.rot("hip_" + leg, Vector3(-32.0 * crouch + 30.0 * sp * (1.0 - land) + 20.0 * air - 26.0 * squash, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(52.0 * crouch - 16.0 * sp * (1.0 - land) + 14.0 * air + 44.0 * squash, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-20.0 * crouch + 8.0 * sp * (1.0 - land) - 18.0 * squash, 0.0, 0.0))
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(10.0 * crouch - 40.0 * (sp * (1.0 - land) + air) - 30.0 * squash, 0.0, 0.0))
		b.rot("knee_" + arm, Vector3(-40.0 * crouch + 30.0 * squash, 0.0, 0.0))
	_quills(b, t, 20.0 * crouch - 30.0 * air + 30.0 * squash, 0.0)
	_rattle(b, t, 8.0 * squash)
	b.bend(TAIL, Vector3(-14.0 * crouch + 20.0 * sp * (1.0 - land) - 10.0 * squash, 0.0, 0.0), 1.2)


static func _back_roll(t: float, b: HHMonsterBody) -> void:
	# sits back (0-0.6), flips onto its back (0.6-1.2, contact), windmill spin with legs kicking
	# (1.2-2.3), rolls up (2.3-3.0) with the ridge gone: the quills lie flat from 2.0 on
	var sit := _ss(t, 0.0, 0.6)
	var flip := _ss(t, 0.6, 1.2)
	var spin := _ss(t, 1.2, 1.35) * (1.0 - _ss(t, 2.2, 2.4))
	var up := _ss(t, 2.3, 3.0)
	var onback := flip * (1.0 - up)
	var bald := _ss(t, 1.9, 2.3)
	var turns := 0.0
	if t > 1.2:
		var u := clampf((t - 1.2) / 1.1, 0.0, 1.0)
		turns = 540.0 * (u * u * (3.0 - 2.0 * u) * 0.3 + u * 0.7)
	# the roll: pivot on the long axis at hip height, lowered so the back lands on the ground
	b.move("root", Vector3(0.0, -0.45 * sit * (1.0 - flip) - 0.9 * onback, 0.0))
	_pivot(b, Vector3(-18.0 * sit * (1.0 - flip), turns, 180.0 * onback), Vector3(0.0, HIP_H, HIP_Z))
	b.bend(SPINE, Vector3(-6.0 * sit + 10.0 * onback, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-14.0 * sit + 16.0 * onback, 0.0, 0.0))
	b.rot("head", Vector3(-8.0 * sit + 10.0 * onback, 0.0, 0.0))
	_jaw(b, 10.0 * sit + 26.0 * onback)
	var kick := spin
	for leg in REAR:
		var s := 1.0 if leg == "hl" else -1.0
		b.rot("hip_" + leg, Vector3(-30.0 * sit - 40.0 * onback + 24.0 * kick * sin(TAU * t * 2.5 + s), 0.0, s * 20.0 * onback))
		b.rot("knee_" + leg, Vector3(44.0 * sit + 20.0 * onback - 24.0 * kick * sin(TAU * t * 2.5 + s), 0.0, 0.0))
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(-40.0 * onback, 0.0, 0.0))
		b.rot("knee_" + arm, Vector3(-30.0 * onback, 0.0, 0.0))
	b.bend(TAIL, Vector3(26.0 * sit * (1.0 - flip) + 30.0 * onback, 20.0 * kick * sin(TAU * t * 1.5), 0.0), 1.3)
	_quills(b, t, 30.0 * sit * (1.0 - flip) - 80.0 * bald, 0.0)
	_rattle(b, t, 14.0 * spin * (1.0 - bald))


# ------------------------------------------------------------------ reactions

static func _hit_react(t: float, b: HHMonsterBody) -> void:
	var k := _snap(t, 0.0, 0.08) * (1.0 - _ss(t, 0.18, 0.5))
	b.rot("neck", Vector3(-8.0 * k, 16.0 * k, 0.0))
	b.rot("head", Vector3(-6.0 * k, 12.0 * k, 0.0))
	b.bend(SPINE, Vector3(0.0, 5.0 * k, 3.0 * k))
	b.move("root", Vector3(0.0, -0.05 * k, -0.1 * k))
	_jaw(b, 16.0 * k)
	_arms_tuck(b, 1.0)
	_quills(b, t, 14.0 + 10.0 * k, 0.0)
	_rattle(b, t, 8.0 * k)
	_tail_sway(b, t, 0.5, 8.0 * k)


static func _stagger(t: float, b: HHMonsterBody) -> void:
	var sag := _snap(t, 0.0, 0.25) * (1.0 - _ss(t, 0.85, 1.4))
	var wobble := _shake(t, 0.25, 0.9, 3.0)
	b.move("root", Vector3(0.0, -0.42 * sag, 0.0))
	_roll_about(b, 9.0 * wobble * sag, 0.9)
	_pitch_hips(b, 10.0 * sag)
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(-18.0 * sag, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(34.0 * sag, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-14.0 * sag, 0.0, 0.0))
	for arm in ARMS:
		var s := 1.0 if arm == "fl" else -1.0
		b.rot("hip_" + arm, Vector3(-30.0 * sag, 0.0, s * 20.0 * sag))
	b.bend(SPINE, Vector3(4.0 * sag, 9.0 * wobble * sag, 0.0))
	b.rot("neck", Vector3(14.0 * sag, 10.0 * wobble * sag, 0.0))
	b.rot("head", Vector3(10.0 * sag, 0.0, 0.0))
	_jaw(b, 12.0 * sag)
	_quills(b, t, 14.0 - 40.0 * sag, 0.0)
	_tail_sway(b, t, 1.4, 10.0 * sag)


static func _collapse(t: float, b: HHMonsterBody) -> void:
	var d := _ss(t, 0.0, 1.3)
	var bounce := _shake(t, 1.3, 0.6, 2.5) * 0.05
	_sprawl_pose(b, d)
	b.move("root", Vector3(0.0, bounce, 0.0))
	b.bend(SPINE, Vector3(5.0 * d, 0.0, 0.0), 0.8)
	b.rot("neck", Vector3(12.0 * d, 0.0, 0.0))
	b.rot("head", Vector3(6.0 * d, 0.0, 0.0))
	_jaw(b, 18.0 * d)
	_quills(b, t, 14.0 - 80.0 * d, 0.0)


static func _death(t: float, b: HHMonsterBody) -> void:
	_collapse(minf(t, 2.0), b)
	var r := _ss(t, 1.5, 2.7)
	_roll_about(b, 75.0 * r, 0.5)
	b.move("root", Vector3(0.0, 0.2 * r, 0.0))
	b.rot("neck", Vector3(0.0, 0.0, -10.0 * r))
	_jaw(b, 16.0 * r)
	for leg in REAR:
		b.rot("hip_" + leg, Vector3(-20.0 * r, 0.0, 0.0))
	for arm in ARMS:
		b.rot("hip_" + arm, Vector3(-30.0 * r, 0.0, 0.0))
