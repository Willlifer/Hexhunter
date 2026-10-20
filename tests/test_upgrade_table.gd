extends RefCounted
## Lane U: the upgrade table (HHUpgrades): well formed, every drop source is a
## real monster, three slots per skill, weapon fit, every skill covered.


func test_check_is_clean(c: HHSelfTest.HHCheck) -> void:
	var problems := HHUpgrades.check()
	c.eq(problems.size(), 0, "check(): %s" % str(problems))
	c.ok(HHUpgrades.TABLE.size() >= 12, "the six kickoff examples plus six more (%d)" % HHUpgrades.TABLE.size())
	for id in ["exchange_immune", "exchange_burst", "energized_double", "arcing_twice", "daggerleap_homing", "pierce_wide"]:
		c.ok(HHUpgrades.TABLE.has(id), "kickoff example %s is in the table" % id)


func test_drops_from_real_monsters(c: HHSelfTest.HHCheck) -> void:
	var seen := {}
	for id in HHUpgrades.TABLE:
		for m in HHUpgrades.TABLE[id].drops_from:
			c.ok(ResourceLoader.exists("res://src/monster/%s.gd" % m), "%s drops from %s, which exists in src/monster/" % [id, m])
			seen[m] = true
	for m in ["swampfang", "colambros", "rimeslithe", "spirewalker"]:
		c.ok(seen.has(m), "%s drops something" % m)


func test_every_skill_has_an_upgrade(c: HHSelfTest.HHCheck) -> void:
	for w in HHUpgrades.WEAPONS:
		for sk in HHUpgrades.SKILLS:
			var n := 0
			for id in HHUpgrades.for_weapon(w):
				if str(HHUpgrades.TABLE[id].skill) == sk:
					n += 1
			c.ok(n >= 1, "%s %s has at least one upgrade (%d)" % [w, sk, n])


func test_slot_limit_and_weapon_fit(c: HHSelfTest.HHCheck) -> void:
	var ups := HHUpgrades.empty_slots()
	c.ok(HHUpgrades.slot(ups, "w", "exchange_immune", "lance"), "an any-weapon upgrade slots on the lance")
	c.ok(not HHUpgrades.slot(ups, "w", "exchange_immune", "lance"), "not twice")
	c.ok(not HHUpgrades.slot(ups, "q", "exchange_immune", "lance"), "refused on the wrong skill")
	c.ok(not HHUpgrades.slot(ups, "q", "energized_double", "lance"), "a bow upgrade is refused on the lance")
	c.ok(HHUpgrades.slot(ups, "q", "energized_double", "bow"), "...and slots on the bow")
	c.ok(not HHUpgrades.slot(ups, "q", "nope", "bow"), "unknown id refused")
	# the limit: three per skill (two real w upgrades plus one filler fills it)
	var three := HHUpgrades.empty_slots()
	c.ok(HHUpgrades.slot(three, "w", "exchange_burst", "daggers"), "first w slotted")
	three["w"].append("filler")                       # a second occupant, straight into the array
	c.ok(HHUpgrades.slot(three, "w", "exchange_immune", "daggers"), "third slot still open")
	c.eq((three["w"] as Array).size(), 3, "three slotted")
	var full := { "w": ["a", "b", "c"] }
	c.ok(not HHUpgrades.slot(full, "w", "exchange_immune", "lance"), "a fourth is refused (max 3 per skill)")
	c.ok(HHUpgrades.unslot(three, "w", "filler"), "unslot removes")
	c.ok(not HHUpgrades.unslot(three, "w", "filler"), "...once")
	c.eq((three["w"] as Array).size(), 2, "two left")
	c.ok(HHUpgrades.slot(three, "w", "exchange_immune", "daggers") == false, "still refused while slotted")
	c.ok(HHUpgrades.slot({}, "t", "potion_cleanse", "bow"), "the potion (t) slots on any weapon, creating the key")


func test_has_reads_the_unit(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 20.0, 0.0)
	var s := HHSim.new(a, 1)
	var u := s.add_player("p1", Vector2i(0, 4), "fire", "water", "lance", { "q": ["pierce_wide"], "w": ["exchange_immune"] })
	c.ok(HHUpgrades.has(u, "pierce_wide"), "has pierce_wide")
	c.ok(HHUpgrades.has(u, "exchange_immune"), "has exchange_immune")
	c.ok(not HHUpgrades.has(u, "exchange_burst"), "not exchange_burst")
	c.ok(not HHUpgrades.has(u, "nope"), "unknown is false")
	var plain := s.add_player("p2", Vector2i(1, 4))
	c.ok(not HHUpgrades.has(plain, "pierce_wide"), "a player without upgrades has none (old callers still work)")
	c.ok(not HHUpgrades.has(s.add_monster("m", Vector2i(0, -4)), "pierce_wide"), "a monster has none")
	c.eq(HHUpgrades.for_weapon("bow").size(), HHUpgrades.for_weapon("bow").filter(func(id): return HHUpgrades.fits(id, "bow")).size(), "for_weapon only lists fitting ids")
	c.ok("exchange_immune" in HHUpgrades.for_weapon("daggers"), "any-weapon upgrades list for every weapon")
	c.ok(not "pierce_wide" in HHUpgrades.for_weapon("daggers"), "lance upgrades do not list for daggers")
