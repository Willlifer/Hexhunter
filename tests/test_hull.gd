extends RefCounted
## Lane H (H250-H259): the monster hull. Occupancy (a hunter never stands in a
## still hull; monsters never overlap), the attack click (every hex of every
## arena resolves to a legal spot: outside the hull, within the weapon's reach
## of its edge, the fewest steps away, never the centre), the move click
## (round the hull, never into it), and push-out (every displacing move ends
## with every hunter on a legal hex, two hunters on two hexes). Lane P
## (H268-H279): the push hurts (20% landed on, 5% self-caused, never on top of
## the same attack's own hit), and a monster leap splashes its element on the
## Attack Ring, contained.

const BIOMES := { "pond": "swampfang", "caldera": "colambros", "cave": "rimeslithe", "glade": "spirewalker" }
const BRAINS := { "swampfang": "res://src/monster/swampfang.gd", "colambros": "res://src/monster/colambros.gd",
	"rimeslithe": "res://src/monster/rimeslithe.gd", "spirewalker": "res://src/monster/spirewalker.gd" }
const WEAPONS := ["daggers", "lance", "bow"]


static func biome_arena(id: String) -> HHArena:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://arenas/%s.json" % id))
	var gen: Dictionary = d.gen
	var ar: HHArena = HHArenaGens.arena(str(gen.id), gen.params)
	if ar.authored.is_empty():
		ar.authored = Array(d.get("authored", ar.spawns.get("authored", [])))
	return ar


## Every arena the game plays plus the flat stand-in.
static func arenas() -> Dictionary:
	var out := { "round": HHArena.round_flat(1, 25.0, 0.6) }
	for b in BIOMES:
		out[b] = biome_arena(b)
	return out


static func place(s: HHSim, u: Dictionary, h: Vector2i) -> void:
	u.hex = h
	u.prev = h
	u.crossed = h
	u.pos = s.arena.stand(h)
	u.path = [] as Array[Vector2i]
	u.goal_pos = HHSim.NO_POS


## No hunter inside a still hull; no two monsters' hulls overlap.
static func legal_now(s: HHSim) -> String:
	for m in s.monsters():
		if not s.occupying(m):
			continue
		for p in s.players():
			if (s.alive(p) or bool(p.downed)) and (p.leap as Dictionary).is_empty() and s.in_hull(m, p.hex):
				return "t%d %s inside %s's hull at %s (centre %s)" % [s.tick, p.id, m.id, p.hex, m.hex]
	var ms := s.monsters().filter(func(o): return s.alive(o))
	for i in ms.size():
		for j in range(i + 1, ms.size()):
			if HHHex.distance(ms[i].hex, ms[j].hex) <= int(ms[i].size) + int(ms[j].size):
				return "t%d hulls of %s and %s overlap" % [s.tick, ms[i].id, ms[j].id]
	return ""


# ------------------------------------------------------------------ the hull follows size

func test_hull_and_ring_follow_size(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var big := s.add_monster("big", Vector2i(0, -6), 20000.0, 2)
	var small := s.add_monster("small", Vector2i(0, 8), 20000.0, 1)
	c.eq(s.footprint(big).size(), 19, "radius 2: a 19-hex hull")
	c.eq(s.attack_ring(big).size(), 18, "radius 2: the ring bordering it is 18 hexes (6 x 3; the spec's 24 is the radius-4 ring)")
	c.eq(s.footprint(small).size(), 7, "radius 1: a 7-hex hull")
	c.eq(s.attack_ring(small).size(), 12, "radius 1: a 12-hex Attack Ring")
	for h in s.attack_ring(big):
		c.ok(not s.in_hull(big, h) and HHHex.neighbors(h).any(func(n): return s.in_hull(big, n)), "ring hex %s borders the hull" % h)
	var p := s.add_player("p1", Vector2i(0, 0), "fire", "water", "daggers")
	place(s, p, Vector2i(0, 3))
	var b := s.blocked_for(p)
	for h in s.footprint(big):
		c.ok(b.has(h), "hull hex %s is a wall for a hunter outside" % h)
	place(s, p, big.hex + Vector2i(1, 0))
	c.ok(not s.blocked_for(p).has(big.hex), "a hunter inside a (moving) hull is not walled by it: it can walk out")


# ------------------------------------------------------------------ 5.4a occupancy

## Hunters ordered at, into and through the hull from all round it, on every
## arena: at every tick end no hunter stands in a still hull.
func test_never_in_a_still_hull(c: HHSelfTest.HHCheck) -> void:
	var all := arenas()
	for name in all:
		var a: HHArena = all[name]
		var s := HHSim.new(a, 3)
		var p1 := s.add_player("p1", a.spawns.player[0], "fire", "water", "daggers")
		var p2 := s.add_player("p2", a.spawns.player[0], "fire", "water", "lance")
		var m := s.add_monster("m", a.spawns.monster, 50000.0, 2)
		var goals: Array = s.footprint(m).filter(func(h): return a.exists(h))
		goals.append_array(s.arena.ring(m.hex, 5))
		var bad := ""
		var moved := 0
		for gi in goals.size():
			var g: Vector2i = goals[gi]
			var far: Vector2i = goals[(gi * 7 + 3) % goals.size()]
			for i in 40:
				var o := {}
				if i == 0:
					o = { "p1": { "move": g, "move_pos": a.stand(g) }, "p2": { "move": far, "move_pos": a.stand(far) } }
				s.step(o)
				p1.hp = p1.max_hp
				p2.hp = p2.max_hp
				var why := legal_now(s)
				if why != "" and bad == "":
					bad = why
			if p1.hex != a.spawns.player[0]:
				moved += 1
		c.ok(bad == "", "%s: %s" % [name, bad if bad != "" else "no hunter ever in the still hull"])
		c.ok(moved > goals.size() / 2, "%s: the hunters really moved (%d of %d legs)" % [name, moved, goals.size()])
		for h in s.footprint(m):
			c.ok(p1.hex != h and p2.hex != h, "%s: nobody ends on hull hex %s" % [name, h])


## A move click inside the hull goes to the nearest Attack Ring hex to the
## clicked point, round the hull; a click beyond the hull routes round it.
func test_move_click_routes_round_the_hull(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var m := s.add_monster("m", Vector2i(0, 0), 50000.0, 2)
	var p := s.add_player("p1", Vector2i(0, 8))
	place(s, p, Vector2i(0, 6))
	s.step({ "p1": { "move": m.hex, "move_pos": s.arena.stand(m.hex) } })
	var path: Array = p.path
	c.ok(not path.is_empty(), "a click on the centre still walks")
	c.eq(HHHex.distance(path[-1], m.hex), 3, "... to the Attack Ring, never the centre (%s)" % [path[-1]])
	var far := Vector2i(0, -6)
	place(s, p, Vector2i(0, 6))
	s.step({ "p1": { "move": far, "move_pos": s.arena.stand(far) } })
	path = p.path
	c.ok(not path.is_empty() and path[-1] == far, "a click beyond the hull keeps its goal")
	c.ok(path.all(func(h): return not s.in_hull(m, h)), "... and the route never enters the hull")
	var crossed := false
	for i in 200:
		s.step()
		crossed = crossed or s.in_hull(m, p.hex)
	c.ok(not crossed, "the walk went round, not through")
	c.eq(p.hex, far, "and arrived on the far side")


## Two monsters never overlap: a monster's walls are the other hull grown by its own size.
func test_monsters_never_overlap(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var a := s.add_monster("a", Vector2i(-6, 0), 50000.0, 2)
	var b := s.add_monster("b", Vector2i(6, 0), 50000.0, 1)
	var bl := s.blocked_for(a)
	for h in HHHex.area(b.hex, 3):
		c.ok(bl.has(h), "a may not centre on %s (its hull would touch b's)" % h)
	var bad := ""
	for leg in 6:
		s.monster_move(a, b.hex)
		s.monster_move(b, a.hex)
		for i in 160:
			s.step()
			var why := legal_now(s)
			if why != "" and bad == "":
				bad = why
	c.ok(bad == "", bad if bad != "" else "two monsters walking at each other never overlap")


# ------------------------------------------------------------------ 5.4b the attack click

## Multi-source BFS from every legal spot: steps from each hex to the nearest.
static func steps_to_legal(s: HHSim, u: Dictionary, t: Dictionary, blocked: Dictionary) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for h in s.arena.cells:
		if s.arena.walkable(h) and not blocked.has(h) and s.in_attack_range(u, t, h):
			dist[h] = 0
			queue.append(h)
	var qi := 0
	while qi < queue.size():
		var h := queue[qi]
		qi += 1
		for n in s.arena.walk_neighbors(h, blocked):
			if not dist.has(n):
				dist[n] = int(dist[h]) + 1
				queue.append(n)
	return dist


## Exhaustive: every walkable hex of every arena, every weapon. The spot is
## walkable, outside every hull, within the weapon's reach of the hull's edge
## (daggers: exactly the Attack Ring), the fewest steps away; the path to it
## is a legal walk; nothing resolves to the centre or inside the hull; NO_HEX
## only when no legal spot is reachable at all.
func test_attack_click_from_every_hex(c: HHSelfTest.HHCheck) -> void:
	var all := arenas()
	for name in all:
		var a: HHArena = all[name]
		var s := HHSim.new(a, 1)
		var m := s.add_monster("m", a.spawns.monster, 50000.0, 2)
		var p := s.add_player("p1", a.spawns.player[0])
		for w in WEAPONS:
			p.weapon = w
			p.reach = HHWeapons.reach(w)
			place(s, p, a.spawns.player[0])
			var blocked := s.blocked_for(p)
			var dist := steps_to_legal(s, p, m, blocked)
			var n := 0
			var fails := 0
			var first := ""
			for h in a.cells:
				if not a.walkable(h) or s.in_hull(m, h):
					continue
				place(s, p, h)
				var spot: Dictionary = s.attack_spot(p, m)
				var at: Vector2i = spot.hex
				var path: Array = spot.path
				var why := ""
				if at == HHSim.NO_HEX:
					if dist.has(h):
						why = "no spot though one is %d steps away" % int(dist[h])
				else:
					if not a.walkable(at) or s.in_hull(m, at) or not s.in_attack_range(p, m, at):
						why = "illegal spot %s (%d from centre)" % [at, HHHex.distance(at, m.hex)]
					elif w == "daggers" and HHHex.distance(at, m.hex) != int(m.size) + 1:
						why = "daggers off the Attack Ring at %s" % at
					elif path.size() != int(dist.get(h, -1)):
						why = "spot %d steps away, nearest is %d" % [path.size(), int(dist.get(h, -1))]
					else:
						var prev: Vector2i = h
						for st in path:
							if HHHex.distance(prev, st) != 1 or not a.walkable(st) or blocked.has(st) or s.in_hull(m, st):
								why = "bad step %s -> %s" % [prev, st]
								break
							prev = st
						if why == "" and not path.is_empty() and path[-1] != at:
							why = "path ends at %s, not the spot" % [path[-1]]
				n += 1
				if why != "":
					fails += 1
					if first == "":
						first = "%s: %s" % [h, why]
			c.ok(fails == 0, "%s %s: %d hexes, %d bad%s" % [name, w, n, fails, "" if first == "" else " (first " + first + ")"])
			c.ok(n > 200, "%s %s: the sweep covered the arena (%d hexes)" % [name, w, n])


## A hunter inside the hull of a moving monster still resolves to a spot
## outside it (the pathfinder never aims inside), and a size-1 monster works.
func test_attack_click_from_inside_and_small_hulls(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var m := s.add_monster("m", Vector2i(0, 0), 50000.0, 2)
	var p := s.add_player("p1", Vector2i(0, 8), "fire", "water", "daggers")
	for h in s.footprint(m):
		place(s, p, h)
		var spot: Dictionary = s.attack_spot(p, m)
		c.eq(HHHex.distance(spot.hex, m.hex), 3, "from inside at %s: a ring hex (%s)" % [h, spot.hex])
	var t := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var sm := t.add_monster("sm", Vector2i(0, 0), 50000.0, 1)
	var q := t.add_player("p1", Vector2i(0, 8), "fire", "water", "daggers")
	for h in t.arena.ring(sm.hex, 6):
		place(t, q, h)
		var spot: Dictionary = t.attack_spot(q, sm)
		c.eq(HHHex.distance(spot.hex, sm.hex), 2, "size 1 from %s: its 12-hex Attack Ring (%s)" % [h, spot.hex])


## The click as an order: target + attack walks to the spot and strikes from it.
func test_attack_order_walks_to_the_ring_and_hits(c: HHSelfTest.HHCheck) -> void:
	for w in WEAPONS:
		var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
		var m := s.add_monster("m", Vector2i(0, -6), 50000.0, 2)
		var p := s.add_player("p1", Vector2i(0, 8), "fire", "water", w)
		var hits := 0
		var inside := false
		for i in 300:
			for e in s.step({ "p1": { "target": "m", "attack": true } } if i == 0 else {}):
				if e.type == "strike" and str(e.get("id", "")) == "p1":
					hits += 1
			inside = inside or s.in_hull(m, p.hex)
		c.ok(hits > 0, "%s: struck (%d)" % [w, hits])
		c.ok(s.in_attack_range(p, m), "%s: standing in range of the hull's edge (%d from centre)" % [w, HHHex.distance(p.hex, m.hex)])
		c.ok(not inside, "%s: never stepped into the hull" % w)


## Two daggers hunters spread: the second takes another Attack Ring hex.
func test_party_spreads_round_the_ring(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var m := s.add_monster("m", Vector2i(0, -6), 50000.0, 2)
	var p1 := s.add_player("p1", Vector2i(0, 8), "fire", "water", "daggers")
	var p2 := s.add_player("p2", Vector2i(0, 8), "fire", "water", "daggers")
	place(s, p1, Vector2i(0, 4))
	place(s, p2, Vector2i(0, 4))
	for i in 240:
		s.step({ "p1": { "target": "m", "attack": true }, "p2": { "target": "m", "attack": true } } if i == 0 else {})
	c.ok(s.in_attack_range(p1, m) and s.in_attack_range(p2, m), "both on the ring (%s, %s)" % [p1.hex, p2.hex])
	c.ok(p1.hex != p2.hex, "on two different hexes")


# ------------------------------------------------------------------ 5.4c push-out

## Exhaustive: the monster lands with its hull on a hunter, for every hex the
## hull can stand on, every arena. The hunter ends on a legal hex: walkable,
## outside every hull, on the Attack Ring when the ring has a free hex.
func test_push_out_from_every_landing(c: HHSelfTest.HHCheck) -> void:
	var all := arenas()
	for name in all:
		var a: HHArena = all[name]
		var s := HHSim.new(a, 1)
		var m := s.add_monster("m", a.spawns.monster, 50000.0, 2)
		var p := s.add_player("p1", a.spawns.player[0])
		var n := 0
		var fails := 0
		var off_ring := 0
		var first := ""
		for centre in a.cells:
			if not a.walkable(centre):
				continue
			m.hex = centre
			m.pos = a.stand(centre)
			for h in HHHex.area(centre, 2):
				if not a.walkable(h) or (h != centre and HHHex.distance(h, centre) != 2):
					continue                                # the centre and the hull's edge
				place(s, p, h)
				p.hp = p.max_hp
				p.stagger = 0
				p.under = {}
				p.struck = {}
				var hp := float(p.hp)
				s._push_out()
				n += 1
				var why := ""
				if not a.walkable(p.hex) or s.in_hull(m, p.hex):
					why = "left at %s" % p.hex
				elif not is_equal_approx(hp - float(p.hp), float(p.max_hp) * HHTune.value("push_land_pct") / 100.0):
					why = "the push did %.1f, not push_land_pct (nobody had been under it: it came down on them)" % (hp - float(p.hp))
				elif (p.pos as Vector3) != a.stand(p.hex):
					why = "pos off its hex"
				if HHHex.distance(p.hex, centre) != 3:
					off_ring += 1
				if why != "":
					fails += 1
					if first == "":
						first = "centre %s from %s: %s" % [centre, h, why]
		c.ok(fails == 0, "%s: %d landings, %d bad%s" % [name, n, fails, "" if first == "" else " (first " + first + ")"])
		c.ok(n > 400, "%s: covered (%d)" % [name, n])
		c.ok(off_ring * 50 < n, "%s: almost always onto the Attack Ring (%d of %d further out: edge and cliff landings)" % [name, off_ring, n])


## The leap itself, stepped, with a damaging telegraph on the landing (H268's
## no-double-hit rule): the hunters that telegraph hit take no push-out damage
## on top (the push is `spared`); two hunters under it get two hexes; a downed
## hunter is pushed too; a dash under way ends.
func test_leap_onto_hunters(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var p1 := s.add_player("p1", Vector2i(0, 8))
	var p2 := s.add_player("p2", Vector2i(0, 8))
	var p3 := s.add_player("p3", Vector2i(0, 8))
	var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
	var land := Vector2i(0, 2)
	place(s, p1, land)
	place(s, p2, land)
	place(s, p3, land + Vector2i(1, 0))
	p3.hp = 0.0
	p3.downed = true
	s.begin_leap(m, land, 12, Callable())
	s.telegraph("m", HHHex.area(land, 2), 12, { "dmg_pct": 10.0 })   # the leap rule's own damage, as a brain issues it
	var ev: Array = []
	for i in 12:
		ev.append_array(s.step())
	var pushes := ev.filter(func(e): return e.type == "push_out")
	var hurts := ev.filter(func(e): return e.type == "hurt")
	c.eq(pushes.size(), 3, "three hunters slid out (downed too)")
	c.ok(hurts.size() == 2 and hurts.all(func(e): return not str(e.get("cause", "")).begins_with("push")), "only the landing telegraph hurt (%d hurts)" % hurts.size())
	c.ok(pushes.filter(func(e): return str(e.id) != "p3").all(func(e): return bool(e.get("spared", false))), "the pushes of the two it hit are spared")
	c.ok(hurts.all(func(e): return int(e.tick) <= int(pushes[0].tick)), "damage resolves on the landing tick, before the slide")
	for p in [p1, p2, p3]:
		c.eq(HHHex.distance(p.hex, m.hex), 3, "%s on the Attack Ring (%s)" % [p.id, p.hex])
	c.ok(p1.hex != p2.hex and p2.hex != p3.hex and p1.hex != p3.hex, "three different hexes")
	c.eq(int(p1.stagger), 0, "a slide is not a stagger")
	# a dash under way ends where it is slid
	var t := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var q := t.add_player("p1", Vector2i(0, 8))
	var mm := t.add_monster("m", Vector2i(0, -8), 50000.0, 2)
	place(t, q, Vector2i(0, 4))
	t.begin_leap(mm, Vector2i(0, 3), 6, Callable())
	for i in 5:
		t.step()
	t.step({ "p1": { "dash": t.arena.stand(Vector2i(0, 0)) } })
	for i in 4:
		t.step()
	c.ok(not t.in_hull(mm, q.hex), "a dash into a landing hull ends outside it (%s)" % q.hex)
	c.ok((q.dash as Dictionary).is_empty(), "the dash is over")


## A monster walking onto a standing hunter does not push mid-glide (H338:
## its moving body passes over); it pushes the tick it stops.
func test_walk_over_pushes_on_arrival(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 8))
	var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
	place(s, p, Vector2i(0, 0))
	s.monster_move(m, Vector2i(0, 1))
	var inside_moving := false
	var pushed_tick := -1
	var arrived_tick := -1
	var ev: Array = []
	for i in 400:
		for e in s.step():
			ev.append(e)
			if e.type == "push_out":
				pushed_tick = s.tick
			if e.type == "arrive" and str(e.id) == "m":
				arrived_tick = s.tick
		if not s.stationary(m) and s.in_hull(m, p.hex):
			inside_moving = true
		if arrived_tick > 0:
			break
	c.ok(inside_moving, "the moving body passed over the hunter")
	c.eq(pushed_tick, arrived_tick, "pushed on the arrival tick")
	c.eq(HHHex.distance(p.hex, m.hex), 3, "onto the Attack Ring")
	# H268: it walked onto a hunter standing still: the monster arrived on it, 20%
	var push: Array = ev.filter(func(e): return e.type == "push_out")
	var hurts: Array = ev.filter(func(e): return e.type == "hurt" and str(e.id) == "p1")
	c.ok(push.size() == 1 and str(push[0].get("cause", "")) == "land", "a walk ending on a standing hunter is 'land' (%s)" % [push])
	c.ok(hurts.size() == 1 and str(hurts[0].cause) == "push_land", "one hurt, push_land")
	if hurts.size() == 1:
		c.near(float(hurts[0].amount), float(p.max_hp) * HHTune.value("push_land_pct") / 100.0, 0.01, "20% of max HP")
	c.ok(int(p.stagger) > 0, "a landed-on push staggers (push_land_stagger)")
	c.ok(ev.any(func(e): return e.type == "interrupted" and str(e.id) == "p1" and str(e.cause) == "push_land"), "a monster blow: it interrupts (H58)")


## Every monster brain, its own biome, two hunters (one standing still as a
## target for leaps and charges, one attacking): over a long fight no hunter
## is ever left in a still hull, and the displacing moves that land on a
## hunter push it. Reports which moves pushed.
func test_every_monster_pushes_out(c: HHSelfTest.HHCheck) -> void:
	for biome in BIOMES:
		var a := biome_arena(biome)
		var mon: String = BIOMES[biome]
		var s := HHSim.new(a, 2)
		s.add_player("p1", a.spawns.player[0], "fire", "water", "lance")
		s.add_player("p2", a.spawns.player[0], "thunder", "ice", "daggers")
		var brain: Object = load(BRAINS[mon]).new()
		var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
		var m := s.add_monster(mon, a.spawns.monster, 2000000.0, 2, allowed)
		s.brains[mon] = brain
		if brain.has_method("setup"):
			brain.setup(s, m)
		s.hurt(m, 10.0, "test")
		var bad := ""
		var pushes := 0
		var last_attack := ""
		var by := {}
		for i in 4500:
			var o := {}
			if i % 90 == 0:
				o["p2"] = { "target": mon, "attack": true }
			for e in s.step(o):
				if e.type == "telegraph" and str(e.get("owner", e.get("id", ""))) == mon:
					last_attack = str(e.get("name", ""))
				if e.type == "push_out":
					pushes += 1
					by[last_attack] = int(by.get(last_attack, 0)) + 1
			for id in ["p1", "p2"]:
				var u := s.unit(id)
				u.hp = u.max_hp
				u.downed = false
			var why := legal_now(s)
			if why != "" and bad == "":
				bad = why
		c.ok(bad == "", "%s: %s" % [mon, bad if bad != "" else "never a hunter in a still hull over 150 s"])
		print("    [hull] %s: %d push-outs, after %s" % [mon, pushes, JSON.stringify(by)])


func test_deterministic(c: HHSelfTest.HHCheck) -> void:
	var hashes: Array = []
	for run in 2:
		var a := biome_arena("glade")
		var s := HHSim.new(a, 4)
		s.add_player("p1", a.spawns.player[0], "fire", "water", "daggers")
		s.add_player("p2", a.spawns.player[0], "fire", "water", "daggers")
		var brain: Object = load(BRAINS["spirewalker"]).new()
		var m := s.add_monster("spirewalker", a.spawns.monster, 2000000.0, 2, brain.allowed_kinds())
		s.brains["spirewalker"] = brain
		if brain.has_method("setup"):
			brain.setup(s, m)
		for i in 1500:
			s.step({ "p1": { "target": "spirewalker", "attack": true }, "p2": { "target": "spirewalker", "attack": true } } if i % 60 == 0 else {})
		hashes.append(s.state_hash())
	c.eq(hashes[0], hashes[1], "same seed, same orders: same hash with hull rules")


# ------------------------------------------------------------------ each monster's displacing moves

## A biome fight with the brain wired, woken, at a decision point (standing,
## not busy). p1 (lance) and p2 (daggers) stand where the test puts them.
static func brain_fight(biome: String, seed: int) -> Array:
	var a := biome_arena(biome)
	var mon: String = BIOMES[biome]
	var s := HHSim.new(a, seed)
	var p1 := s.add_player("p1", a.spawns.player[0], "fire", "water", "lance")
	var p2 := s.add_player("p2", a.spawns.player[0], "thunder", "ice", "daggers")
	var brain: Object = load(BRAINS[mon]).new()
	var allowed: Array = brain.allowed_kinds() if brain.has_method("allowed_kinds") else []
	var m := s.add_monster(mon, a.spawns.monster, 2000000.0, 2, allowed)
	s.brains[mon] = brain
	if brain.has_method("setup"):
		brain.setup(s, m)
	s.hurt(m, 10.0, "test")
	for i in 600:
		s.step()
		p1.hp = p1.max_hp
		p2.hp = p2.max_hp
		if i > 30 and s.stationary(m) and s.tick >= int(brain.get("busy_until")) and str(brain.get("mode")) in ["idle", "attack"]:
			break
	return [s, brain, m, p1, p2]


## A walkable hex `d` from the monster's centre the hull could land on.
static func spot_at(s: HHSim, m: Dictionary, d: int) -> Vector2i:
	var hs: Array = s.arena.ring(m.hex, d).filter(func(h): return s.arena.walkable(h) and HHHex.area(h, 2).all(func(f): return s.arena.walkable(f)))
	hs.sort()
	return hs[0] if not hs.is_empty() else Vector2i(-9999, -9999)


## Steps `ticks`, keeping the hunters up; returns [events, first bad state].
static func run_checked(s: HHSim, ticks: int) -> Array:
	var ev: Array = []
	var bad := ""
	for i in ticks:
		ev.append_array(s.step())
		for p in s.players():
			p.hp = p.max_hp
		var why := legal_now(s)
		if why != "" and bad == "":
			bad = why
	return [ev, bad]


func test_colambros_leap_pushes_out(c: HHSelfTest.HHCheck) -> void:
	var r := brain_fight("caldera", 5)
	var s: HHSim = r[0]
	var brain: Object = r[1]
	var m: Dictionary = r[2]
	var p1: Dictionary = r[3]
	var p2: Dictionary = r[4]
	var at := spot_at(s, m, 6)
	place(s, p1, at)
	place(s, p2, at + Vector2i(1, 0) if s.arena.walkable(at + Vector2i(1, 0)) else at)
	c.ok(bool(brain.call("_leap", s, m, p1)), "the leap started")
	var out: Array = run_checked(s, 150)
	var ev: Array = out[0]
	c.ok(str(out[1]) == "", "colambros leap: %s" % (out[1] if str(out[1]) != "" else "nobody left inside"))
	var landed := ev.filter(func(e): return e.type == "land" and str(e.id) == str(m.id))
	var pushed := ev.filter(func(e): return e.type == "push_out")
	c.ok(not landed.is_empty(), "it landed")
	c.ok(pushed.size() >= 1 and int(pushed[0].tick) == int(landed[0].tick), "pushed on the landing tick (%d pushes)" % pushed.size())
	_check_leap_landing(c, s, m, ev, landed, "leap_stomp", "fire", [p1, p2])
	for p in [p1, p2]:
		c.ok(s.arena.walkable(p.hex) and not s.in_hull(m, p.hex), "%s on a legal hex (%s)" % [p.id, p.hex])
	if pushed.size() >= 2:
		c.ok(pushed[0].to != pushed[1].to, "two hunters, two hexes")


func test_spirewalker_squash_pushes_out(c: HHSelfTest.HHCheck) -> void:
	var r := brain_fight("glade", 5)
	var s: HHSim = r[0]
	var brain: Object = r[1]
	var m: Dictionary = r[2]
	var p1: Dictionary = r[3]
	var p2: Dictionary = r[4]
	var at := spot_at(s, m, 6)
	place(s, p1, at)
	place(s, p2, at)
	brain.call("_squash", s, m, p1)
	var out: Array = run_checked(s, 150)
	var ev: Array = out[0]
	c.ok(str(out[1]) == "", "spirewalker squash: %s" % (out[1] if str(out[1]) != "" else "nobody left inside"))
	var pushed := ev.filter(func(e): return e.type == "push_out")
	var landed := ev.filter(func(e): return e.type == "land" and str(e.id) == str(m.id))
	c.ok(not landed.is_empty(), "it landed")
	c.ok(pushed.size() >= 2, "both hunters under the squash slid out (%d)" % pushed.size())
	_check_leap_landing(c, s, m, ev, landed, "leaping_squash", "thunder", [p1, p2])
	c.ok(p1.hex != p2.hex, "two hunters, two hexes (%s, %s)" % [p1.hex, p2.hex])


func test_rimeslithe_shoulder_charge_pushes_out(c: HHSelfTest.HHCheck) -> void:
	# a fresh fight per bearing until the line lets the body drive (cave walls cut some)
	var r: Array = []
	var s: HHSim
	var brain: Object
	var m: Dictionary
	var p1: Dictionary
	var p2: Dictionary
	var goal := Vector2i(-9999, -9999)
	for k in 6:
		r = brain_fight("cave", 5)
		s = r[0]
		brain = r[1]
		m = r[2]
		p1 = r[3]
		p2 = r[4]
		var hs: Array = s.arena.ring(m.hex, 5).filter(func(h): return s.arena.walkable(h))
		hs.sort()
		place(s, p1, hs[(k * hs.size()) / 6])
		brain.call("_shoulder_charge", s, m, p1)
		goal = brain.get("charge_goal")
		if goal.x != -9999:
			break
	c.ok(goal.x != -9999, "the charge drives somewhere (%s)" % goal)
	place(s, p2, goal)                                   # a hunter standing where the drive ends
	var out: Array = run_checked(s, 120)
	var ev: Array = out[0]
	c.ok(str(out[1]) == "", "rimeslithe charge: %s" % (out[1] if str(out[1]) != "" else "nobody left inside"))
	c.ok(ev.any(func(e): return e.type == "push_out" and str(e.id) == "p2"), "the hunter at the end of the drive slid out")
	c.ok(not s.in_hull(m, p2.hex) and s.arena.walkable(p2.hex), "p2 on a legal hex (%s)" % p2.hex)


func test_swampfang_surface_pushes_out(c: HHSelfTest.HHCheck) -> void:
	var r := brain_fight("pond", 5)
	var s: HHSim = r[0]
	var brain: Object = r[1]
	var m: Dictionary = r[2]
	var p1: Dictionary = r[3]
	var p2: Dictionary = r[4]
	brain.call("_dive", s, m)
	brain.call("_start_swim", s, m, p1)
	var surf: Vector2i = brain.get("surface_hex")
	var under: Array = HHHex.area(surf, 2).filter(func(h): return s.arena.walkable(h))
	under.sort()
	c.ok(not under.is_empty(), "a walkable hex (a pad, the shore) under the surfacing hull")
	if under.is_empty():
		return
	var ev: Array = []
	var bad := ""
	for i in 400:
		if bool(m.untargetable):                         # wading in over the swimmer, wherever it is
			var mp: Array = m.path
			var near: Array = HHHex.area(m.hex, 2).filter(func(h): return s.arena.walkable(h) 				and mp.slice(0, 2).all(func(n): return HHHex.distance(n, h) <= 2))
			near.sort()
			if not near.is_empty() and p2.hex != near[0]:
				place(s, p2, near[0])
		ev.append_array(s.step())
		for p in s.players():
			p.hp = p.max_hp
		var why := legal_now(s)
		if why != "" and bad == "":
			bad = why
		if ev.any(func(e): return e.type == "push_out"):
			break
	c.ok(bad == "", "swampfang surfacing: %s" % (bad if bad != "" else "nobody left inside"))
	c.ok(ev.any(func(e): return e.type == "push_out" and str(e.id) == "p2"), "the hunter on the pad it surfaced under slid out")
	c.ok(not s.in_hull(m, p2.hex), "p2 outside the hull (%s)" % p2.hex)


# ------------------------------------------------------------------ push-out hurts, leaps splash (Lane P, H268-H279)

## H268/H269 on a real brain's leap: the landing telegraph deals nothing itself;
## every hunter it landed on takes push_land_pct as `push_land` on the landing
## tick; the Attack Ring round the landing gets the monster's element on its
## open hexes, contained (no detonation sourced by the monster that tick).
static func _check_leap_landing(c: HHSelfTest.HHCheck, s: HHSim, m: Dictionary, ev: Array, landed: Array, clip: String, element: String, ps: Array) -> void:
	if landed.is_empty():
		return
	var lt := int(landed[0].tick)
	c.ok(not ev.any(func(e): return e.type == "hurt" and str(e.get("cause", "")) == clip), "%s: the landing telegraph itself deals nothing" % clip)
	var pushed: Array = ev.filter(func(e): return e.type == "push_out" and int(e.tick) == lt)
	var hits: Array = ev.filter(func(e): return e.type == "hurt" and str(e.get("cause", "")) == "push_land" and int(e.tick) == lt)
	c.ok(pushed.size() >= 1 and hits.size() == pushed.size(), "%s: each hunter it landed on took push_land (%d pushed, %d hurt)" % [clip, pushed.size(), hits.size()])
	var want := HHTune.value("player_hp") * HHTune.value("push_land_pct") / 100.0
	c.ok(hits.all(func(e): return is_equal_approx(float(e.amount), want)), "%s: 20%% of max HP each (%s)" % [clip, hits.map(func(e): return int(e.amount))])
	var splash: Array = ev.filter(func(e): return e.type == "paint" and bool(e.get("splash", false)) and int(e.tick) == lt)
	c.eq(splash.size(), 1, "%s: one splash on landing" % clip)
	if splash.size() == 1:
		var sp: Dictionary = splash[0]
		c.eq(str(sp.element), element, "%s: the splash is %s" % [clip, element])
		c.eq(str(sp.id), str(m.id), "%s: laid by the monster" % clip)
		c.ok(bool(sp.get("contained", false)), "%s: marked contained" % clip)
		c.ok(not (sp.hexes as Array).is_empty() and (sp.hexes as Array).all(func(h): return HHHex.distance(h, m.hex) == int(m.size) + 1), "%s: on the Attack Ring only (%d hexes)" % [clip, (sp.hexes as Array).size()])
	c.ok(not ev.any(func(e): return e.type == "detonate" and str(e.get("source", "")) == str(m.id) and int(e.tick) == lt), "%s: the splash set nothing off" % clip)


static func _under_case() -> Array:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 8))
	var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
	place(s, m, Vector2i(0, 0))
	m.path = [Vector2i(0, 1)] as Array[Vector2i]        # gliding: not occupying
	place(s, p, Vector2i(1, 1))
	return [s, p, m]


## H268, H281: a monster that arrives on a hunter is always "land" (20%,
## staggers), whether the hunter stood, walked away or walked into it. The
## author's "you caused it" (5%) is a hunter's own leap or dash aimed into a
## body (test_own_leap_and_dash_bump). The slide happens either way.
func test_push_damage_cause(c: HHSelfTest.HHCheck) -> void:
	for case in ["standing", "away", "into"]:
		var r := _under_case()
		var s: HHSim = r[0]
		var p: Dictionary = r[1]
		var m: Dictionary = r[2]
		c.ok(s.in_hull(m, p.hex) and not s.occupying(m), "%s: under a moving hull" % case)
		if case == "into":
			p.path = [Vector2i(0, 0)] as Array[Vector2i]
		elif case == "away":
			p.path = [Vector2i(3, 4)] as Array[Vector2i]
		c.eq(s._moving_toward(p, m), case == "into", "%s: moving toward it" % case)
		s._track_under()
		c.eq(str((p.under as Dictionary).get("by", "")), "m", "%s: noted under m" % case)
		m.path = [] as Array[Vector2i]                   # it stops on the hunter
		s.events = []
		var hp := float(p.hp)
		s._push_out()
		var want := "land"                               # H281 (push_walk_into_is_self 0)
		var push: Array = s.events.filter(func(e): return e.type == "push_out")
		c.ok(push.size() == 1 and str(push[0].cause) == want, "%s: cause %s" % [case, want])
		c.near(hp - float(p.hp), float(p.max_hp) * HHTune.value("push_%s_pct" % want) / 100.0, 0.01, "%s: push_%s_pct of max HP" % [case, want])
		c.ok(s.events.any(func(e): return e.type == "hurt" and str(e.cause) == "push_" + want), "%s: hurt cause push_%s" % [case, want])
		c.eq(int(p.stagger) > 0, want == "land", "%s: staggers only when landed on" % case)
		c.ok(not s.in_hull(m, p.hex), "%s: slid out" % case)
		c.ok((p.under as Dictionary).is_empty(), "%s: under cleared" % case)


## H272: the push is a monster blow through hurt(): dash i-frames dodge it,
## immunity skips it, a charging lance's super armour cuts it (no stagger, no
## interrupt). The slide happens in every case.
func test_push_damage_through_hurt(c: HHSelfTest.HHCheck) -> void:
	for case in ["iframes", "immune", "braced"]:
		var r := _under_case()
		var s: HHSim = r[0]
		var p: Dictionary = r[1]
		var m: Dictionary = r[2]
		m.path = [] as Array[Vector2i]
		match case:
			"iframes": p.dash_iframes = 3
			"immune": p.immune = 3
			"braced":
				p.weapon = "lance"
				p.charging = { "skill": "q", "ticks": 5, "level": 1, "aim": p.hex }
		s.events = []
		var hp := float(p.hp)
		s._push_out()
		c.ok(not s.in_hull(m, p.hex), "%s: slid out" % case)
		match case:
			"iframes":
				c.eq(float(p.hp), hp, "i-frames: no damage")
				c.ok(s.events.any(func(e): return e.type == "dodge" and str(e.cause) == "push_land"), "i-frames: a dodge")
			"immune":
				c.eq(float(p.hp), hp, "immune: no damage")
				c.ok(s.events.any(func(e): return e.type == "immune"), "immune: skipped")
			"braced":
				c.near(hp - float(p.hp), float(p.max_hp) * HHTune.value("push_land_pct") / 100.0 * (1.0 - HHTune.value("lance_charge_guard")), 0.01, "braced: cut by lance_charge_guard")
				c.eq(int(p.stagger), 0, "braced: no stagger")
				c.ok(not s.events.any(func(e): return e.type == "interrupted"), "braced: no interrupt")


## H268, H277: one attack, one blow. A landing telegraph that hurt a hunter
## spares its push (test_leap_onto_hunters); the other way round, a drive that
## ends on a hunter hurts it by the push and the same attack's line, resolving
## later, spares it. A telegraph issued after the push still lands.
func test_push_no_double_hit(c: HHSelfTest.HHCheck) -> void:
	var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
	var p := s.add_player("p1", Vector2i(0, 8))
	var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
	place(s, p, Vector2i(0, 0))
	s.telegraph("m", HHHex.area(Vector2i(0, 0), 5), 200, { "dmg_pct": 20.0, "name": "shoulder_charge" })
	s.monster_move(m, Vector2i(0, 1))
	var ev: Array = []
	for i in 210:
		ev.append_array(s.step())
		if s.tick == 160:
			s.telegraph("m", HHHex.area(p.hex, 1), 30, { "dmg_pct": 10.0, "name": "bite" })
	var hurts: Array = ev.filter(func(e): return e.type == "hurt" and str(e.id) == "p1")
	var causes: Array = hurts.map(func(e): return str(e.cause))
	c.ok(causes.has("push_land"), "the drive's push hurt (%s)" % [causes])
	c.ok(not causes.has("shoulder_charge"), "the same attack's line, resolving after the push, spared it")
	c.ok(causes.has("bite"), "a later attack still lands")
	c.ok(ev.any(func(e): return e.type == "telegraph_end" and str(e.name) == "shoulder_charge"), "the line did resolve")


## H269, H274: the splash paints the monster's element on the open Attack Ring
## hexes, contained: a charged hex, a fuse and a fire-3 hex on the ring are
## left exactly as they were (no douse, no fuse set off, no eruption), no
## detonation, overheat or reaction anywhere, the hull itself unpainted.
## Thunder (Spirewalker) arms fuses on open ground and sets nothing off.
func test_leap_splash_contained(c: HHSelfTest.HHCheck) -> void:
	for el in ["fire", "thunder"]:
		var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
		var p := s.add_player("p1", Vector2i(0, 8), "water", "fire", "lance")
		var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
		var land := Vector2i(0, 2)
		var ring: Array = s.arena.ring(land, 3)
		ring.sort()
		var wet: Vector2i = ring[0]
		var fuse: Vector2i = ring[4]
		var hot: Vector2i = ring[8]
		s.charge.apply([wet], "water", "p1", 2)
		s.charge.apply([fuse], "thunder", "p1", 1)
		s.charge.apply([hot], "fire", "p1", 3)
		var before := { wet: s.charge.at(wet).duplicate(), fuse: s.charge.at(fuse).duplicate(), hot: s.charge.at(hot).duplicate() }
		s.begin_leap(m, land, 6, Callable())
		m.leap["splash"] = el
		var ev: Array = []
		for i in 8:
			ev.append_array(s.step())
		c.ok(ev.any(func(e): return e.type == "land" and str(e.id) == "m"), "%s: landed" % el)
		var splash: Array = ev.filter(func(e): return e.type == "paint" and bool(e.get("splash", false)))
		c.eq(splash.size(), 1, "%s: one splash" % el)
		for h in [wet, fuse, hot]:
			var now: Dictionary = s.charge.at(h)
			c.ok(int(now.h) == int(before[h].h) and int(now.v) == int(before[h].v) and str(now.marker) == str(before[h].marker), "%s: %s left as it was" % [el, h])
			if not splash.is_empty():
				c.ok(not (splash[0].hexes as Array).has(h), "%s: %s not in the splash" % [el, h])
		var open := 0
		for h in ring:
			if h in [wet, fuse, hot] or not s.charge.can_hold(h):
				continue
			open += 1
			c.ok(s.charge.carries(h, el) and (el != "fire" or s.charge.intensity(h, "fire") == 1), "%s: ring hex %s carries tier 1" % [el, h])
		c.ok(open >= 15, "%s: the open ring was painted (%d)" % [el, open])
		for h in HHHex.area(land, 2):
			c.ok(s.charge.at(h).is_empty(), "%s: hull hex %s unpainted" % [el, h])
		for t in ["detonate", "overheat", "overfreeze", "douse", "reaction", "gale"]:
			c.ok(not ev.any(func(e): return e.type == t), "%s: no %s" % [el, t])
		c.eq(float(p.hp), float(p.max_hp), "%s: nobody hurt" % el)


## Every monster leap splashes: the two brains that leap (Colambros leap_stomp,
## Spirewalker leaping_squash) set u.leap.splash, a plain string (no Callable
## added to the unit; a co-op snapshot carries it).
func test_every_leap_splashes(c: HHSelfTest.HHCheck) -> void:
	for biome in ["caldera", "glade"]:
		var r := brain_fight(biome, 5)
		var s: HHSim = r[0]
		var brain: Object = r[1]
		var m: Dictionary = r[2]
		var p1: Dictionary = r[3]
		place(s, p1, spot_at(s, m, 6))
		if biome == "caldera":
			brain.call("_leap", s, m, p1)
		else:
			brain.call("_squash", s, m, p1)
		var seen := ""
		for i in 150:
			s.step()
			for p in s.players():
				p.hp = p.max_hp
			if not (m.leap as Dictionary).is_empty():
				seen = str((m.leap as Dictionary).get("splash", ""))
				var snap := HHSnapshot.capture(s)
				var leap_copy: Dictionary = (snap.u[str(m.id)] as Dictionary).leap
				c.eq(str(leap_copy.get("splash", "")), seen, "%s: the snapshot carries the splash" % biome)
				break
		c.eq(seen, "fire" if biome == "caldera" else "thunder", "%s: the leap carries its splash element" % biome)


func test_push_damage_deterministic(c: HHSelfTest.HHCheck) -> void:
	var runs: Array = []
	for run in 2:
		var r := brain_fight("caldera", 5)
		var s: HHSim = r[0]
		var brain: Object = r[1]
		var m: Dictionary = r[2]
		var p1: Dictionary = r[3]
		var p2: Dictionary = r[4]
		var at := spot_at(s, m, 6)
		place(s, p1, at)
		place(s, p2, at + Vector2i(1, 0) if s.arena.walkable(at + Vector2i(1, 0)) else at)
		brain.call("_leap", s, m, p1)
		var log: Array = []
		for i in 600:
			for e in s.step({ "p2": { "target": str(m.id), "attack": true } } if i % 45 == 0 else {}):
				if (e.type == "hurt" and str(e.cause).begins_with("push")) or (e.type == "paint" and bool(e.get("splash", false))):
					log.append("%d:%s:%s" % [int(e.tick), e.type, str(e.get("id", ""))])
			for p in s.players():
				if float(p.hp) < 600.0:
					p.hp = p.max_hp
		runs.append([s.state_hash(), log])
	c.eq(runs[0][0], runs[1][0], "same seed, same orders: same hash with push damage and splashes")
	c.eq(runs[0][1], runs[1][1], "the same push hurts and splashes on the same ticks (%d)" % (runs[0][1] as Array).size())
	c.ok(not (runs[0][1] as Array).is_empty(), "the run had a push hurt or a splash")


## H281: a hunter's own leap or dash aimed into a monster's body lands on the
## free hex nearest the aim (past the move's range if need be), outside the
## body, and the bump costs push_self_pct (5%, no stagger), by the monster.
func test_own_leap_and_dash_bump(c: HHSelfTest.HHCheck) -> void:
	for how in ["leap", "dash"]:
		var s := HHSim.new(HHArena.round_flat(1, 25.0, 0.0), 1)
		var p := s.add_player("p1", Vector2i(0, 8), "fire", "water", "daggers")
		var m := s.add_monster("m", Vector2i(0, -8), 50000.0, 2)
		place(s, m, Vector2i(0, 0))
		place(s, p, Vector2i(0, 4))
		var hp := float(p.hp)
		s.events = []
		var ev: Array = []
		if how == "leap":
			s.begin_leap(p, Vector2i(0, 0), 15, Callable())     # aimed at the monster's centre
			c.ok(not s.in_hull(m, (p.leap as Dictionary).to), "leap: redirected at launch, outside the body")
			c.ok(s.events.any(func(e): return e.type == "leap_redirect"), "leap: a leap_redirect event")
			for i in 16:
				ev.append_array(s.step())
		else:
			p.dash_charges = 2
			s._dash_order(p, s.arena.stand(Vector2i(0, 1)))   # into the body, short of its far side
			c.ok(not (p.dash as Dictionary).is_empty(), "dash: starts (a body does not block it)")
			for i in int(HHTune.value("dash_ticks")) + 2:
				ev.append_array(s.step())
		c.ok(not s.in_hull(m, p.hex), "%s: ends outside the body (%s)" % [how, p.hex])
		c.ok(HHHex.distance(p.hex, m.hex) == int(m.size) + 1, "%s: beside it, on the Attack Ring" % how)
		c.ok(ev.any(func(e): return e.type == "bump" and str(e.by) == "m"), "%s: a bump event" % how)
		c.near(hp - float(p.hp), float(p.max_hp) * HHTune.value("push_self_pct") / 100.0, 0.01, "%s: push_self_pct of max HP" % how)
		c.ok(not ev.any(func(e): return e.type == "push_out" and str(e.id) == "p1"), "%s: not also pushed out" % how)
		c.eq(int(p.stagger), 0, "%s: no stagger" % how)
