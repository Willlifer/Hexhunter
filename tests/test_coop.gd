extends RefCounted
## Lane S (H53, H875-): co-op in the sim. Up to four hunters fanned out from
## one spawn, monster HP scaled to the party, downed and revive, the fight lost
## only when nobody stands, aggro on the nearest standing hunter with a threat
## bonus for the last one that hit, no friendly fire, determinism with four.

const BIOMES := { "pond": "swampfang", "caldera": "colambros", "cave": "rimeslithe", "glade": "spirewalker" }
const BRAINS := { "swampfang": "res://src/monster/swampfang.gd", "colambros": "res://src/monster/colambros.gd",
	"rimeslithe": "res://src/monster/rimeslithe.gd", "spirewalker": "res://src/monster/spirewalker.gd" }


## The biome arena the game plays (registry path: generator + authored rows).
static func biome_arena(id: String) -> HHArena:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://arenas/%s.json" % id))
	var gen: Dictionary = d.gen
	var ar: HHArena = HHArenaGens.arena(str(gen.id), gen.params)
	if ar.authored.is_empty():
		ar.authored = Array(d.get("authored", ar.spawns.get("authored", [])))
	return ar


## A fight the way HHFight builds one: hunters first on the arena's spawn, then the biome's monster and brain.
static func fight(arena: HHArena, seed: int, hunters: Array, monster: String = "") -> HHSim:
	var s := HHSim.new(arena, seed)
	for h in hunters:
		s.add_player(str(h.id), arena.spawns.player[0], str(h.get("element", "fire")), str(h.get("backup", "water")), str(h.get("weapon", "lance")))
	if monster != "":
		var brain: Object = load(BRAINS[monster]).new()
		var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
		var m := s.add_monster(monster, arena.spawns.monster, HHTune.value("monster_hp"), 2, allowed)
		s.brains[monster] = brain
		if brain.has_method("setup"):
			brain.setup(s, m)
	return s


func _flat(n: int) -> HHSim:
	var a := HHArena.round_flat(1, 25.0, 0.0)
	var s := HHSim.new(a, 1)
	for i in n:
		s.add_player("p%d" % (i + 1), Vector2i(0, 6))
	return s


func _types(events: Array) -> Array:
	return events.map(func(e): return str(e.type))


# ------------------------------------------------------------------ spawns

func test_four_spawn_apart_on_every_biome(c: HHSelfTest.HHCheck) -> void:
	for biome in BIOMES:
		var a := biome_arena(biome)
		var s := fight(a, 1, [{ "id": "p1" }, { "id": "p2" }, { "id": "p3" }, { "id": "p4" }], BIOMES[biome])
		var ps := s.players()
		c.eq(ps.size(), 4, "%s: four hunters" % biome)
		var spawn: Vector2i = a.spawns.player[0]
		c.eq(ps[0].hex, spawn, "%s: p1 stands on the arena spawn" % biome)
		var mon: Vector3 = a.stand(a.spawns.monster)
		for i in ps.size():
			var p: Dictionary = ps[i]
			c.ok(a.walkable(p.hex) and a.kind(p.hex) in HHSim.SPAWN_KINDS, "%s %s: plain walkable ground (%s)" % [biome, p.id, a.kind(p.hex)])
			c.ok(not a.path(spawn, p.hex, {}).is_empty() or p.hex == spawn, "%s %s: reachable from the spawn" % [biome, p.id])
			c.ok(HHHex.distance(spawn, p.hex) <= 6, "%s %s: near the spawn (%d)" % [biome, p.id, HHHex.distance(spawn, p.hex)])
			if i > 0:
				var near := 1 << 30
				for j in ps.size():
					if j != i:
						near = mini(near, HHHex.distance(p.hex, ps[j].hex))
				c.ok(near >= 2 and near <= 3, "%s %s: 2-3 hexes from its nearest hunter (%d)" % [biome, p.id, near])
			var to := mon - (p.pos as Vector3)
			var fwd := Vector2(sin(float(p.facing)), cos(float(p.facing)))
			c.ok(fwd.dot(Vector2(to.x, to.z).normalized()) > 0.99, "%s %s: faces the monster" % [biome, p.id])
			for j in range(i + 1, ps.size()):
				var dd := HHHex.distance(p.hex, ps[j].hex)
				c.ok(dd >= int(HHTune.value("party_spawn_min")), "%s: %s and %s %d apart" % [biome, p.id, ps[j].id, dd])


func test_spawn_is_deterministic_and_skips_charge(c: HHSelfTest.HHCheck) -> void:
	var a := _flat(4)
	var b := _flat(4)
	c.eq(a.players().map(func(p): return p.hex), b.players().map(func(p): return p.hex), "same arena = same seats")
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6))
	var first_free := s.party_spawn(Vector2i(0, 6))
	s.paint([first_free], "fire", "env", 2)
	var p2 := s.add_player("p2", Vector2i(0, 6))
	c.ok(p2.hex != first_free, "a charged hex is never a seat")
	c.ok(s.charge.at(p2.hex).is_empty(), "p2 stands on clean ground")


func test_hunters_pass_through_each_other(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(2)
	var p1 := s.unit("p1")
	var p2 := s.unit("p2")
	var goal: Vector2i = p2.hex
	var b := s.blocked_for(p1)
	c.ok(not b.has(goal), "an ally's hex is not a wall")
	s.step({ "p1": { "move": goal, "move_pos": s.arena.stand(goal) } })
	for i in 60:
		s.step()
	c.eq(p1.hex, goal, "p1 walks onto p2's hex")


## H880: an auto-walk to the monster (target + attack) used to stall forever on
## a string-pulled corner (glade and caldera: "blocked" every tick, 0 damage
## in the 90 s bot fight). Every biome now walks into reach.
func test_auto_walk_reaches_the_monster_on_every_biome(c: HHSelfTest.HHCheck) -> void:
	for biome in BIOMES:
		var a := biome_arena(biome)
		var s := fight(a, 1, [{ "id": "p1" }, { "id": "p2", "weapon": "bow" }])
		var m := s.add_monster("m", a.spawns.monster, 20000.0, 2)
		var orders := { "p1": { "target": "m", "attack": true }, "p2": { "target": "m", "attack": true } }
		var blocked := 0
		for i in 600:
			for e in s.step(orders if i == 0 else {}):
				if e.type == "blocked":
					blocked += 1
		for id in ["p1", "p2"]:
			var p := s.unit(id)
			c.ok(HHHex.distance(p.hex, m.hex) <= int(p.reach) + int(m.size) + 1, "%s %s: walked into reach (at %s, %d away)" % [biome, id, p.hex, HHHex.distance(p.hex, m.hex)])
		c.ok(blocked < 20, "%s: no blocked storm (%d)" % [biome, blocked])


# ------------------------------------------------------------------ HP scaling

func test_party_hp_scaling(c: HHSelfTest.HHCheck) -> void:
	for n in [1, 2, 3, 4]:
		var s := _flat(n)
		var m := s.add_monster("m", Vector2i(0, -6), 20000.0, 2)
		c.near(float(m.max_hp), 20000.0 * (1.0 + 0.6 * (n - 1)), 0.01, "%d hunters: max HP" % n)
		c.near(float(m.hp), float(m.max_hp), 0.01, "%d hunters: full HP" % n)
	var t := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var m2 := t.add_monster("m", Vector2i(0, -6), 20000.0, 2)
	t.add_player("p1", Vector2i(0, 6))
	c.near(float(m2.max_hp), 20000.0, 0.01, "monster first, solo: untouched")
	m2.hp = 10000.0
	t.add_player("p2", Vector2i(0, 6))
	c.near(float(m2.max_hp), 32000.0, 0.01, "monster first, a second hunter joins: x1.6")
	c.near(float(m2.hp), 16000.0, 0.01, "HP keeps its fraction")
	t.scale_for_party()
	c.near(float(m2.max_hp), 32000.0, 0.01, "scale_for_party is idempotent")


# ------------------------------------------------------------------ downed / revive

func test_solo_still_dies(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(1)
	var p := s.unit("p1")
	c.eq(p.hex, Vector2i(0, 6), "solo hunter stands exactly on the spawn")
	s.hurt(p, 99999.0, "test")
	var ev := _types(s.events)
	c.ok("death" in ev and not "downed" in ev, "solo: death, never downed")
	c.ok(not bool(p.downed), "solo: not downed")
	s.step()
	c.eq(s.over, "dead", "solo: the hunt is lost")


func test_downed_with_an_ally_up(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(2)
	var p1 := s.unit("p1")
	s.apply_status(p1, "burn", 300)
	s.apply_status(p1, "slow", 300)
	s.events = []
	s.hurt(p1, 99999.0, "test")
	var ev := _types(s.events)
	c.ok("downed" in ev and not "death" in ev, "downed, not dead")
	c.ok(bool(p1.downed), "u.downed")
	c.ok((p1.statuses as Dictionary).is_empty(), "statuses cleared")
	c.eq(ev.count("status_end"), 2, "status_end for each cleared status")
	c.ok(not s.targetable(p1), "untargetable")
	c.ok(s.units_in([p1.hex]).filter(func(u): return u.id == "p1").is_empty(), "attacks find nothing there")
	var at: Vector2i = p1.hex
	s.step({ "p1": { "move": at + Vector2i(3, 0) } })
	for i in 30:
		s.step()
	c.eq(p1.hex, at, "a downed hunter ignores orders")
	c.eq(s.over, "", "the hunt goes on")


func _down_with_helper(s: HHSim) -> Dictionary:
	var p1 := s.unit("p1")
	var p2 := s.unit("p2")
	s.hurt(p1, 99999.0, "test")
	p2.hex = p1.hex + Vector2i(1, 0)
	p2.pos = s.arena.stand(p2.hex)
	return p1


func test_revive_after_three_seconds_adjacent(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(2)
	var p1 := _down_with_helper(s)
	var progress := 0
	var revived_at := -1
	var start := s.tick
	for i in 120:
		for e in s.step():
			if e.type == "revive_progress":
				progress += 1
			if e.type == "revived":
				revived_at = s.tick - start
				c.eq(str(e.by), "p2", "revived by p2")
		if revived_at > 0:
			break
	c.eq(revived_at, int(HHTune.value("revive_ticks")), "revived after revive_ticks (3 s)")
	c.eq(progress, 9, "revive_progress every 10 ticks")
	c.ok(not bool(p1.downed) and s.alive(p1), "standing again")
	c.near(float(p1.hp), float(p1.max_hp) * 0.3, 0.01, "back at 30% HP")
	c.ok(s.targetable(p1), "targetable again")


func test_revive_interrupted_by_damage(c: HHSelfTest.HHCheck) -> void:
	var t := _flat(2)
	var q1 := _down_with_helper(t)
	var q2 := t.unit("p2")
	for i in 50:
		t.step()
	c.near(float(q1.revive), 50.0, 0.01, "50 ticks of progress")
	t.telegraph("env", [q2.hex], 1, { "name": "test_hit", "dmg_pct": 1.0 })   # lands inside the next step, before its revive pass
	var ev2: Array = t.step()
	c.ok("revive_interrupted" in _types(ev2), "revive_interrupted emitted")
	var left := 50.0 - HHTune.value("revive_hit_setback")
	c.near(float(q1.revive), left, 0.01, "H54: a hit costs revive_hit_setback of progress, not all of it")
	var revived := -1
	for i in 120:
		for e in t.step():
			if e.type == "revived":
				revived = i + 1
		if revived > 0:
			break
	c.eq(revived, int(HHTune.value("revive_ticks") - left), "the rest of the revive after the hit")


func test_revive_decays_alone(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(2)
	var p1 := _down_with_helper(s)
	var p2 := s.unit("p2")
	for i in 40:
		s.step()
	c.near(float(p1.revive), 40.0, 0.01, "40 ticks with a helper")
	var away: Vector2i = p1.hex + Vector2i(5, 0)
	s.step({ "p2": { "move": away, "move_pos": s.arena.stand(away) } })
	for i in 40:
		s.step()
	c.ok(HHHex.distance(p2.hex, p1.hex) > 1, "p2 walked away")
	c.ok(float(p1.revive) < 40.0 and float(p1.revive) > 0.0, "progress decays (%.1f)" % float(p1.revive))
	c.ok(bool(p1.downed), "still downed")


func test_fallen_only_when_all_down(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(3)
	s.hurt(s.unit("p1"), 99999.0, "test")
	s.hurt(s.unit("p2"), 99999.0, "test")
	s.step()
	c.eq(s.over, "", "two down, one standing: the hunt goes on")
	c.ok(bool(s.unit("p1").downed) and bool(s.unit("p2").downed), "both downed")
	s.events = []
	s.hurt(s.unit("p3"), 99999.0, "test")
	c.ok("death" in _types(s.events), "the last hunter dies (nobody to revive)")
	s.step()
	c.eq(s.over, "dead", "everyone down: lost")


# ------------------------------------------------------------------ aggro

func test_aggro_last_attacker_then_nearest(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var p1 := s.add_player("p1", Vector2i(0, 3))
	var p2 := s.add_player("p2", Vector2i(0, 5))
	var m := s.add_monster("m", Vector2i(0, -1), 20000.0, 2)
	var d1 := HHHex.distance(m.hex, p1.hex)
	var d2 := HHHex.distance(m.hex, p2.hex)
	c.ok(d1 < d2 and float(d2) - HHTune.value("aggro_hit_bonus_hexes") < float(d1), "setup: p1 nearer (%d vs %d), inside the bonus" % [d1, d2])
	c.eq(str(s.monster_target(m).get("id", "")), "p1", "nearest first")
	s.strike(p2, m, 100.0, m.hex, "test")
	c.eq(str(m.aggro_id), "p2", "the hit is remembered")
	c.eq(str(s.monster_target(m).get("id", "")), "p1", "H54: the monster holds its target for aggro_commit_ticks")
	for i in int(HHTune.value("aggro_commit_ticks")):
		s.step()
	c.eq(str(s.monster_target(m).get("id", "")), "p2", "then the last attacker beats the nearest within the memory")
	for i in int(HHTune.value("aggro_memory_ticks")) + 1:
		s.step()
	c.eq(str(s.monster_target(m).get("id", "")), "p1", "after aggro_memory_ticks: nearest again")
	s.hurt(p1, 99999.0, "test")
	c.eq(str(s.monster_target(m).get("id", "")), "p2", "a downed hunter is never the target")
	for biome in BIOMES:
		var brain: Object = load(BRAINS[BIOMES[biome]]).new()
		c.eq(str(brain.call("_nearest_player", s, m).get("id", "")), "p2", "%s's brain asks monster_target" % BIOMES[biome])


func test_aggro_from_reactions_and_telegraphs(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	s.add_player("p1", Vector2i(0, 6))
	s.add_player("p2", Vector2i(0, 6))
	var m := s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	s.telegraph("p2", [m.hex], 1, { "name": "arcing shot", "dmg_pct": 1.0 })
	s.step()
	c.eq(str(m.aggro_id), "p2", "a hunter's telegraph counts as a hit")
	s.paint([m.hex], "fire", "p1", 3)
	s.paint([m.hex], "fire", "p1", 1)            # overheat
	c.eq(str(m.aggro_id), "p1", "a hunter's reaction counts as a hit")


# ------------------------------------------------------------------ friendly fire

func test_no_friendly_fire(c: HHSelfTest.HHCheck) -> void:
	var s := _flat(2)
	var p1 := s.unit("p1")
	var p2 := s.unit("p2")
	var full := float(p2.hp)
	c.eq(s.strike(p1, p2, 500.0, p2.hex, "test"), 0.0, "a blow passes through an ally")
	s.telegraph("p1", [p2.hex], 1, { "name": "arcing shot", "dmg_pct": 10.0 })
	s.step()
	s.paint([p2.hex], "fire", "p1", 3)
	s.paint([p2.hex], "fire", "p1", 1)          # overheat on p2's hex
	for i in 60:
		s.step()
	c.near(float(p2.hp), full, 0.01, "no damage from an ally's telegraph, overheat or fire ground")
	HHTune.set_value("party_friendly_fire", 1.0)
	c.ok(s.strike(p1, p2, 500.0, p2.hex, "test") > 0.0, "party_friendly_fire 1 turns it back on")
	HHTune.reset()


func test_weapons_spare_allies(c: HHSelfTest.HHCheck) -> void:
	for w in ["lance", "daggers", "bow"]:
		var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
		var p1 := s.add_player("p1", Vector2i(0, 6), "fire", "water", w)
		var p2 := s.add_player("p2", Vector2i(0, 6))
		var full := float(p2.hp)
		for k in ["q", "e", "r"]:
			p1.cooldowns[k] = 0
			s.step({ "p1": { "cast": { "skill": k, "aim": p2.hex } } })
			for i in 120:
				s.step()
		c.near(float(p2.hp), full, 0.01, "%s Q/E/R aimed at an ally: no damage" % w)


# ------------------------------------------------------------------ determinism

static func scripted_run(seed: int, ticks: int) -> HHSim:
	var a := HHArena.round_flat(seed, 25.0, 0.6)
	var s := HHSim.new(a, seed)
	var weapons := ["lance", "daggers", "bow", "lance"]
	var els := ["fire", "thunder", "ice", "water"]
	for i in 4:
		s.add_player("p%d" % (i + 1), Vector2i(0, 8), els[i], "dark", weapons[i])
	var brain := HHSwampfang.new("swampfang")
	var m := s.add_monster("swampfang", Vector2i(0, -4), 20000.0, 2)
	s.brains["swampfang"] = brain
	for t in ticks:
		var orders := {}
		for i in 4:
			var id := "p%d" % (i + 1)
			var k := (t + i * 37) % 240
			if k == 5:
				orders[id] = { "target": "swampfang", "attack": true }
			elif k == 90:
				orders[id] = { "cast": { "skill": ["q", "e", "r"][(t / 240 + i) % 3], "aim": m.hex } }
			elif k == 150:
				var h: Vector2i = m.hex + Vector2i(i - 2, 5)
				orders[id] = { "move": h, "move_pos": a.stand(h) }
			elif k == 200 and i == 1:
				orders[id] = { "potion": true }
		s.step(orders)
	return s


func test_determinism_four_hunters(c: HHSelfTest.HHCheck) -> void:
	var a := scripted_run(3, 900)
	var b := scripted_run(3, 900)
	c.eq(a.state_hash(), b.state_hash(), "two identical 4-hunter runs: same hash")
	c.ok(float(a.unit("swampfang").hp) < float(a.unit("swampfang").max_hp), "the run actually fought")
	var d := scripted_run(4, 900)
	c.ok(d.state_hash() != a.state_hash(), "a different seed differs")
