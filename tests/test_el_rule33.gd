extends RefCounted
## Lane EL (spec 3.3, H262 DECIDE-C): one rule for who every reaction hurts.
## Player-triggered: the monster takes the trigger's auto attack x mult; never
## the trigger, never an ally. Monster- or arena-triggered: the monster takes
## monster_reaction_frac of the player-cast damage, every hunter in it takes
## monster_reaction_player_frac of it and is never killed (left at 1 HP at
## worst). Plus the hooks sections 7-8 asked for: react_at (one contained
## monster action: detonate / quench / shatter in a radius).


func _sim() -> HHSim:
	var s := HHSim.new(HHArena.round_flat(1, 17.5, 0.0), 1)
	s.add_player("p1", Vector2i(0, 3), "fire", "thunder", "lance")
	s.add_player("p2", Vector2i(3, 3), "water", "ice", "daggers")
	s.add_monster("m", Vector2i(0, -2), 20000.0, 2)
	return s


func test_player_trigger(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var p1 := s.unit("p1")
	var p2 := s.unit("p2")
	var hx := Vector2i(0, 0)                        # the hull's edge
	s.paint([hx], "fire", "p1", 2)
	s.paint([p1.hex, p2.hex], "fire", "p1", 2)
	s.step()
	var mhp := float(m.hp)
	s.paint([hx, p1.hex, p2.hex], "thunder", "p1")
	var want: float = HHFormulas.reaction_damage(s.reaction_unit("p1"), HHTune.value("det_aa_mult_per_point") * 2.0, 1.0, 0.0, 1.0).value
	c.near(mhp - float(m.hp), want, 1.0, "the monster: the trigger's auto attack x 6")
	c.near(float(p1.hp), float(p1.max_hp), 0.01, "never the trigger")
	c.near(float(p2.hp), float(p2.max_hp), 0.01, "never an ally")


func test_monster_trigger_and_floor(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var p1 := s.unit("p1")
	var hx := Vector2i(0, 0)
	s.paint([hx, p1.hex], "fire", "p1", 2)
	s.step()
	var mhp := float(m.hp)
	var php := float(p1.hp)
	s.paint([hx, p1.hex], "thunder", "m")             # the monster's own spell completes it
	var base := s.reaction_unit("p1") * HHTune.value("det_aa_mult_per_point") * 2.0           # the charge is p1's: its player-cast damage
	c.near(mhp - float(m.hp), base * HHTune.value("monster_reaction_frac"), 1.0, "the monster takes monster_reaction_frac")
	c.near(php - float(p1.hp), base * HHTune.value("monster_reaction_player_frac"), 1.0, "the hunter in it takes monster_reaction_player_frac")
	s.step()
	p1.hp = 5.0
	s.paint([p1.hex], "fire", "m", 3)
	s.step()
	s.paint([p1.hex], "thunder", "m")
	c.near(float(p1.hp), 1.0, 0.001, "never kills: left at 1 HP")
	c.eq(s.over, "", "the fight goes on")
	s.step()
	s.paint([p1.hex], "fire", "env", 3)
	s.step()
	s.paint([p1.hex], "thunder", "env")
	c.near(float(p1.hp), 1.0, 0.001, "the arena's reactions use the same rule")


func test_react_at_hooks(c: HHSelfTest.HHCheck) -> void:
	var s := _sim()
	var m := s.unit("m")
	var area := s.arena.area(Vector2i(0, -2), 3)
	for h in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-2, -2)]:
		s.paint([h], "fire", "p1", 2)
	var cry := Vector2i(2, -4)                      # its fragments land clear of the fire hexes
	s.paint([cry], "dark", "p1", 1)
	s.step()
	s.paint([cry], "ice", "p1", 1)
	s.step()
	var mhp := float(m.hp)
	var r := s.react_at(area, "m", "detonate")
	c.eq(r.detonations.size(), 3, "every charged hex blasts once")
	c.eq(r.shatters.size(), 1, "the crystal shatters")
	c.ok(float(m.hp) < mhp, "monster-triggered: the monster is hurt (reduced)")
	var left := 0
	for h in area:
		if s.charge.charged(h) and not s.charge.produced(h):
			left += 1
	c.eq(left, 0, "nothing in the radius is left but the contained fragment splash")
	s.step()
	s.paint([Vector2i(0, 0)], "water", "p1", 2)
	s.step()
	var q := s.react_at(area, "m", "quench")
	c.ok(s.charge.at(Vector2i(0, 0)).is_empty(), "quench clears")
	c.ok(q.detonations.is_empty(), "with no blast")


## H437: the hunters' light never heals the monster; its own light (and
## unowned light) still does; a hunter's light still heals the hunters.
func test_enemy_light_never_heals(c: HHSelfTest.HHCheck) -> void:
	for src in ["p1", "m"]:
		var s := _sim()
		var m := s.unit("m")
		var p2 := s.unit("p2")
		m.hp = float(m.max_hp) * 0.5
		p2.hp = float(p2.max_hp) * 0.5
		s.paint([m.hex, p2.hex], "light", src, 2)
		var mhp := float(m.hp)
		var php := float(p2.hp)
		for i in 40:
			s.step()
		if src == "p1":
			c.ok(float(m.hp) <= mhp, "a hunter's light does not heal the monster (%.0f -> %.0f)" % [mhp, float(m.hp)])
			c.ok(float(p2.hp) > php, "a hunter's light heals an ally")
		else:
			c.ok(float(m.hp) > mhp, "the monster's own light heals it")
			c.ok(float(p2.hp) <= php, "the monster's light does not heal the hunters")
