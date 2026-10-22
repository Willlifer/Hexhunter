class_name HHTierFx
extends Node3D
## Lane M (H400-H389): the ground and body effects of the NORMAL-tier monster
## mechanics (HHTierBrain). It reads only the monster's unit (`u.tier`, plain
## replicated data) and `sim.tick`, so a co-op mirror draws the same thing as
## the host. HHMonsterBody makes one when its unit first carries `tier` (never
## on EASY) and calls update() every frame. Top-level: world coordinates.
## Unshaded alpha shaders only (Compatibility / web safe).
##
##   enrage   a heat ring round the hull + embers, both growing with enrage
##   pulse    the hull glows in the element colour before a pulse, flashes on it
##   purge    a ring building under the monster through the tell, a shockwave out
##            to the purge radius when it lands (blue quench, violet discharge)
##   fakeout  three corridors with yellow warning outlines (beat 1); G38-style
##            chevrons marching down one lane, or down the decoys with the true
##            lane's pointing inward (beat 2); the decoys vanish and the true
##            lane turns red (beat 3); an orb + light on the monster's true side
##   sweep    the rotating beam / hurricane, clockwise chevrons round the reach
##            circle, and the safe wedge behind blocks in green
##   siphon   the stalk path as a warning line flowing to the cluster, the
##            cluster outlined in its element
##   root     a ring of roots and a sun shaft; violet and drooping when stunned

const LIFT := 0.075
const YELLOW := Color(1.0, 0.86, 0.12)
const RED := Color(1.0, 0.18, 0.08)
const SAFE := Color(0.35, 1.0, 0.7)
const ROOT := Color(0.7, 0.95, 0.3)
const STUN := Color(0.7, 0.35, 1.0)
const ENRAGE := Color(1.0, 0.3, 0.06)
const EL := { "fire": Color(1.0, 0.45, 0.12), "water": Color(0.3, 0.65, 1.0), "ice": Color(0.7, 0.92, 1.0),
	"thunder": Color(0.75, 0.5, 1.0), "wind": Color(0.6, 1.0, 0.65), "dark": Color(0.55, 0.25, 0.9), "light": Color(1.0, 0.88, 0.4) }

const TILE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform int mode = 0;            // 0 lane, 1 safe, 2 cluster, 3 path
uniform vec4 col : source_color = vec4(1.0, 0.86, 0.12, 1.0);
uniform vec4 col2 : source_color = vec4(1.0, 0.18, 0.08, 1.0);
uniform vec2 lane_o = vec2(0.0);
uniform vec2 lane_d = vec2(0.0, 1.0);
uniform float half_w = 1.6;
uniform float len = 12.0;
uniform float chev = 0.0;        // 0..1 chevron strength
uniform float dir = 1.0;         // +1 chevrons point / march out of the monster, -1 inward
uniform float red = 0.0;         // 0..1 the lane turning red (beat 3)
uniform float alpha = 1.0;
varying vec3 wp;
varying vec2 lp;
float hexd(vec2 p) {
	p = abs(p);
	float a = max(p.x, dot(p, vec2(0.5, 0.8660254)));
	return max(a, abs(dot(p, vec2(-0.5, 0.8660254)))) / 0.8660254;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX.xz;
}
void fragment() {
	float d = hexd(lp);
	vec3 c = col.rgb;
	float a = 0.0;
	if (mode == 0) {
		vec2 q = wp.xz - lane_o;
		vec2 perp = vec2(-lane_d.y, lane_d.x);
		float s = dot(q, lane_d);
		float t = dot(q, perp);
		float inside = 1.0 - smoothstep(half_w - 0.05, half_w + 0.05, abs(t));
		// the warning outline: dashed yellow lines along both long edges and the far end
		float edge = 1.0 - smoothstep(0.0, 0.13, abs(abs(t) - half_w));
		float cap = (1.0 - smoothstep(0.0, 0.13, abs(s - len))) * inside;
		float dash = step(0.35, fract(s * 0.55 - TIME * 0.7));
		a = max(edge * dash, cap) * 0.95 + inside * 0.10;
		// G38 chevrons (Gamers Gauntlet Scorched Earth): lone chevrons marching along the lane
		float wc = t / half_w;
		float arms = 1.0 - smoothstep(0.62, 0.8, abs(wc));
		float f = fract((s * dir + abs(wc) * 1.5) * 0.42 - TIME * 1.6);
		float ch = smoothstep(0.52, 0.58, f) * (1.0 - smoothstep(0.80, 0.86, f)) * arms * inside;
		ch *= smoothstep(0.0, 1.0, s) * (1.0 - smoothstep(len - 0.6, len, s));
		a = max(a, ch * chev * 0.95);
		c = mix(col.rgb, col2.rgb, red);
		a = max(a, inside * red * 0.28);
	} else if (mode == 1) {
		float sh = 0.5 + 0.5 * sin(TIME * 3.0 + wp.x * 0.7 + wp.z * 0.5);
		a = 0.20 + 0.12 * sh;
		a = max(a, (1.0 - smoothstep(0.0, 0.06, abs(d - 0.9))) * 0.8);
	} else if (mode == 2) {
		float beat = 0.5 + 0.5 * sin(TIME * 7.0);
		a = 0.14 + 0.10 * beat;
		float rim = (1.0 - smoothstep(0.0, 0.08, abs(d - 0.88))) * (0.6 + 0.4 * beat);
		c = mix(col.rgb, vec3(1.0, 0.95, 0.6), rim * 0.7);
		a = max(a, rim);
	} else {
		float g = length(wp.xz - lane_o);
		float f = fract(g * 0.45 + TIME * 1.4);
		float band = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.35, 0.45, f));
		a = 0.40 + band * 0.6;
		a *= 1.0 - smoothstep(0.62, 0.8, d);
		a = max(a, (1.0 - smoothstep(0.0, 0.06, abs(d - 0.92))) * 0.55);
	}
	a *= alpha * (1.0 - smoothstep(0.985, 1.0, d));
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.3, 0.06, 1.0);
uniform float radius = 6.0;      // the quad's half size (m)
uniform float r_in = 2.4;
uniform float r_out = 3.0;
uniform float alpha = 0.5;
uniform float beat = 3.0;
uniform int mode = 0;            // 0 heat band, 1 clockwise chevrons, 2 solid flash
void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * radius;
	float r = length(p);
	float band = smoothstep(r_in - 0.2, r_in, r) * (1.0 - smoothstep(r_out, r_out + 0.2, r));
	float a = band;
	if (mode == 0) {
		float ang = atan(p.x, p.y);
		float flick = 0.6 + 0.4 * sin(TIME * beat + ang * 7.0 + sin(TIME * 1.7 + ang * 3.0) * 2.0);
		a *= flick;
	} else if (mode == 1) {
		float ang = atan(p.x, p.y);
		float s = -ang * (r_in + r_out) * 0.5;          // along the turn: clockwise from above
		float t = (r - (r_in + r_out) * 0.5) / max(0.01, (r_out - r_in) * 0.5);
		float f = fract((s + abs(t) * 1.2) * 0.38 - TIME * 1.8);
		float ch = smoothstep(0.5, 0.56, f) * (1.0 - smoothstep(0.78, 0.84, f)) * (1.0 - smoothstep(0.7, 0.95, abs(t)));
		a = band * (0.18 + 0.8 * ch);
	}
	ALBEDO = col.rgb;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.7, 0.92, 1.0, 1.0);
uniform float alpha = 1.0;
uniform int mode = 0;            // 0 beam, 1 hurricane
void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float y = UV.y;
	float a;
	vec3 c = col.rgb;
	if (mode == 0) {
		float core = 1.0 - smoothstep(0.0, 0.25, x);
		float glow = 1.0 - smoothstep(0.2, 1.0, x);
		float flow = 0.75 + 0.25 * sin(y * 40.0 - TIME * 18.0);
		a = core * 0.95 + glow * 0.45 * flow;
		c = mix(col.rgb, vec3(1.0), core * 0.6);
	} else {
		float sw = sin(y * 22.0 - TIME * 10.0 + x * 6.0) * 0.5 + 0.5;
		a = (1.0 - smoothstep(0.3, 1.0, x)) * (0.35 + 0.5 * sw);
	}
	a *= smoothstep(0.0, 0.04, y) * (1.0 - smoothstep(0.92, 1.0, y));
	ALBEDO = c;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

var sim: HHSim
var mid := ""
var body: Node3D

var _tile_shader: Shader
var _ring_shader: Shader
var _tiles: Array = []           # MeshInstance3D pool
var _used := 0
var _lane_mats: Array = []
var _safe_mat: ShaderMaterial
var _cluster_mat: ShaderMaterial
var _path_mat: ShaderMaterial
var _heat: MeshInstance3D
var _pulse: MeshInstance3D
var _purge: MeshInstance3D
var _sweep_ring: MeshInstance3D
var _root_ring: MeshInstance3D
var _beam: MeshInstance3D
var _orb: MeshInstance3D
var _orb_light: OmniLight3D
var _embers: CPUParticles3D
var _roots: Array = []
var _shaft: MeshInstance3D
var _t := 0.0

## H461 (lane LD): one Shader per code, shared by every HHTierFx. A Shader
## built per instance compiled again on each NORMAL fight's first tell (a
## browser stall); shared, the boot preload and HHWarmup compile it once.
static var _shared := {}


static func shared_shader(key: String) -> Shader:
	if not _shared.has(key):
		var sh := Shader.new()
		sh.code = { "tile": TILE_SHADER, "ring": RING_SHADER, "beam": BEAM_SHADER }[key]
		_shared[key] = sh
	return _shared[key]


## The runtime-built shaders, for HHWarmup.
static func warm_shaders() -> Array[Shader]:
	return [shared_shader("tile"), shared_shader("ring"), shared_shader("beam")]


func setup(p_sim: HHSim, p_id: String, p_body: Node3D = null) -> void:
	sim = p_sim
	mid = p_id
	body = p_body
	top_level = true
	name = "TierFx"
	_tile_shader = shared_shader("tile")
	_ring_shader = shared_shader("ring")
	for i in 3:
		_lane_mats.append(_tile_mat(0, YELLOW))
	_safe_mat = _tile_mat(1, SAFE)
	_cluster_mat = _tile_mat(2, EL.fire)
	_path_mat = _tile_mat(3, Color(1.0, 0.32, 0.08))
	_heat = _disc(ENRAGE, 0)
	_pulse = _disc(EL.fire, 0)
	_purge = _disc(EL.water, 0)
	_sweep_ring = _disc(RED, 1)
	_root_ring = _disc(ROOT, 0)
	var bm := ShaderMaterial.new()
	bm.shader = shared_shader("beam")
	_beam = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	_beam.mesh = pm
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	_orb.mesh = sm
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_color = Color(1.0, 0.95, 0.55)
	_orb.material_override = om
	_orb.visible = false
	add_child(_orb)
	_orb_light = OmniLight3D.new()
	_orb_light.light_color = Color(1.0, 0.85, 0.3)
	_orb_light.omni_range = 6.0
	_orb_light.visible = false
	add_child(_orb_light)
	_embers = CPUParticles3D.new()
	_embers.amount = 48
	_embers.lifetime = 1.4
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_embers.emission_ring_axis = Vector3.UP
	_embers.emission_ring_radius = 2.6
	_embers.emission_ring_inner_radius = 2.0
	_embers.emission_ring_height = 0.1
	_embers.direction = Vector3.UP
	_embers.spread = 20.0
	_embers.gravity = Vector3(0, 1.5, 0)
	_embers.initial_velocity_min = 0.8
	_embers.initial_velocity_max = 2.0
	var em := SphereMesh.new()
	em.radius = 0.06
	em.height = 0.12
	em.radial_segments = 4
	em.rings = 2
	_embers.mesh = em
	var emm := StandardMaterial3D.new()
	emm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emm.albedo_color = Color(1.0, 0.45, 0.1)
	emm.vertex_color_use_as_albedo = true
	_embers.material_override = emm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	grad.set_color(1, Color(0.8, 0.1, 0.02, 1.0))
	_embers.color_ramp = grad
	_embers.emitting = false
	add_child(_embers)
	for i in 18:
		var r := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.16
		cm.height = 1.4
		cm.radial_segments = 5
		cm.rings = 1
		r.mesh = cm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = ROOT
		r.material_override = rm
		r.visible = false
		add_child(r)
		_roots.append(r)
	_shaft = MeshInstance3D.new()
	var shm := CylinderMesh.new()
	shm.top_radius = 2.6
	shm.bottom_radius = 2.6
	shm.height = 9.0
	shm.cap_top = false
	shm.cap_bottom = false
	_shaft.mesh = shm
	var shmat := StandardMaterial3D.new()
	shmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shmat.albedo_color = Color(1.0, 0.95, 0.55, 0.13)
	_shaft.material_override = shmat
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft.visible = false
	add_child(_shaft)


func _tile_mat(mode: int, c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _tile_shader
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("col2", RED)
	return m


func _disc(c: Color, mode: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _ring_shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("mode", mode)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Lay a ring disc: centre `at`, outer band [r_in, r_out] metres.
func _ring(mi: MeshInstance3D, at: Vector3, r_in: float, r_out: float, a: float, c: Color, beat: float = 3.0) -> void:
	var half := r_out + 0.4
	mi.visible = a > 0.005
	if not mi.visible:
		return
	mi.global_transform = Transform3D(Basis().scaled(Vector3(half, 1.0, half)), at + Vector3(0, LIFT + 0.01, 0))
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("radius", half)
	m.set_shader_parameter("r_in", r_in)
	m.set_shader_parameter("r_out", r_out)
	m.set_shader_parameter("alpha", a)
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("beat", beat)


func _tile(h: Vector2i, mat: ShaderMaterial, lift: float = LIFT) -> void:
	if not sim.arena.exists(h):
		return
	var mi: MeshInstance3D
	if _used < _tiles.size():
		mi = _tiles[_used]
	else:
		mi = MeshInstance3D.new()
		mi.mesh = HHTileFX.hex_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tiles.append(mi)
	_used += 1
	mi.material_override = mat
	mi.global_transform = Transform3D(Basis(), sim.arena.surface(h) + Vector3(0, lift, 0))
	mi.visible = true


func _world(h: Vector2i) -> Vector3:
	return sim.arena.surface(h)


## Seconds since sim tick `k` (frame-smoothed by the caller's clock).
func _since(k: Variant) -> float:
	if k == null:
		return INF
	return float(sim.tick - int(k)) / 30.0


func update(delta: float) -> void:
	_t += delta
	_used = 0
	var u := sim.unit(mid) if sim != null else {}
	var T: Variant = u.get("tier")
	var live := T is Dictionary and sim.alive(u)
	var vis := { "beam": false, "orb": false, "sweep": false, "root": false }
	if live:
		_draw_state(u, T, vis)
	for i in range(_used, _tiles.size()):
		(_tiles[i] as MeshInstance3D).visible = false
	_beam.visible = vis.beam
	_orb.visible = vis.orb
	_orb_light.visible = vis.orb
	_sweep_ring.visible = _sweep_ring.visible and vis.sweep
	if not vis.root:
		_root_ring.visible = false
		_shaft.visible = false
		for r in _roots:
			(r as MeshInstance3D).visible = false
	if not live:
		_heat.visible = false
		_pulse.visible = false
		_purge.visible = false
		_sweep_ring.visible = false
		_embers.emitting = false


func _draw_state(u: Dictionary, T: Dictionary, vis: Dictionary) -> void:
	var at: Vector3 = u.pos
	var size := float(u.size)
	var air := not (u.get("leap", {}) as Dictionary).is_empty() or bool(u.get("untargetable", false))
	# enrage: the heat ring and embers grow with it
	var e := float(T.get("enrage", 0.0))
	var heat_a := 0.0
	if e > 0.02 and not air:
		heat_a = 0.25 + 0.6 * e
	_ring(_heat, at, size + 0.35, size + 0.35 + 0.25 + 0.6 * e, heat_a, ENRAGE, 3.0 + 9.0 * e)
	_embers.global_position = at + Vector3(0, 0.2, 0)
	_embers.emitting = e > 0.05 and not air
	_embers.speed_scale = 0.6 + 1.2 * e
	_embers.scale_amount_min = 0.5 + 1.5 * e
	_embers.scale_amount_max = 1.0 + 2.5 * e
	# pulse: the tell glow, then the flash
	var fx: Dictionary = T.get("fx", {})
	var pel := str(fx.get("pulse_el", ""))
	var pc: Color = EL.get(pel, EL.get(_pulse_el(T), Color.WHITE))
	var to_pulse := float(int(T.get("pulse_at", -1)) - sim.tick) / 30.0
	var since_pulse := _since(fx.get("pulse"))
	var tell := HHTierBrain.t("pulse_tell_ticks") / 30.0
	if since_pulse < 0.7:
		var k := since_pulse / 0.7
		_ring(_pulse, at, 0.0, size + 0.6 + 0.8 * k, 0.75 * (1.0 - k), pc)
	elif to_pulse >= 0.0 and to_pulse < tell and int(T.get("aggro_at", -1)) >= 0 and not air:
		_ring(_pulse, at, size - 0.1, size + 0.5, 0.35 + 0.5 * (1.0 - to_pulse / tell), pc, 18.0)
	else:
		_pulse.visible = false
	# purge: build then shockwave
	var pk := str(fx.get("purge_kind", ""))
	var purge_c: Color = EL.water if pk == "quench" else (EL.thunder if pk == "roar" else pc)
	var since_done := _since(fx.get("purge_done"))
	var to_land := float(int(fx.get("purge_at", -1)) - sim.tick) / 30.0
	if since_done < 0.8 and int(fx.get("purge_done", -1)) >= int(fx.get("purge", 0)):
		var k2 := since_done / 0.8
		var r := size + 0.5 + (HHTierBrain.t("purge_radius") + 0.5) * k2
		_ring(_purge, at, r - 0.9, r, 0.9 * (1.0 - k2), purge_c, 2.0)
	elif to_land >= 0.0 and int(fx.get("purge", -1)) >= 0 and to_land < 1.5:
		var k3 := 1.0 - to_land / maxf(0.1, HHTierBrain.t("purge_windup_ticks") / 30.0)
		_ring(_purge, at, size + 0.2, size + 0.6 + 0.6 * k3, 0.4 + 0.5 * k3, purge_c, 20.0)
	else:
		_purge.visible = false
	var act: Dictionary = T.get("act", {})
	match str(act.get("kind", "")):
		"fakeout": _draw_fakeout(u, T, act, vis)
		"sweep": _draw_sweep(u, T, act, vis)
		"siphon": _draw_siphon(u, act)
		"root": _draw_root(u, act, vis, fx)


func _pulse_el(T: Dictionary) -> String:
	return str(HHTierBrain.profile(str(T.get("kind", ""))).get("pulse", ""))


func _draw_fakeout(u: Dictionary, _T: Dictionary, act: Dictionary, vis: Dictionary) -> void:
	var phase := str(act.get("phase", ""))
	var lanes: Array = act.get("lanes", [])
	var truth := int(act.get("truth", 0))
	var variant := str(act.get("variant", "single"))
	var o := Vector2((u.pos as Vector3).x, (u.pos as Vector3).z)
	for i in lanes.size():
		var ln: Dictionary = lanes[i]
		var line: Array = ln.line
		if line.size() < HHTierBrain.ti("fk_min_len"):
			line = ln.get("reach", line)
		if line.is_empty():
			continue
		var is_true := i == truth
		if phase in ["vanish", "run"] and not is_true:
			continue                                     # beat 3: the decoys vanish
		if phase == "run":
			continue                                     # the red telegraph has taken over
		var end_w: Vector3 = _world(line[-1])
		var d := Vector2(end_w.x, end_w.z) - o
		var dl := d.length()
		var m: ShaderMaterial = _lane_mats[i]
		m.set_shader_parameter("lane_o", o)
		m.set_shader_parameter("lane_d", d / maxf(0.01, dl))
		m.set_shader_parameter("len", dl + 0.9)
		m.set_shader_parameter("half_w", 1.55)
		var chev := 0.0
		var dir := 1.0
		if phase in ["chevrons", "vanish"]:
			if variant == "single":
				chev = 1.0 if is_true else 0.0
			else:
				chev = 1.0
				dir = -1.0 if is_true else 1.0           # decoys march out; the true lane points inward
		m.set_shader_parameter("chev", chev)
		m.set_shader_parameter("dir", dir)
		m.set_shader_parameter("red", 1.0 if phase == "vanish" else 0.0)
		m.set_shader_parameter("alpha", 1.0)
		for h in ln.lane:
			_tile(h, m)
	# the body tell: an orb and a light on the true lane's side
	if phase in ["chevrons", "vanish"]:
		var k := int(act.get("tell", 0))
		var f := float(u.facing)
		var fwd := Vector3(sin(f), 0, cos(f))
		var left := Vector3(cos(f), 0, -sin(f))
		var side := left * float(k) * (float(u.size) + 0.3) + fwd * (1.2 if k == 0 else 0.4)
		var p: Vector3 = (u.pos as Vector3) + side + Vector3(0, 2.3 + 0.15 * sin(_t * 9.0), 0)
		_orb.global_position = p
		_orb_light.global_position = p
		_orb_light.light_energy = 3.0 + 1.5 * sin(_t * 12.0)
		vis.orb = true


func _draw_sweep(u: Dictionary, _T: Dictionary, act: Dictionary, vis: Dictionary) -> void:
	var phase := str(act.get("phase", ""))
	if phase == "walk":
		return
	var at: Vector3 = u.pos
	var size := float(u.size)
	var reach := size + HHTierBrain.t("sw_reach")
	var el := str(act.get("el", "dark"))
	var c: Color = EL.get(el, RED)
	var m: ShaderMaterial = _sweep_ring.material_override
	m.set_shader_parameter("mode", 1)
	_ring(_sweep_ring, at, reach - 0.8, reach + 0.2, 0.85, RED)
	vis.sweep = true
	for h in act.get("safe", []):
		_tile(h, _safe_mat, LIFT + 0.004)
	var start := int(act.get("start", -1))
	if start < 0:
		return
	var r := float(sim.tick - start)
	if phase == "wind":
		r = 0.0
	var ang := HHTierBrain.sweep_angle(act, r)
	var dirv := Vector3(sin(ang), 0, cos(ang))
	var length := reach - size + 0.5
	var width := 1.1 if el != "dark" and el != "wind" else 2.6
	var mid_p := at + dirv * (size + length * 0.5) + Vector3(0, 0.55, 0)
	var basis := Basis(Vector3.UP, ang).scaled(Vector3(width, 1.0, length))
	_beam.global_transform = Transform3D(basis, mid_p)
	var bm: ShaderMaterial = _beam.material_override
	bm.set_shader_parameter("col", c)
	bm.set_shader_parameter("mode", 1 if width > 2.0 else 0)
	bm.set_shader_parameter("alpha", 0.45 if phase == "wind" else 1.0)
	vis.beam = true


func _draw_siphon(u: Dictionary, act: Dictionary) -> void:
	var el := str(act.get("el", "fire"))
	_cluster_mat.set_shader_parameter("col", EL.get(el, RED))
	for h in act.get("cluster", []):
		if sim.charge.intensity(h, el) > 0:
			_tile(h, _cluster_mat, LIFT + 0.002)
	var path: Array = act.get("path", [])
	if path.is_empty():
		return
	var g: Vector3 = _world(act.get("goal", u.hex))
	_path_mat.set_shader_parameter("lane_o", Vector2(g.x, g.z))
	for h in path:
		if HHHex.distance(h, u.hex) > int(u.size):
			_tile(h, _path_mat, LIFT + 0.006)


func _draw_root(u: Dictionary, act: Dictionary, vis: Dictionary, fx: Dictionary) -> void:
	var phase := str(act.get("phase", ""))
	if phase == "walk":
		return
	vis.root = true
	var at: Vector3 = u.pos
	var size := float(u.size)
	var stun := phase == "stun"
	var c := STUN if stun else ROOT
	_ring(_root_ring, at, size - 0.2, size + 0.9, 0.55, c, 6.0 if stun else 2.0)
	_shaft.visible = not stun
	_shaft.global_position = at + Vector3(0, 4.5, 0)
	var grow := clampf(_since(fx.get("root")) * 2.0, 0.0, 1.0)
	for i in _roots.size():
		var mi: MeshInstance3D = _roots[i]
		var a := TAU * float(i) / float(_roots.size()) + 0.17 * float(i % 3)
		var rr := size + 0.35 + 0.25 * float(i % 2)
		var base := at + Vector3(sin(a) * rr, 0, cos(a) * rr)
		base.y = sim.arena.height_at(base.x, base.z)
		var tilt := (0.25 if not stun else 1.05) + 0.05 * sin(_t * 3.0 + float(i))
		var out := Vector3(sin(a), 0, cos(a))
		var basis := Basis(out.cross(Vector3.UP).normalized(), -tilt)
		var h := (0.9 + 0.5 * float(i % 3) * 0.5) * grow * (0.6 if stun else 1.0)
		mi.global_transform = Transform3D(basis.scaled(Vector3(1, maxf(0.05, h), 1)), base + basis * Vector3(0, 0.7 * maxf(0.05, h), 0))
		(mi.material_override as StandardMaterial3D).albedo_color = c
		mi.visible = true
