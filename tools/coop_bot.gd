extends SceneTree
## Lane S (H53): two bot hunters fight each biome's monster headless and the
## run prints outcome, damage by cause, downs / revives and who the monster
## chased. The bots are deliberately simple (attack, cast on cooldown, dodge
## a telegraph that is about to land on them, drink under 40% HP, run to a
## downed ally and stand by it); the numbers say what co-op does to the
## fight, not how well a good party plays.
##   godot --headless --path . --script res://tools/coop_bot.gd
## Env: SECONDS (90), SEED (1), BIOMES ("pond,caldera,cave,glade"), HUNTERS (2),
## WEAPONS ("lance,bow,daggers,lance").

const BIOMES := { "pond": "swampfang", "caldera": "colambros", "cave": "rimeslithe", "glade": "spirewalker" }
const ELEMENTS := [["fire", "water"], ["thunder", "ice"], ["dark", "light"], ["water", "fire"]]


func _initialize() -> void:
	_run.call_deferred()


func _env(key: String, def: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else def


func _run() -> void:
	var seconds := float(_env("SECONDS", "90"))
	var seed := int(_env("SEED", "1"))
	var n := int(_env("HUNTERS", "2"))
	var weapons := _env("WEAPONS", "lance,bow,daggers,lance").split(",")
	for biome in _env("BIOMES", "pond,caldera,cave,glade").split(","):
		_fight(biome, str(BIOMES[biome]), seed, n, weapons, int(seconds * 30.0))
	quit()


static func biome_arena(id: String) -> HHArena:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://arenas/%s.json" % id))
	var gen: Dictionary = d.gen
	var ar: HHArena = HHArenaGens.arena(str(gen.id), gen.params)
	if ar.authored.is_empty():
		ar.authored = Array(d.get("authored", ar.spawns.get("authored", [])))
	return ar


func _fight(biome: String, monster: String, seed: int, n: int, weapons: PackedStringArray, ticks: int) -> void:
	var arena := biome_arena(biome)
	var s := HHSim.new(arena, seed)
	var ids: Array = []
	for i in n:
		var id := "p%d" % (i + 1)
		ids.append(id)
		s.add_player(id, arena.spawns.player[0], ELEMENTS[i % 4][0], ELEMENTS[i % 4][1], weapons[i % weapons.size()])
	var brain: Object = load("res://src/monster/%s.gd" % monster).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var m := s.add_monster(monster, arena.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
	s.brains[monster] = brain
	if brain.has_method("setup"):
		brain.setup(s, m)
	var dmg_monster := {}
	var dmg_hunters := {}
	var dmg_by_hunter := {}
	var counts := { "downed": 0, "revived": 0, "revive_interrupted": 0, "death": 0, "potion": 0, "cast": 0 }
	var chased := {}
	var switches := 0
	var last_target := ""
	var bots := {}
	for id in ids:
		bots[id] = { "dodging": 0, "next_cast": 60 + ids.find(id) * 11, "next_rev": 0 }
	var end_tick := ticks
	for t in ticks:
		var orders := {}
		for id in ids:
			var o := _decide(s, s.unit(id), m, bots[id], ids)
			if not o.is_empty():
				orders[id] = o
		var ev := s.step(orders)
		for e in ev:
			match str(e.type):
				"hurt":
					var u := s.unit(str(e.id))
					var key := str(e.cause)
					if str(u.get("kind", "")) == "monster":
						dmg_monster[key] = float(dmg_monster.get(key, 0.0)) + float(e.amount)
					else:
						dmg_hunters[key] = float(dmg_hunters.get(key, 0.0)) + float(e.amount)
						dmg_by_hunter[e.id] = float(dmg_by_hunter.get(e.id, 0.0)) + float(e.amount)
				"downed", "revived", "revive_interrupted", "death", "potion", "cast":
					counts[str(e.type)] = int(counts[str(e.type)]) + 1
		if OS.get_environment("TRACE") != "" and s.tick % 150 == 0:
			for e in ev:
				if str(e.type) in ["blocked", "move"]:
					print("   ev ", e)
			for id in ids:
				var u := s.unit(id)
				var pr := s.arena.path_to_reach(u.hex, m.hex, int(u.reach) + int(m.size), s.blocked_for(u))
				print("   reach-path %s: %d, walkable here %s kind %s" % [id, pr.size(), s.arena.walkable(u.hex), s.arena.kind(u.hex)])
				print("   t%d %s hex %s hp %.0f target '%s' att %s path %d held %s | m hex %s targetable %s untg %s" % [s.tick, id, u.hex, float(u.hp), u.target, u.attacking, (u.path as Array).size(), s.held(u), m.hex, s.targetable(m), m.untargetable])
		var tgt := str(s.monster_target(m).get("id", ""))
		if tgt != "":
			chased[tgt] = int(chased.get(tgt, 0)) + 1
			if last_target != "" and tgt != last_target:
				switches += 1
			last_target = tgt
		if s.over != "":
			end_tick = s.tick
			break
	print("== %s vs %s, %d hunters (%s), seed %d" % [biome, monster, n, ", ".join(ids.map(func(i): return "%s %s/%s" % [i, s.unit(i).weapon, s.unit(i).element])), seed])
	print("   outcome: %s at %.1f s; monster %.0f / %.0f HP (%.0f%% left, x%.1f party HP)" % [
		s.over if s.over != "" else "timeout", end_tick / 30.0, float(m.hp), float(m.max_hp), 100.0 * float(m.hp) / float(m.max_hp), float(m.party_scale)])
	var hl: Array = []
	for id in ids:
		var u := s.unit(id)
		hl.append("%s %s %.0f HP, %d potions left, took %.0f" % [id, "DOWNED" if bool(u.downed) else ("dead" if not s.alive(u) else "up"), float(u.hp), int(u.potions), float(dmg_by_hunter.get(id, 0.0))])
	print("   hunters: ", "; ".join(hl))
	print("   events: %s" % JSON.stringify(counts))
	print("   monster chased: %s, %d target switches" % [JSON.stringify(chased), switches])
	print("   damage to the monster by cause: %s" % _fmt(dmg_monster))
	print("   damage to hunters by cause: %s" % _fmt(dmg_hunters))


static func _fmt(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return float(d[a]) > float(d[b]))
	var total := 0.0
	for k in keys:
		total += float(d[k])
	var parts: Array = []
	for k in keys:
		parts.append("%s %.0f" % [k, float(d[k])])
	return "total %.0f: %s" % [total, ", ".join(parts)]


## One bot's order this tick ({} = nothing new).
func _decide(s: HHSim, u: Dictionary, m: Dictionary, b: Dictionary, ids: Array) -> Dictionary:
	if not s.alive(u) or s.held(u):
		return {}
	# a downed ally: go and stand by it
	for id in ids:
		var d := s.unit(id)
		if id != u.id and bool(d.downed):
			if HHHex.distance(u.hex, d.hex) > 1:
				if s.tick >= int(b.next_rev):
					b.next_rev = s.tick + 15
					return { "move": d.hex, "move_pos": s.arena.stand(d.hex) }
				return {}
			if (u.path as Array).is_empty() and not bool(u.attacking):
				return {}
			return { "stop": true }
	# a telegraph about to land on me: step out
	var danger := {}
	for tg in s.telegraphs:
		if str(tg.owner) in ids or int(tg.left) > 36:
			continue
		for h in tg.hexes:
			danger[h] = true
	if danger.has(u.hex):
		if int(b.dodging) > s.tick:
			return {}
		var safe := _safe_hex(s, u, danger)
		if safe != u.hex:
			b.dodging = s.tick + 20
			return { "move": safe, "move_pos": s.arena.stand(safe) }
	if int(b.dodging) > s.tick and not (u.path as Array).is_empty():
		return {}
	# drink under 40%
	if float(u.hp) < 0.4 * float(u.max_hp) and int(u.potions) > 0 and int(u.cooldowns.get("t", 0)) <= 0 and not danger.has(u.hex):
		return { "potion": true }
	# cast on cooldown when the monster is close enough
	if s.tick >= int(b.next_cast) and s.targetable(m) and HHHex.distance(u.hex, m.hex) <= int(m.size) + 5:
		b.next_cast = s.tick + 45
		for k in ["r", "q", "e"]:
			if int(u.cooldowns[k]) <= 0:
				return { "cast": { "skill": k, "aim": s.nearest_hex_of(m, u.hex) } }
	if s.targetable(m) and (str(u.target) != m.id or not bool(u.attacking)):
		return { "target": m.id, "attack": true }
	return {}


func _safe_hex(s: HHSim, u: Dictionary, danger: Dictionary) -> Vector2i:
	var blocked := s.blocked_for(u)
	for r in range(1, 7):
		for h in s.arena.ring(u.hex, r):
			if s.arena.walkable(h) and not danger.has(h) and not blocked.has(h) and not s.arena.path(u.hex, h, blocked).is_empty():
				return h
	return u.hex
