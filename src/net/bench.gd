class_name HHNetBench
extends RefCounted
## Lane N's test bed (node-free): a host sim with a monster brain and up to
## four hunters, a matching mirror, and scripted bot orders that make a busy
## fight (attacks, casts, swaps, moves, sandbox paint so every reaction shows).
## Used by tests/test_net.gd and tools/net_*.gd. Not used by the game.
##
## Until Lane S lands multi-hunter spawns, extra hunters are added here with
## sim.add_player on walkable hexes around the arena's player spawn, and the
## monster's HP is multiplied by MONSTER_HP_MULT so a bot party cannot end a
## 60 s measurement early (Lane S owns the real party scaling, H53).

const WEAPONS := ["lance", "daggers", "bow", "lance"]
const MONSTER_HP_MULT := 8.0
const ELEMENTS := [["fire", "water"], ["thunder", "ice"], ["light", "dark"], ["wind", "fire"]]


## The party rows a session would build: [{ peer, id, name, weapon, element, backup, upgrades }].
static func party(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({ "peer": 1 if i == 0 else 100 + i, "id": "p%d" % (i + 1), "name": "bot%d" % (i + 1),
			"weapon": WEAPONS[i % 4], "element": ELEMENTS[i % 4][0], "backup": ELEMENTS[i % 4][1],
			"upgrades": { "q": [], "w": [], "e": ["daggerleap_homing"] if WEAPONS[i % 4] == "daggers" else [], "r": [] } })
	return out


static func load_arena(arena_id: String, seed: int) -> HHArena:
	if arena_id == "round" or arena_id == "":
		return HHArena.round_flat(seed)
	return HHRegistry.load_arena(arena_id, seed).arena


## The host's sim: arena, hunters, monster with its brain (as HHFight builds it).
static func host_sim(arena_id: String, monster: String, seed: int, players: Array, p_arena: HHArena = null) -> HHSim:
	var a := p_arena if p_arena != null else load_arena(arena_id, seed)
	var sim := HHSim.new(a, seed)
	sim.sandbox = true
	_hunters(sim, players)
	if monster != "":
		var allowed: Array = []
		var brain: Variant = null
		var path := "res://src/monster/%s.gd" % monster
		if ResourceLoader.exists(path):
			brain = (load(path) as GDScript).new()
			if brain.has_method("allowed_kinds"):
				allowed = brain.allowed_kinds()
		var u := sim.add_monster(monster, a.spawns.monster, HHTune.value("monster_hp") * MONSTER_HP_MULT, 2, allowed)
		if brain != null:
			sim.brains[monster] = brain
			if brain.has_method("setup"):
				brain.setup(sim, u)
	return sim


## A client's mirror: same arena and seed, same units, no brains.
static func mirror_sim(arena_id: String, monster: String, seed: int, players: Array, p_arena: HHArena = null) -> HHSim:
	var a := p_arena if p_arena != null else load_arena(arena_id, seed)
	var sim := HHSim.new(a, seed)
	_hunters(sim, players)
	if monster != "":
		sim.add_monster(monster, a.spawns.monster, HHTune.value("monster_hp") * MONSTER_HP_MULT, 2)
	return sim


static func _hunters(sim: HHSim, players: Array) -> void:
	var spawn: Vector2i = sim.arena.spawns.player[0]
	var taken := {}
	var offs := [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2)]
	for i in players.size():
		var p: Dictionary = players[i]
		var h := sim.arena.nearest_walkable(spawn, spawn + offs[i % 4], taken)
		taken[h] = true
		sim.add_player(str(p.id), h, str(p.element), str(p.backup), str(p.weapon), p.get("upgrades", {}))


## Scripted orders for one hunter at `tick` (empty most ticks).
static func bot_order(sim: HHSim, id: String, tick: int, slot: int) -> Dictionary:
	var u := sim.unit(id)
	if u.is_empty() or not sim.alive(u):
		return {}
	var ms := sim.monsters()
	var m: Dictionary = ms[0] if not ms.is_empty() else {}
	var t := tick + slot * 17
	var spawn: Vector2i = sim.arena.spawns.player[0]
	if tick == 5 + slot * 3 and not m.is_empty():
		return { "target": m.id, "attack": true, "run": true }
	if t % 450 == 200:
		var goal: Vector2i = spawn + Vector2i(3 - slot * 2, -2 + (t / 450) % 3)
		return { "move": goal, "move_pos": sim.arena.stand(goal) }
	if t % 450 == 290 and not m.is_empty():
		return { "target": m.id, "attack": true }
	if m.is_empty():
		return {}
	var aim: Vector2i = m.hex
	match t % 300:
		60: return { "cast": { "skill": "q", "aim": aim } }
		120: return { "cast": { "skill": "e", "aim": aim } }
		150: return { "swap": true }
		240: return { "cast": { "skill": "r", "aim": aim + Vector2i(1, 1) } }
	if t % 600 == 330:
		return { "potion": true }
	if t % 90 == 45:
		var els := ["fire", "water", "thunder", "ice", "wind", "light", "dark"]
		return { "paint": { "element": els[(t / 90 + slot) % els.size()], "hex": u.hex + Vector2i(1, slot % 2), "steps": 2 } }
	return {}


## Every bot hunter's orders this tick, except `skip` (the ones a remote peer drives).
static func bot_orders(sim: HHSim, tick: int, skip: Array = []) -> Dictionary:
	var out := {}
	var i := 0
	for u in sim.players():
		if not u.id in skip:
			var o := bot_order(sim, u.id, tick, i)
			if not o.is_empty():
				out[u.id] = o
		i += 1
	return out
