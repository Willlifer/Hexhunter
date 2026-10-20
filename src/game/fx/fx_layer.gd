class_name HHFxLayer
extends Node3D
## Lane FX (H700): the effects layer of HHArenaView. Each frame `sync` reads
## the sim: every live telegraph in `sim.telegraphs` gets an HHTelegraphFx
## (pooled; one per attack: same owner, name and start tick), built over its
## countdown and committed when it resolves; the hunter's wind-up builds at
## the weapon hand (HHSkillFx); monsters in a state get their standing
## effects (HHStateFx). One-shots come in through `on_event` (strike, cast,
## pierce, eruption, arrowstorm ...).
##
## Bodies are looked up by unit id: `bodies` / `player_body` when a caller
## sets them, else the parent fight's `monster_bodies` / `player_body`
## (duck-typed), so effects can follow sockets by name.

const POOL_MAX := 12              ## parked effects kept for reuse

var sim: HHSim
var arena: HHArena
var bodies := {}                  ## unit id -> body node (HHMonsterBody)
var player_body: Node3D = null
var enabled := true
var effects := {}                 ## group key -> HHTelegraphFx (live)
var pool: Array = []              ## parked HHTelegraphFx
var skill: HHSkillFx
var states := {}                  ## monster id -> HHStateFx
var made := 0                     ## effects ever built (tests: pooling)
var _tg_group := {}               ## telegraph id -> group key


func setup(p_arena: HHArena) -> void:
	arena = p_arena
	skill = HHSkillFx.new()
	skill.name = "SkillFx"
	skill.layer = self
	add_child(skill)


func body_of(id: String) -> Node:
	if bodies.has(id):
		return bodies[id]
	return null


## The group an attack's telegraphs share.
static func group_key(tg: Dictionary, tick: int) -> String:
	var pl: Dictionary = tg.get("payload", {})
	var nm := str(pl.get("name", pl.get("clip", "")))
	var start := tick - (int(tg.total) - int(tg.left))
	return "%s|%s|%d" % [str(tg.owner), nm, start]


func sync(p_sim: HHSim, player_id: String, delta: float) -> void:
	sim = p_sim
	if not enabled or sim == null:
		return
	_find_bodies()
	var seen := {}
	for tg in sim.telegraphs:
		var id := int(tg.id)
		seen[id] = true
		var key: String = _tg_group.get(id, "")
		if key == "":
			key = group_key(tg, sim.tick)
			_tg_group[id] = key
		var fx: HHTelegraphFx = effects.get(key)
		if fx == null:
			fx = _acquire()
			effects[key] = fx
			fx.begin(self, key, tg, sim.tick - (int(tg.total) - int(tg.left)))
		else:
			fx.add_member(tg)
	# resolved telegraphs: their members end (the first one commits the effect)
	for id in _tg_group.keys():
		if seen.has(id):
			continue
		var key: String = _tg_group[id]
		_tg_group.erase(id)
		var fx: HHTelegraphFx = effects.get(key)
		if fx != null:
			fx.end_member(int(id))
	for key in effects.keys():
		var fx: HHTelegraphFx = effects[key]
		var p := clampf(float(sim.tick - fx.start_tick) / maxf(1.0, float(fx.total)), 0.0, 1.0)
		fx.update(p, delta)
		if fx.finished():
			effects.erase(key)
			_release(fx)
	skill.update(sim, player_id, delta)
	for m in sim.monsters():
		var id := str(m.id)
		if not states.has(id):
			var s := HHStateFx.new()
			s.layer = self
			s.unit_id = id
			add_child(s)
			states[id] = s
		(states[id] as HHStateFx).update(sim, delta)


func on_event(e: Dictionary, p_sim: HHSim, player_id: String) -> void:
	if not enabled or skill == null:
		return
	sim = p_sim
	skill.on_event(e, p_sim, player_id)


func _find_bodies() -> void:
	var host := get_parent().get_parent() if get_parent() != null else null
	if host == null:
		return
	var mb: Variant = host.get("monster_bodies")
	if mb is Dictionary:
		for id in mb:
			bodies[id] = mb[id]
	var pb: Variant = host.get("player_body")
	if pb is Node3D:
		player_body = pb


func _acquire() -> HHTelegraphFx:
	if not pool.is_empty():
		return pool.pop_back()
	var fx := HHTelegraphFx.new()
	made += 1
	fx.name = "Tg%d" % made
	add_child(fx)
	return fx


func _release(fx: HHTelegraphFx) -> void:
	fx.release()
	if pool.size() < POOL_MAX:
		pool.append(fx)
	else:
		fx.queue_free()


## Live sprite count over every effect (tests, the perf note).
func sprite_count() -> int:
	var n := 0
	for fx in effects.values():
		n += (fx as HHTelegraphFx).add.live() + (fx as HHTelegraphFx).mix.live()
	if skill != null:
		n += skill.add.live() + skill.mix.live()
	for s in states.values():
		n += (s as HHStateFx).add.live() + (s as HHStateFx).mix.live()
	return n
