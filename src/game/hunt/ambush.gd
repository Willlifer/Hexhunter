class_name HHAmbush
extends Node3D
## The ambush cutscene (Lane H, H48): the monster's own arena loads, the
## hunter stands at the player spawn, the water / ground / shade at the
## monster spawn pulses, then the monster bursts out (scale-up, rise, its
## roar clip, a spray of the biome's motes), the camera swings from the
## hunter to the monster, the monster's name slams in, and the screen ends
## with finished({ result: "ambushed" }). Any key or click skips it
## (finished({ result: "skipped" })). About four seconds (hunt_ambush_*).
##
## Everything visual is a function of `time`, so `scrub(t)` (the capture
## tool) lands on the same frame as playing to t.

signal finished(result: Dictionary)

const PHASES := ["lurk", "burst", "name", "done"]

var cfg := {}
var arena: HHArena
var asset: GKAsset
var view: HHArenaView
var camera: HHCameraRig
var hunter: Node3D
var monster: Node3D
var monster_id := ""
var biome := "pond"
var time := 0.0
var _rings: Array = []
var _motes: CPUParticles3D
var _spot: OmniLight3D
var _name: Label
var _sub: Label
var _band: TitleBand                 ## Lane UI: the plate behind the name (the HUD's banner language)
var _bars: Array = []
var _roared := false
var _done := false
var _setup_done := false
var _hunter_pos := Vector3.ZERO
var _monster_pos := Vector3.ZERO


## Which beat of the cutscene a time falls in (pure, for tests).
static func phase_at(t: float) -> String:
	if t >= HHHuntKit.t("ambush_seconds"):
		return "done"
	if t >= HHHuntKit.t("ambush_name_at"):
		return "name"
	if t >= HHHuntKit.t("ambush_burst_at"):
		return "burst"
	return "lurk"


## The monster's threat clip, checked against its clip table when Lane E's body is there.
static func roar_clip(id: String) -> String:
	var want := str(HHHuntKit.ROAR.get(id, "aggravated_idle"))
	if ResourceLoader.exists("res://src/monster/monster_body.gd"):
		var s: GDScript = load("res://src/monster/monster_body.gd")
		var table: Dictionary = s.clips(id)
		if not table.is_empty() and not table.has(want):
			return "aggravated_idle" if table.has("aggravated_idle") else str(table.keys()[0])
	return want


static func peak_time() -> float:
	return HHHuntKit.t("ambush_name_at") + 0.45


# ------------------------------------------------------------------ setup

func setup(p_cfg: Dictionary) -> void:
	if _setup_done:
		return
	_setup_done = true
	cfg = p_cfg
	monster_id = str(cfg.get("monster", "swampfang"))
	biome = str(cfg.get("arena", HHHuntFlow.biome_of(monster_id)))
	var loaded := HHHuntKit.load_arena(biome, int(cfg.get("seed", 1)))
	arena = loaded.arena
	asset = loaded.asset
	view = HHArenaView.new()
	view.name = "ArenaView"
	add_child(view)
	view.build(arena, asset)
	_hunter_pos = arena.stand(arena.spawns.player[0])
	_monster_pos = arena.stand(arena.spawns.monster)
	hunter = HHHuntKit.hunter_body(str(cfg.get("weapon", "lance")))
	hunter.name = "Hunter"
	hunter.position = _hunter_pos
	hunter.rotation.y = _yaw_from_to(_hunter_pos, _monster_pos)
	add_child(hunter)
	monster = HHHuntKit.monster_body(monster_id)
	monster.name = monster_id
	monster.position = _monster_pos + Vector3(0, -3.0, 0)
	monster.rotation.y = _yaw_from_to(_monster_pos, _hunter_pos)
	monster.scale = Vector3.ONE * 0.02
	monster.visible = false
	add_child(monster)
	if monster.has_method("play"):
		monster.play("aggravated_idle")
	var d := HHHuntKit.disturbance(biome)
	var sy := arena.surface(arena.spawns.monster).y
	for k in 3:
		var r := HHHuntKit.ring(d.ring, 0.16)
		r.position = Vector3(_monster_pos.x, sy + 0.08, _monster_pos.z)
		add_child(r)
		_rings.append(r)
	_spot = OmniLight3D.new()                   # a stage light on the monster as it rises (the cave is dark)
	_spot.name = "Spot"
	_spot.position = _monster_pos + Vector3(0, 9.0, 0)
	_spot.omni_range = 18.0
	_spot.light_color = (d.mote as Color).lerp(Color.WHITE, 0.5)
	_spot.light_energy = 0.0
	_spot.shadow_enabled = false
	add_child(_spot)
	_motes = HHHuntKit.motes(biome, 90, 2.5)
	_motes.position = Vector3(_monster_pos.x, sy, _monster_pos.z)
	_motes.lifetime = 1.4
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 7.0
	_motes.spread = 60.0
	_motes.gravity = Vector3(0, -6.0, 0)
	_motes.explosiveness = 0.95
	_motes.one_shot = true
	_motes.emitting = false
	add_child(_motes)
	camera = HHCameraRig.new()
	camera.name = "CameraRig"
	camera.input_enabled = false
	add_child(camera)
	_build_hud()
	_apply(0.0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	for k in 2:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if k == 0 else 1.0
		bar.anchor_bottom = 0.0 if k == 0 else 1.0
		bar.offset_top = 0.0 if k == 0 else -1.0
		bar.offset_bottom = 1.0 if k == 0 else 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		_bars.append(bar)
	_band = TitleBand.new()
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_band)
	_name = HHHuntKit.label(HHHuntFlow.display_name(monster_id).to_upper(), 104, Color(1.0, 0.9, 0.62))
	_name.add_theme_font_override("font", HHHud.serif())
	_name.add_theme_constant_override("outline_size", 14)
	_name.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.0, 0.95))
	_name.set_anchors_preset(Control.PRESET_CENTER)
	_name.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name.grow_vertical = Control.GROW_DIRECTION_BOTH
	_name.position.y += 200.0                        # lower third: the monster stays in view
	_name.modulate = Color(1, 1, 1, 0)
	layer.add_child(_name)
	_sub = HHHuntKit.label("ambushes you in %s" % HHHuntFlow.display_name(biome), 28, Color(1.0, 0.95, 0.86))
	_sub.add_theme_font_override("font", HHHud.serif())
	_sub.set_anchors_preset(Control.PRESET_CENTER)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.grow_vertical = Control.GROW_DIRECTION_BOTH
	_sub.position.y += 286.0
	_sub.modulate = Color(1, 1, 1, 0)
	layer.add_child(_sub)
	var skip := HHHuntKit.label("any key: skip", 16, Color(0.8, 0.8, 0.8))
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	skip.position -= Vector2(16, 16)
	layer.add_child(skip)


# ------------------------------------------------------------------ timeline

var paused := false          ## tools: hold the frame after a scrub


func _process(delta: float) -> void:
	if not _setup_done or _done or paused:
		return
	_advance(delta)


## Step the cutscene by delta: one-shots fire on crossing their time.
func _advance(delta: float) -> void:
	var before := time
	time += delta
	var burst_at := HHHuntKit.t("ambush_burst_at")
	if before < burst_at and time >= burst_at:
		_burst()
	if monster.has_method("update"):
		monster.update(delta)
	if hunter.has_method("update"):
		hunter.update(delta)
	_apply(delta)
	if time >= HHHuntKit.t("ambush_seconds"):
		_finish("ambushed")


## Land on time t exactly (tools): stepped at 30 Hz so one-shots still fire.
func scrub(t: float) -> void:
	while time < t - 1e-6:
		_advance(minf(1.0 / 30.0, t - time))


func _burst() -> void:
	_roared = true
	monster.visible = true
	if monster.has_method("play"):
		monster.play(roar_clip(monster_id), false)
	if _motes.is_inside_tree():                 # headless tests scrub out of the tree
		_motes.restart()
		_motes.emitting = true
	camera.shake(0.7)


## Everything continuous, from `time`.
func _apply(_delta: float) -> void:
	var burst_at := HHHuntKit.t("ambush_burst_at")
	var burst_s := HHHuntKit.t("ambush_burst_s")
	var name_at := HHHuntKit.t("ambush_name_at")
	# the monster: hidden, then up and out with an overshoot
	var k := clampf((time - burst_at) / burst_s, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)                          # ease out
	var over := 1.0 + 0.22 * sin(k * PI) * (1.0 - k)          # a bulge on the way up
	if time >= burst_at:
		monster.visible = true
		monster.scale = Vector3.ONE * maxf(0.02, e * over)
		monster.position = _monster_pos + Vector3(0, -3.0 * (1.0 - e) + 0.9 * sin(k * PI), 0)
	# the rings: pulse until the burst, then fade
	var period := 0.8
	for i in _rings.size():
		var r: MeshInstance3D = _rings[i]
		var ph := fmod(time / period + float(i) / 3.0, 1.0)
		var sc := maxf(0.3, ph * 7.0)
		r.scale = Vector3(sc, 1.0, sc)
		var m: StandardMaterial3D = r.material_override
		var base: Color = HHHuntKit.disturbance(biome).ring
		var fade := 1.0 - clampf((time - burst_at) / 0.5, 0.0, 1.0)
		m.albedo_color = Color(base.r, base.g, base.b, base.a * (1.0 - ph) * fade)
	# the camera: on the hunter, then a swing onto the monster
	var sw := smoothstep(0.0, 1.0, clampf((time - burst_at + 0.1) / (burst_s + 0.5), 0.0, 1.0))
	var yaw_h := _yaw_from_to(_monster_pos, _hunter_pos)         # behind the hunter, looking at the spawn
	var yaw_m := yaw_h + 0.38                                     # a touch off the hunter's line: the floor between them is clear of scenery
	if _spot != null:
		_spot.light_energy = 3.0 * smoothstep(0.0, 1.0, clampf((time - burst_at) / 0.4, 0.0, 1.0))
	var chest := Vector3(0, 2.4, 0)
	var pivot := (_hunter_pos + Vector3(0, 1.4, 0)).lerp(_monster_pos + chest, sw)
	camera.follow(pivot - Vector3(0, camera.pivot_lift, 0), true)   # snap: the rig's own lag would drift it
	camera.dist = lerpf(9.0, HHHuntKit.t("ambush_cam_dist"), sw)
	camera.pitch = deg_to_rad(lerpf(20.0, 16.0, sw))
	camera.yaw = lerp_angle(yaw_h, yaw_m, sw)
	# letterbox bars slide in over the first half second
	var bar_h := 70.0 * smoothstep(0.0, 1.0, clampf(time / 0.5, 0.0, 1.0))
	if _bars.size() == 2:
		(_bars[0] as ColorRect).offset_bottom = bar_h
		(_bars[1] as ColorRect).offset_top = -bar_h
	# the name slams in
	var nk := clampf((time - name_at) / 0.28, 0.0, 1.0)
	var ne := 1.0 - pow(1.0 - nk, 3.0)
	if _name != null:
		_name.modulate = Color(1, 1, 1, ne)
		var s := lerpf(3.2, 1.0, ne)
		_name.pivot_offset = _name.size * 0.5
		_name.scale = Vector2(s, s)
		_sub.modulate = Color(1, 1, 1, clampf((time - name_at - 0.3) / 0.35, 0.0, 1.0))
	if _band != null:
		_band.open = clampf((time - name_at + 0.05) / 0.3, 0.0, 1.0)
		_band.queue_redraw()


static func _yaw_from_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


func _finish(verdict: String) -> void:
	if _done:
		return
	_done = true
	finished.emit({ "result": verdict })


func _unhandled_input(ev: InputEvent) -> void:
	if _done:
		return
	if (ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed):
		_finish("skipped")


## The title card's band (Lane UI): a dark plate across the lower third,
## gold rules fading to the screen edges, diamond studs at the ends of the
## top rule; `open` (0..1) wipes it out from the centre.
class TitleBand:
	extends Control
	const Y := 200.0                 # the name's offset below the centre (as _name)
	const H := 190.0
	var open := 0.0

	func _draw() -> void:
		if open <= 0.0:
			return
		var pt := HHHud.Paint.new(get_canvas_item())
		var s := get_viewport_rect().size
		var cx := s.x * 0.5
		var cy := s.y * 0.5 + Y + 38.0
		var half := s.x * 0.5 * (1.0 - pow(1.0 - open, 3.0))
		var top := cy - H * 0.5
		var bot := cy + H * 0.5
		var dark := Color(0.03, 0.022, 0.015, 0.88)
		var clear := Color(dark.r, dark.g, dark.b, 0.0)
		var g := HHHud.GOLD
		var gc := Color(g.r, g.g, g.b, 0.0)
		for side in [-1.0, 1.0]:
			var x1: float = cx + side * half
			pt.poly_colors(PackedVector2Array([Vector2(cx, top), Vector2(x1, top), Vector2(x1, bot), Vector2(cx, bot)]),
				PackedColorArray([dark, clear, clear, dark]))
			for y in [top, bot]:
				var w: float = 1.0 if y == cy + 54.0 else 1.5
				var a := 0.9 if y != cy + 54.0 else 0.6
				var c0 := Color(g.r, g.g, g.b, a)
				pt.poly_colors(PackedVector2Array([Vector2(cx, y - w), Vector2(x1, y - w), Vector2(x1, y + w), Vector2(cx, y + w)]),
					PackedColorArray([c0, gc, gc, c0]))
		var d := Vector2(cx, top)
		pt.poly(PackedVector2Array([d + Vector2(0, -6), d + Vector2(6, 0), d + Vector2(0, 6), d + Vector2(-6, 0)]), g)

