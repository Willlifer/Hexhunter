class_name HHSwampfangClips
extends RefCounted
## Swampfang's clips: pose functions of time on an HHMonsterBody (the
## Black | White anim_*.gd idea, on bones instead of a pose solver). Every
## clip is weight first: a slow anticipation, a short release, a held
## contact, follow-through in the tail and frill. The kickoff's bar (H13):
## heavy, slow, telegraphed; ground shapes carry the danger, the body sells it.
##
## CLIPS: { name: { duration (s), contact_tick (30 Hz tick when damage lands;
## -1 none), loop, key (the preview moment, s), note } }. The brain
## (HHSwampfang) starts the clip and the telegraph on the same tick with a
## window of `contact_tick` ticks, so the danger shape resolves exactly as
## the body lands the blow.
##
## Bone names (art/monsters/monsters.json): root, hips, spine_0, spine_1,
## chest, neck, head, jaw, tail_0..tail_3, frill_l, frill_r, fin_0 (the head
## crest) fin_1 fin_2 (the dorsal sails: fold bones, Phase 3.5), and per leg
## fl / fr / hl / hr: hip_, knee_, ankle_, toe_.
## Axes (HHMonsterBody.rot): pitch about X (+ drops a forward tip, lifts a
## tail tip), yaw about Y (+ swings a tip to the monster's left), roll about Z.

const T := 1.0 / 30.0

const CLIPS := {
	"calm_float":      { "duration": 5.0, "contact_tick": -1, "loop": true,  "key": 1.2, "note": "half-submerged, only frill and back fins show, slow sway" },
	"aggravated_idle": { "duration": 3.0, "contact_tick": -1, "loop": true,  "key": 0.8, "note": "raised, frill flared, breathing, tail slow sway" },
	"frill_roar":      { "duration": 2.4, "contact_tick": -1, "loop": false, "key": 0.95, "note": "crouch and fold (0-0.6), snap open (0.6-0.75), held roar with shake, settle" },
	"walk":            { "duration": 1.6, "contact_tick": -1, "loop": true,  "key": 0.3, "note": "front-leg driven, hind legs shuffle, weight rolls, tail paddles" },
	"hit_react":       { "duration": 0.6, "contact_tick": -1, "loop": false, "key": 0.1, "note": "head yanks, body shudders" },
	"stagger":         { "duration": 1.5, "contact_tick": -1, "loop": false, "key": 0.5, "note": "sags onto the front legs, head low, slow recover" },
	"collapse":        { "duration": 2.0, "contact_tick": -1, "loop": false, "key": 1.6, "note": "down onto the belly, legs splay, holds" },
	"death":           { "duration": 3.0, "contact_tick": -1, "loop": false, "key": 2.6, "note": "collapse, then rolls onto its side, holds" },
	"dark_spray":      { "duration": 2.2, "contact_tick": 36, "loop": false, "key": 1.25, "note": "frill flare + head back (0-0.9), head whip down-forward (0.9-1.2), spray held, recover" },
	"water_jet":       { "duration": 2.0, "contact_tick": 30, "loop": false, "key": 1.05, "note": "head coils back and low, thrusts forward on a straight neck, held, recover" },
	"thrash_splash":   { "duration": 2.4, "contact_tick": 39, "loop": false, "key": 1.25, "note": "body coils one way and rises, whips the other and slams, second smaller whip" },
	"death_roll_spin": { "duration": 3.6, "contact_tick": 48, "loop": false, "key": 2.0, "note": "rocks with growing amplitude for 1.6 s, then two full rolls, wobbles out" },
	"dive":            { "duration": 1.8, "contact_tick": -1, "loop": false, "key": 1.15, "note": "rears, plunges nose-first, the tail slaps the surface as it goes under; holds submerged" },
	"swim":            { "duration": 2.0, "contact_tick": -1, "loop": true,  "key": 0.5, "note": "submerged, a travelling undulation down spine and tail" },
	"surface_lunge":   { "duration": 2.0, "contact_tick": 30, "loop": false, "key": 1.0, "note": "quivers under, bursts up jaws wide with frill flared, slams down, settles" },
	"bite_back_miss":  { "duration": 1.6, "contact_tick": -1, "loop": false, "key": 0.7, "note": "neck and head crane round to the rear, snap shut on nothing, frustrated shake back" },
}

const SPINE := ["hips", "spine_0", "spine_1", "chest"]
const NECK := ["neck", "head"]
const TAIL := ["tail_0", "tail_1", "tail_2", "tail_3"]
const FINS := ["fin_0", "fin_1", "fin_2"]
const FIN_FOLD := -78.0  ## sail pitch when laid flat back along the body
const FRONT := ["fl", "fr"]
const HIND := ["hl", "hr"]
const UNDER := -2.5      ## root drop when submerged (m; -2.1 before the Phase 3.5 skull, which stands taller)
const FLOAT := -1.72     ## root drop when floating calm (m): eyes and frill at the surface


static func clip_list() -> PackedStringArray:
	return PackedStringArray(CLIPS.keys())


static func pose(clip: String, t: float, b: HHMonsterBody) -> void:
	match clip:
		"calm_float": _calm_float(t, b)
		"aggravated_idle": _aggravated_idle(t, b)
		"frill_roar": _frill_roar(t, b)
		"walk": _walk(t, b)
		"hit_react": _hit_react(t, b)
		"stagger": _stagger(t, b)
		"collapse": _collapse(t, b)
		"death": _death(t, b)
		"dark_spray": _dark_spray(t, b)
		"water_jet": _water_jet(t, b)
		"thrash_splash": _thrash_splash(t, b)
		"death_roll_spin": _death_roll_spin(t, b)
		"dive": _dive(t, b)
		"swim": _swim(t, b)
		"surface_lunge": _surface_lunge(t, b)
		"bite_back_miss": _bite_back_miss(t, b)


# ------------------------------------------------------------------ helpers

## 0..1 across [a, b], smoothstepped.
static func _ss(t: float, a: float, c: float) -> float:
	if c <= a:
		return 1.0 if t >= c else 0.0
	return smoothstep(0.0, 1.0, clampf((t - a) / (c - a), 0.0, 1.0))


## 0..1 across [a, c], fast out (a snap): 1 - (1 - u)^3.
static func _snap(t: float, a: float, c: float) -> float:
	var u := clampf((t - a) / maxf(c - a, 1e-4), 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


## 0..1 across [a, c], slow in (a coil): u^3.
static func _coil(t: float, a: float, c: float) -> float:
	var u := clampf((t - a) / maxf(c - a, 1e-4), 0.0, 1.0)
	return u * u * u


## A decaying shake: sin at `hz`, amplitude falling over `life` from `t0`.
static func _shake(t: float, t0: float, life: float, hz: float) -> float:
	if t < t0:
		return 0.0
	var u := (t - t0) / maxf(life, 1e-4)
	if u >= 1.0:
		return 0.0
	return sin((t - t0) * TAU * hz) * (1.0 - u) * (1.0 - u)


## Overshoot: rises to 1 by `c`, swings past to 1 + amt and settles by `end`.
static func _over(t: float, a: float, c: float, end: float, amt: float) -> float:
	if t <= c:
		return _snap(t, a, c)
	var u := clampf((t - c) / maxf(end - c, 1e-4), 0.0, 1.0)
	return 1.0 + amt * sin(u * PI) * (1.0 - u)


## Roll the whole body about its own long axis at height `h` (not about
## the ground origin, which would swing the body through the floor).
static func _roll_about(b: HHMonsterBody, roll_deg: float, h: float) -> void:
	var c := Vector3(0.0, h, 0.0)
	b.rot("root", Vector3(0.0, 0.0, roll_deg))
	b.move("root", c - Basis(Vector3.BACK, deg_to_rad(roll_deg)) * c)


static func _frill(b: HHMonsterBody, flare: float) -> void:
	# at rest the frill rakes back; flaring swings the tips forward and up
	b.rot("frill_l", Vector3(0.0, -48.0 * flare, 28.0 * flare))
	b.rot("frill_r", Vector3(0.0, 48.0 * flare, -28.0 * flare))


## The crest and dorsal sails: `raise` 1 = up (the rest pose), 0 = laid flat
## back along the body (calm, swimming); `flick` adds a lagged ripple.
static func _fins(b: HHMonsterBody, raise: float, flick: float = 0.0) -> void:
	for k in FINS.size():
		b.rot(FINS[k], Vector3(FIN_FOLD * (1.0 - raise) + flick * (1.0 - 0.2 * k), 0.0, 0.0))


static func _jaw(b: HHMonsterBody, open_deg: float) -> void:
	b.rot("jaw", Vector3(open_deg, 0.0, 0.0))


## The tail paddles: a yaw wave travelling down the chain, phase-lagged.
static func _tail_sway(b: HHMonsterBody, t: float, period: float, amp_deg: float, lag: float = 0.22) -> void:
	for k in TAIL.size():
		var ph := TAU * (t / period - lag * k)
		b.rot(TAIL[k], Vector3(0.0, sin(ph) * amp_deg * (0.6 + 0.4 * k), 0.0))


## Breathing: the chest rises and the spine straightens a touch.
static func _breath(b: HHMonsterBody, t: float, period: float, amt: float) -> void:
	var s := 0.5 - 0.5 * cos(TAU * t / period)
	b.move("spine_1", Vector3(0.0, 0.06 * amt * s, 0.0))
	b.rot("spine_0", Vector3(-1.5 * amt * s, 0.0, 0.0))
	b.rot("chest", Vector3(1.2 * amt * s, 0.0, 0.0))
	b.rot("neck", Vector3(-1.0 * amt * s, 0.0, 0.0))


## One leg: swing/stance by phase 0..1 (0 = foot plants). A downward bone
## swings its tip forward with -pitch.
static func _leg(b: HHMonsterBody, leg: String, ph: float, stride_deg: float, lift_deg: float) -> void:
	ph = fposmod(ph, 1.0)
	if ph < 0.6:
		# stance: the foot pushes back under the body
		var u := ph / 0.6
		b.rot("hip_" + leg, Vector3(lerpf(-stride_deg, stride_deg, u), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lerpf(-4.0, 6.0, u), 0.0, 0.0))
	else:
		# swing: lift, fold, carry forward, reach
		var u := (ph - 0.6) / 0.4
		var arc := sin(u * PI)
		b.rot("hip_" + leg, Vector3(lerpf(stride_deg, -stride_deg, smoothstep(0.0, 1.0, u)), 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(lift_deg * arc, 0.0, 0.0))
		b.rot("ankle_" + leg, Vector3(-lift_deg * 0.6 * arc, 0.0, 0.0))


## Splayed front legs: elbows out, chest low (stagger, collapse).
static func _front_splay(b: HHMonsterBody, amt: float) -> void:
	for leg in FRONT:
		var s := 1.0 if leg == "fl" else -1.0
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 28.0 * amt))
		b.rot("knee_" + leg, Vector3(-30.0 * amt, 0.0, 0.0))
	for leg in HIND:
		var s := 1.0 if leg == "hl" else -1.0
		b.rot("hip_" + leg, Vector3(0.0, 0.0, s * 35.0 * amt))


# ------------------------------------------------------------------ idles

static func _calm_float(t: float, b: HHMonsterBody) -> void:
	# sunk to the collar: hips under, the frill and back fins break the surface
	var sway := sin(TAU * t / 5.0)
	var sway2 := sin(TAU * t / 5.0 + 1.3)
	b.move("root", Vector3(0.0, FLOAT + 0.05 * sway2, 0.0))
	b.rot("root", Vector3(0.0, 2.5 * sway, 0.0))
	_roll_about(b, 1.5 * sway2, 1.2)
	b.bend(SPINE, Vector3(-3.0, 6.0 * sway, 0.0))
	b.rot("neck", Vector3(-6.0 + 2.0 * sway2, 3.0 * sway, 0.0))       # eyes and nostrils at the surface, crocodile style
	b.rot("head", Vector3(-2.0, 0.0, 0.0))
	_tail_sway(b, t, 5.0, 8.0, 0.18)
	b.bend(TAIL, Vector3(-26.0, 0.0, 0.0), 0.8)                    # the tail sail hangs under the surface
	_fins(b, 0.05)                                                  # sails laid flat: only the frill shows
	_frill(b, 0.35 + 0.05 * sway2)
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(30.0, 0.0, 0.0))                      # legs trail, paddling
		b.rot("knee_" + leg, Vector3(20.0 + 6.0 * sway, 0.0, 0.0))


static func _aggravated_idle(t: float, b: HHMonsterBody) -> void:
	var s := sin(TAU * t / 3.0)
	_breath(b, t, 3.0, 1.0)
	_roll_about(b, 1.5 * s, 1.2)
	b.rot("neck", Vector3(-8.0, 6.0 * sin(TAU * t / 6.0), 0.0))        # scanning, head up
	b.rot("head", Vector3(-4.0 + 2.0 * s, 4.0 * sin(TAU * t / 6.0 + 0.6), 0.0))
	_jaw(b, 6.0 + 3.0 * s)
	_frill(b, 0.8 + 0.1 * s)
	_fins(b, 1.0, 3.0 * sin(TAU * t / 1.5))
	_tail_sway(b, t, 3.0, 14.0)
	b.rot("hip_fl", Vector3(2.0 * s, 0.0, 0.0))
	b.rot("hip_fr", Vector3(-2.0 * s, 0.0, 0.0))


static func _walk(t: float, b: HHMonsterBody) -> void:
	var ph := t / 1.6
	# diagonal pairs; the front legs carry the stride, the hind legs shuffle
	_leg(b, "fl", ph, 32.0, 45.0)
	_leg(b, "fr", ph + 0.5, 32.0, 45.0)
	_leg(b, "hr", ph + 0.1, 10.0, 18.0)
	_leg(b, "hl", ph + 0.6, 10.0, 18.0)
	# weight rolls onto the planted front foot; two bobs per cycle
	var roll := sin(TAU * ph) * 6.0
	_roll_about(b, roll, 1.2)
	b.move("root", Vector3(0.0, -0.06 + 0.1 * cos(TAU * ph * 2.0), 0.0))
	b.bend(SPINE, Vector3(0.0, -6.0 * sin(TAU * ph), -roll * 0.5), 1.2)
	b.rot("neck", Vector3(-6.0 - 2.0 * cos(TAU * ph * 2.0), 4.0 * sin(TAU * ph), 0.0))
	b.rot("head", Vector3(-2.0 + 2.0 * cos(TAU * ph * 2.0 + 0.5), 0.0, 0.0))
	_jaw(b, 5.0)
	_frill(b, 0.7)
	_tail_sway(b, t, 1.6, 18.0, 0.2)


static func _frill_roar(t: float, b: HHMonsterBody) -> void:
	# anticipation (0-0.6): crouch, head pulls back and down, frill folds flat
	# snap (0.6-0.75): head up, jaws wide, frill flares past full and settles
	# hold (0.75-1.7): the roar, shaking; release (1.7-2.4): back to the idle
	var a := _ss(t, 0.0, 0.6)
	var s := _snap(t, 0.6, 0.75)
	var flare := _over(t, 0.6, 0.75, 1.1, 0.3)
	var rel := _ss(t, 1.7, 2.4)
	var hold := s * (1.0 - rel)
	var sh := _shake(t, 0.75, 1.0, 11.0) * hold
	var crouch := a * (1.0 - s)
	b.move("root", Vector3(0.0, -0.3 * crouch + 0.2 * hold, -0.15 * crouch))
	b.bend(SPINE, Vector3(6.0 * crouch - 9.0 * hold, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(18.0 * crouch - 30.0 * hold, 3.0 * sh, 0.0))
	b.rot("head", Vector3(10.0 * crouch - 26.0 * hold, 2.0 * sh, 0.0))
	_jaw(b, 4.0 * crouch + 40.0 * hold + 3.0 * sh)
	_frill(b, 0.8 * (1.0 - a) + 1.0 * flare * s * (1.0 - rel * 0.2) + 0.08 * sh)
	_fins(b, 1.0 - 0.45 * crouch, 6.0 * (flare - 1.0) * s + 2.0 * sh)
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(8.0 * crouch - 12.0 * hold, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(10.0 * crouch, 0.0, 0.0))
	b.bend(TAIL, Vector3(-10.0 * crouch + 18.0 * hold, 0.0, 0.0), 1.3)
	_tail_sway(b, t, 2.4, 6.0 + 10.0 * hold, 0.25)


# ------------------------------------------------------------------ reactions

static func _hit_react(t: float, b: HHMonsterBody) -> void:
	var k := _snap(t, 0.0, 0.08) * (1.0 - _ss(t, 0.2, 0.6))
	b.rot("neck", Vector3(-10.0 * k, 18.0 * k, 0.0))
	b.rot("head", Vector3(-8.0 * k, 14.0 * k, 0.0))
	b.bend(SPINE, Vector3(0.0, 6.0 * k, 3.0 * k))
	b.move("root", Vector3(0.0, -0.06 * k, -0.12 * k))
	_jaw(b, 18.0 * k)
	_frill(b, 0.8 + 0.2 * k + 0.1 * _shake(t, 0.05, 0.4, 14.0))
	_tail_sway(b, t, 0.6, 10.0 * k)


static func _stagger(t: float, b: HHMonsterBody) -> void:
	var sag := _snap(t, 0.0, 0.25) * (1.0 - _ss(t, 0.9, 1.5))
	var wobble := _shake(t, 0.25, 1.0, 3.0)
	b.move("root", Vector3(0.0, -0.45 * sag, 0.0))
	_roll_about(b, 10.0 * wobble * sag, 0.9)
	_front_splay(b, 0.8 * sag)
	b.bend(SPINE, Vector3(4.0 * sag, 10.0 * wobble * sag, 0.0))
	b.rot("neck", Vector3(16.0 * sag, 12.0 * wobble * sag, 0.0))
	b.rot("head", Vector3(12.0 * sag, 0.0, 0.0))
	_jaw(b, 12.0 * sag)
	_frill(b, 0.8 - 0.5 * sag)
	_tail_sway(b, t, 1.5, 12.0 * sag)


static func _collapse(t: float, b: HHMonsterBody) -> void:
	var d := _ss(t, 0.0, 1.3)
	var bounce := _shake(t, 1.3, 0.6, 2.5) * 0.06
	b.move("root", Vector3(0.0, -0.95 * d + bounce, 0.0))
	_front_splay(b, d)
	b.bend(SPINE, Vector3(6.0 * d, 0.0, 0.0), 0.8)
	b.rot("neck", Vector3(22.0 * d, 0.0, 0.0))
	b.rot("head", Vector3(14.0 * d, 0.0, 0.0))
	_jaw(b, 20.0 * d)
	_frill(b, 0.8 * (1.0 - d))
	_fins(b, 1.0 - 0.45 * d)
	b.bend(TAIL, Vector3(-10.0 * d, 0.0, 0.0))


static func _death(t: float, b: HHMonsterBody) -> void:
	_collapse(minf(t, 2.0), b)
	var r := _ss(t, 1.5, 2.7)
	_roll_about(b, 70.0 * r, 0.55)
	b.move("root", Vector3(0.0, 0.25 * r, 0.0))
	b.rot("neck", Vector3(0.0, 0.0, -12.0 * r))
	_jaw(b, 20.0 * r)
	for leg in FRONT + HIND:
		b.rot("hip_" + leg, Vector3(-25.0 * r, 0.0, 0.0))


# ------------------------------------------------------------------ attacks

static func _dark_spray(t: float, b: HHMonsterBody) -> void:
	# anticipation: frill flares wide, the head draws back and up, the chest fills
	var a := _ss(t, 0.0, 0.9)
	# release: the head whips down and forward (contact at 1.2 s)
	var w := _snap(t, 0.9, 1.2)
	var hold := _ss(t, 1.2, 1.3) * (1.0 - _ss(t, 1.6, 2.2))
	var rec := _ss(t, 1.6, 2.2)
	var k := a * (1.0 - w)                            # the coil, undone by the whip
	_frill(b, 0.8 + 0.4 * a * (1.0 - rec) + 0.1 * _shake(t, 1.2, 0.5, 18.0))
	b.move("root", Vector3(0.0, 0.14 * k, -0.2 * k))
	b.bend(SPINE, Vector3(-7.0 * k + 2.0 * w * (1.0 - rec), 0.0, 0.0), 1.3)
	b.rot("neck", Vector3(-34.0 * k + 4.0 * w * (1.0 - rec), 0.0, 0.0))
	b.rot("head", Vector3(-20.0 * k + 8.0 * w * (1.0 - rec), 3.0 * _shake(t, 1.2, 0.5, 9.0) * hold, 0.0))
	_jaw(b, 8.0 * a + 38.0 * w * (1.0 - rec))
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(-10.0 * k + 6.0 * w * (1.0 - rec), 0.0, 0.0))   # braces back, then plants
	_tail_sway(b, t, 2.2, 8.0 + 12.0 * w * (1.0 - rec), 0.25)


static func _water_jet(t: float, b: HHMonsterBody) -> void:
	# coil: the neck folds back and the head drops low (0-0.7); thrust (0.7-1.0)
	var c := _coil(t, 0.0, 0.7)
	var th := _snap(t, 0.7, 1.0)
	var rec := _ss(t, 1.5, 2.0)
	var k := c * (1.0 - th)
	var push := th * (1.0 - rec)
	b.move("root", Vector3(0.0, -0.12 * k + 0.05 * push, -0.25 * k + 0.45 * push))
	b.bend(SPINE, Vector3(3.0 * k - 4.0 * push, 0.0, 0.0), 1.4)
	b.rot("neck", Vector3(26.0 * k - 12.0 * push, 0.0, 0.0))
	b.rot("head", Vector3(-30.0 * k + 6.0 * push, 0.0, 0.0))          # chin tucked while coiled, level on the thrust
	_jaw(b, 6.0 * k + 30.0 * push + 2.0 * _shake(t, 1.0, 0.5, 20.0) * push)
	_frill(b, 0.8 - 0.3 * k + 0.2 * push)
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(-8.0 * k + 10.0 * push, 0.0, 0.0))
	b.bend(TAIL, Vector3(0.0, 0.0, 0.0))
	_tail_sway(b, t, 2.0, 10.0, 0.25)


static func _thrash_splash(t: float, b: HHMonsterBody) -> void:
	# coil one way and rise (0-1.0); whip the other way and slam (1.0-1.3,
	# contact 1.3); a smaller return whip (1.3-1.9); settle
	var c := _ss(t, 0.0, 1.0)
	var w := _snap(t, 1.0, 1.3)
	var w2 := _ss(t, 1.3, 1.9)
	var rec := _ss(t, 1.9, 2.4)
	var yaw := 30.0 * c - 80.0 * w + 44.0 * w2
	yaw *= (1.0 - rec)
	var tail_yaw := -50.0 * c + 130.0 * w - 70.0 * w2
	tail_yaw *= (1.0 - rec)
	b.move("root", Vector3(0.0, 0.32 * c * (1.0 - w) - 0.18 * w * (1.0 - w2) * (1.0 - rec), 0.0))
	_roll_about(b, -10.0 * c * (1.0 - w) + 14.0 * w * (1.0 - w2), 1.2)
	b.bend(SPINE, Vector3(-4.0 * c * (1.0 - w), yaw, 0.0), 1.2)
	b.rot("neck", Vector3(-10.0 * c * (1.0 - w) + 10.0 * w * (1.0 - rec), yaw * 0.6, 0.0))
	b.rot("head", Vector3(0.0, yaw * 0.4, 0.0))
	b.bend(TAIL, Vector3(16.0 * c * (1.0 - w) - 10.0 * w * (1.0 - rec), tail_yaw, 0.0), 1.3)
	_jaw(b, 10.0 * c + 20.0 * w * (1.0 - rec))
	_frill(b, 0.8 + 0.2 * c)
	for leg in FRONT:
		var s := 1.0 if leg == "fl" else -1.0
		b.rot("hip_" + leg, Vector3(-12.0 * c * (1.0 - w), 0.0, s * 10.0 * w * (1.0 - rec)))


static func _death_roll_spin(t: float, b: HHMonsterBody) -> void:
	# momentum: rocking with growing amplitude (0-1.6, contact 1.6); then two
	# full rolls about the body axis (1.6-3.0); wobble out
	var roll := 0.0
	if t < 1.6:
		var u := t / 1.6
		roll = sin(TAU * t / 0.8) * (8.0 + 36.0 * u * u)
	elif t < 3.0:
		var u := (t - 1.6) / 1.4
		var e := u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65       # eases in, runs out hard
		roll = sin(TAU * 1.6 / 0.8) * 44.0 + 720.0 * e
	else:
		roll = 720.0 + _shake(t, 3.0, 0.6, 3.0) * 20.0
	var tuck := _ss(t, 0.0, 1.6) * (1.0 - _ss(t, 3.0, 3.6))
	_roll_about(b, roll, 1.25)
	b.move("root", Vector3(0.0, 0.15 * tuck + 0.12 * absf(sin(deg_to_rad(roll))) * tuck, 0.0))
	b.bend(SPINE, Vector3(-4.0 * tuck, 0.0, 10.0 * tuck), 1.2)
	b.rot("neck", Vector3(12.0 * tuck, 0.0, 0.0))                # head tucked in
	b.rot("head", Vector3(10.0 * tuck, 0.0, 0.0))
	_jaw(b, 28.0 * tuck)
	_frill(b, 0.8 + 0.2 * tuck)
	b.bend(TAIL, Vector3(0.0, 0.0, 30.0 * tuck), 1.5)             # the paddle twists into the roll
	for leg in FRONT + HIND:
		b.rot("hip_" + leg, Vector3(30.0 * tuck, 0.0, 0.0))        # legs pulled in
		b.rot("knee_" + leg, Vector3(20.0 * tuck, 0.0, 0.0))


# ------------------------------------------------------------------ water

static func _dive(t: float, b: HHMonsterBody) -> void:
	var rear := _ss(t, 0.0, 0.5) * (1.0 - _ss(t, 0.5, 1.0))
	var plunge := _ss(t, 0.5, 1.2)
	var slap := _ss(t, 0.95, 1.15) * (1.0 - _ss(t, 1.25, 1.5))
	var sink := _ss(t, 0.9, 1.8)
	# the hips stay near the surface while the nose goes under; the paddle
	# comes up out of the water and slaps as the body follows it down
	b.move("root", Vector3(0.0, 0.25 * rear + 0.3 * plunge * (1.0 - sink) + UNDER * sink, 0.8 * plunge))
	b.rot("root", Vector3(-10.0 * rear + 42.0 * plunge * (1.0 - sink * 0.5), 0.0, 0.0))
	b.bend(SPINE, Vector3(-8.0 * rear + 12.0 * plunge, 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-16.0 * rear + 20.0 * plunge, 0.0, 0.0))
	b.rot("head", Vector3(-8.0 * rear + 14.0 * plunge, 0.0, 0.0))
	_jaw(b, 8.0 * rear)
	_frill(b, 0.8 * (1.0 - plunge))
	_fins(b, 1.0 - plunge)
	b.bend(TAIL, Vector3(75.0 * slap - 30.0 * _ss(t, 1.2, 1.4) * (1.0 - _ss(t, 1.5, 1.8)), 0.0, 0.0), 1.2)
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(-20.0 * rear + 35.0 * plunge, 0.0, 0.0))


static func _swim(t: float, b: HHMonsterBody) -> void:
	b.move("root", Vector3(0.0, UNDER + 0.05 * sin(TAU * t / 2.0), 0.0))
	var chain := SPINE + NECK
	for k in chain.size():
		var ph := TAU * (t / 2.0 + 0.12 * k)
		b.rot(chain[k], Vector3(0.0, sin(ph) * 5.0, 0.0))
	_tail_sway(b, t, 1.0, 22.0, 0.2)
	b.rot("neck", Vector3(-6.0, 0.0, 0.0))
	_frill(b, 0.1)
	_fins(b, 0.0)
	b.bend(TAIL, Vector3(-22.0, 0.0, 0.0), 0.8)                    # the tail sail stays under
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(34.0, 0.0, 0.0))
		b.rot("knee_" + leg, Vector3(22.0, 0.0, 0.0))
	for leg in HIND:
		b.rot("hip_" + leg, Vector3(30.0, 0.0, 0.0))


static func _surface_lunge(t: float, b: HHMonsterBody) -> void:
	var quiver := _shake(t, 0.0, 0.7, 12.0) * (1.0 - _ss(t, 0.5, 0.7))
	var up := _over(t, 0.6, 1.0, 1.3, 0.25)       # bursts past the surface, contact 1.0
	var down := _ss(t, 1.0, 1.4)
	var settle := _ss(t, 1.4, 2.0)
	var y := UNDER * (1.0 - up) + 0.9 * up * (1.0 - down)
	b.move("root", Vector3(0.03 * quiver, y, 0.3 * up * (1.0 - settle)))
	b.rot("root", Vector3(-28.0 * up * (1.0 - down) + 8.0 * down * (1.0 - settle), 0.0, 0.0))
	b.bend(SPINE, Vector3(-10.0 * up * (1.0 - down), 0.0, 0.0), 1.2)
	b.rot("neck", Vector3(-22.0 * up * (1.0 - down) + 16.0 * down * (1.0 - settle), 0.0, 0.0))
	b.rot("head", Vector3(-12.0 * up * (1.0 - down) + 10.0 * down * (1.0 - settle), 0.0, 0.0))
	_jaw(b, 42.0 * up * (1.0 - settle))
	_frill(b, 0.1 + 0.9 * up)
	_fins(b, clampf(up, 0.0, 1.0), 8.0 * (up - 1.0))
	b.bend(TAIL, Vector3(-30.0 * up * (1.0 - down) + 20.0 * down * (1.0 - settle), 0.0, 0.0), 1.3)
	for leg in FRONT:
		b.rot("hip_" + leg, Vector3(30.0 * (1.0 - up) - 20.0 * up * (1.0 - down), 0.0, 0.0))


static func _bite_back_miss(t: float, b: HHMonsterBody) -> void:
	# crane round to the left-rear (0-0.6), snap shut on nothing (0.6-0.75),
	# a frustrated shake, back to front (1.1-1.6)
	var crane := _ss(t, 0.0, 0.6) * (1.0 - _ss(t, 1.1, 1.6))
	var snap := _snap(t, 0.6, 0.72)
	var open := _ss(t, 0.1, 0.55) * (1.0 - snap)
	var shake := _shake(t, 0.75, 0.5, 8.0) * crane
	b.bend(SPINE, Vector3(0.0, 34.0 * crane, -6.0 * crane), 1.6)
	b.rot("neck", Vector3(4.0 * crane, 48.0 * crane + 4.0 * shake, 0.0))
	b.rot("head", Vector3(6.0 * crane, 36.0 * crane + 6.0 * shake, 0.0))
	_jaw(b, 34.0 * open)
	_frill(b, 0.8 + 0.2 * crane)
	_roll_about(b, -5.0 * crane, 1.2)
	b.bend(TAIL, Vector3(0.0, -26.0 * crane, 0.0), 1.2)               # the tail swings the other way, out of reach
	b.rot("hip_fl", Vector3(-10.0 * crane, 0.0, 0.0))
	b.rot("hip_fr", Vector3(8.0 * crane, 0.0, 0.0))
