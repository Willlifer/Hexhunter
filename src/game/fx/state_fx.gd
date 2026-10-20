class_name HHStateFx
extends Node3D
## Lane FX (H708, L-18): standing state effects on a monster so its state
## reads at 30 m on its own ground, beside the role-material drives in
## HHMonsterBody (H601):
##   Colambros smoulder   an ember halo rising off the quills (back / hips),
##                        an ember trail when it moves, a warm light pooled
##                        on the ground under it (reads on dark caldera rock)
##   Rimeslithe cold>0.5  frost mist rolling off the crystals and sinking
## Reads the unit and the body's sockets by name; one instance per monster.

var layer: Node                   ## HHFxLayer
var unit_id := ""
var add: HHFxParticles
var mix: HHFxParticles
var light: OmniLight3D
var rng := RandomNumberGenerator.new()
var _acc := {}
var _last_pos := Vector3.INF


func _init() -> void:
	add = HHFxParticles.new(120, true)
	add_child(add)
	mix = HHFxParticles.new(70, false)
	add_child(mix)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.visible = false
	light.omni_attenuation = 1.2
	add_child(light)


func _rate(chan: String, per_s: float, delta: float) -> int:
	var a := float(_acc.get(chan, 0.0)) + per_s * delta
	var n := int(floor(a))
	_acc[chan] = a - n
	return n


func _sock(u: Dictionary, socket_name: String, fallback: Vector3) -> Vector3:
	var local := fallback
	var body: Node = layer.body_of(unit_id) if layer != null else null
	if body != null and body.has_method("socket") and body.call("socket", socket_name) != null:
		local = body.call("socket_pos", socket_name)
	return Transform3D(Basis(Vector3.UP, float(u.get("facing", 0.0))), u.pos) * local


func update(sim: HHSim, delta: float) -> void:
	var u := sim.unit(unit_id)
	light.visible = false
	if u.is_empty() or not sim.alive(u):
		add.step(delta)
		mix.step(delta)
		return
	var pos: Vector3 = u.pos
	var moved := 0.0 if _last_pos == Vector3.INF else pos.distance_to(_last_pos) / maxf(delta, 1e-4)
	_last_pos = pos
	if bool(u.get("smoulder", false)):
		_smoulder(u, moved, delta)
	var cold := float(u.get("cold", 0.0))
	if cold > 0.5:
		_cold(u, cold, delta)
	add.step(delta)
	mix.step(delta)


func _smoulder(u: Dictionary, moved: float, delta: float) -> void:
	var back := _sock(u, "back", Vector3(0, 3.0, 1.1))
	var hips := _sock(u, "hips_top", Vector3(0, 2.5, -0.55))
	var head := _sock(u, "head_top", Vector3(0, 3.4, 3.3))
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.0075)
	light.visible = true
	light.position = (back + hips) * 0.5 + Vector3(0, -0.8, 0)
	light.light_color = Color(1.0, 0.42, 0.12)
	light.light_energy = 2.6 * pulse
	light.omni_range = 6.5
	for i in _rate("halo", 34.0, delta):
		var t := rng.randf()
		var base := hips.lerp(back, t) if t < 0.7 else back.lerp(head, (t - 0.7) / 0.3)
		var q := base + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.2, 0.4), rng.randf_range(-0.7, 0.7))
		add.spawn({ "pos": q, "vel": Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.0, 2.2), rng.randf_range(-0.3, 0.3)), "life": rng.randf_range(0.7, 1.3),
			"size": 0.1, "size_end": 0.04, "color": Color(1.0, 0.7, 0.25, 1.0), "color_end": Color(0.9, 0.15, 0.03, 0.0), "drag": 0.5,
			"shape": HHFxParticles.STREAK, "streak": 0.05 })
	if moved > 1.0:
		var f := float(u.get("facing", 0.0))
		var back_dir := -Vector3(sin(f), 0, cos(f))
		for i in _rate("trail", 10.0 + 4.0 * moved, delta):
			var q := hips + back_dir * rng.randf_range(0.0, 1.5) + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-1.6, 0.2), rng.randf_range(-0.6, 0.6))
			add.spawn({ "pos": q, "vel": back_dir * rng.randf_range(0.5, 1.5) + Vector3(0, rng.randf_range(0.3, 1.0), 0), "life": 0.9,
				"size": 0.12, "size_end": 0.05, "color": Color(1.0, 0.6, 0.2, 1.0), "color_end": Color(0.8, 0.12, 0.02, 0.0), "shape": HHFxParticles.STREAK, "streak": 0.06 })


func _cold(u: Dictionary, cold: float, delta: float) -> void:
	var k := clampf((cold - 0.5) * 2.0, 0.0, 1.0)
	var pts := [_sock(u, "back", Vector3(0, 3.5, 0.7)), _sock(u, "shoulder_l", Vector3(1.0, 3.3, 1.85)), _sock(u, "shoulder_r", Vector3(-1.0, 3.3, 1.85))]
	var o: Vector3 = u.pos
	for i in _rate("mist", 8.0 + 22.0 * k, delta):
		var q: Vector3 = pts[rng.randi() % pts.size()] + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.5, 0.5))
		var out := q - o
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3.RIGHT
		mix.spawn({ "pos": q, "vel": out * rng.randf_range(0.6, 1.4) + Vector3(0, -0.3, 0), "life": rng.randf_range(1.6, 2.2), "size": 0.3, "size_end": 1.3,
			"color": Color(0.88, 0.97, 1.0, 0.25 + 0.3 * k), "color_end": Color(0.88, 0.97, 1.0, 0.0), "grav": 0.6, "drag": 0.6, "shape": HHFxParticles.PUFF })
	for i in _rate("glint", 10.0 * k, delta):
		add.spawn({ "pos": pts[rng.randi() % pts.size()] + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.8), rng.randf_range(-0.8, 0.8)),
			"vel": Vector3(0, -0.4, 0), "life": 0.7, "size": 0.07, "color": Color(0.75, 0.95, 1.0, 1.0), "shape": HHFxParticles.SPARK })
