extends RefCounted
## Lane U: HHDrops (deterministic, weighted, no duplicates) and HHSave
## (round-trip through user://test_hunter.json, slots, hunts).

const TEST_PATH := "user://test_hunter.json"


func test_roll_is_deterministic(c: HHSelfTest.HHCheck) -> void:
	for m in ["swampfang", "colambros", "rimeslithe", "spirewalker"]:
		var a := RandomNumberGenerator.new()
		a.seed = 7
		var b := RandomNumberGenerator.new()
		b.seed = 7
		var ra: Array = []
		var rb: Array = []
		for i in 20:
			ra.append(HHDrops.roll(m, a, "lance"))
			rb.append(HHDrops.roll(m, b, "lance"))
		c.eq(ra, rb, "%s: same seed, same twenty rolls" % m)
		for r in ra:
			c.ok(r.size() >= 1 and r.size() <= 2, "%s: 1-2 drops (%d)" % [m, r.size()])
			for id in r:
				c.ok(m in HHUpgrades.TABLE[id].drops_from, "%s: %s drops from it" % [m, id])
			if r.size() == 2:
				c.ok(r[0] != r[1], "%s: two different drops" % m)
	var x := RandomNumberGenerator.new()
	x.seed = 7
	var y := RandomNumberGenerator.new()
	y.seed = 8
	var diff := false
	for i in 20:
		if HHDrops.roll("swampfang", x) != HHDrops.roll("swampfang", y):
			diff = true
	c.ok(diff, "different seeds roll differently")
	c.eq(HHDrops.roll("nobody", x), [], "an unknown monster drops nothing")


func test_roll_prefers_the_weapon_used(c: HHSelfTest.HHCheck) -> void:
	# swampfang's pool holds lance, daggers, bow and any upgrades
	var pool := HHDrops.pool("swampfang")
	c.ok(pool.size() >= 4, "swampfang has a pool (%d)" % pool.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lance := 0
	var bow := 0
	var n := 400
	for i in n:
		for id in HHDrops.roll("swampfang", rng, "lance"):
			match str(HHUpgrades.TABLE[id].weapon):
				"lance": lance += 1
				"bow": bow += 1
	c.ok(lance > bow, "hunting with the lance drops lance upgrades more often than bow ones (%d vs %d)" % [lance, bow])
	c.ok(bow > 0, "...but bow upgrades still drop")
	c.near(HHDrops.weight_of("pierce_wide", "lance"), HHDrops.WEIGHT_WEAPON, 0.01, "own-weapon weight")
	c.near(HHDrops.weight_of("exchange_immune", "lance"), HHDrops.WEIGHT_ANY, 0.01, "any weight")
	c.near(HHDrops.weight_of("energized_double", "lance"), HHDrops.WEIGHT_OTHER, 0.01, "other weight")
	c.near(HHDrops.weight_of("energized_double", ""), HHDrops.WEIGHT_OTHER, 0.01, "no weapon: flat")


func test_roll_skips_owned(c: HHSelfTest.HHCheck) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var owned: Array = []
	var pool := HHDrops.pool("rimeslithe")
	var rolls := 0
	while rolls < 50:
		rolls += 1
		var r := HHDrops.roll("rimeslithe", rng, "bow", owned)
		for id in r:
			c.ok(not id in owned, "never a duplicate of an owned upgrade (%s)" % id)
			owned.append(id)
		if r.is_empty():
			break
	c.eq(owned.size(), pool.size(), "the whole pool was handed out, once each")
	c.eq(HHDrops.roll("rimeslithe", rng, "bow", owned), [], "then nothing is left")


func test_save_round_trip(c: HHSelfTest.HHCheck) -> void:
	HHSave.path = TEST_PATH
	HHSave.wipe()
	var s := HHSave.load_or_new()
	c.eq(s.owned.size(), 0, "a new file owns nothing")
	c.ok(s.slotted.has("lance") and s.slotted.has("daggers") and s.slotted.has("bow"), "three weapons' slots")
	c.eq(s.slotted.lance.q, [], "empty slots")
	c.ok(not s.slot("lance", "q", "pierce_wide"), "cannot slot what you do not own")
	c.ok(s.own("pierce_wide"), "owned a drop")
	c.ok(not s.own("pierce_wide"), "not twice")
	c.ok(not s.own("nope"), "unknown refused")
	c.ok(s.own("exchange_immune") and s.own("energized_double"), "two more")
	c.ok(s.slot("lance", "q", "pierce_wide"), "slotted on the lance")
	c.ok(s.slot("lance", "w", "exchange_immune"), "any-weapon slotted on the lance")
	c.ok(s.slot("bow", "w", "exchange_immune"), "...and on the bow at the same time")
	c.ok(not s.slot("lance", "q", "energized_double"), "a bow upgrade refused on the lance")
	c.ok(s.slot("bow", "q", "energized_double"), "...fine on the bow")
	s.record_hunt("swampfang", "pond", "lance", "win", 83.25)
	c.ok(s.save(), "saved")
	c.ok(FileAccess.file_exists(TEST_PATH), "file written")
	var t := HHSave.load_or_new()
	c.eq(t.owned, ["pierce_wide", "exchange_immune", "energized_double"], "owned round-trips in order")
	c.eq(t.slotted.lance.q, ["pierce_wide"], "lance q slot round-trips")
	c.eq(t.slotted.lance.w, ["exchange_immune"], "lance w slot round-trips")
	c.eq(t.slotted.bow.q, ["energized_double"], "bow q slot round-trips")
	c.eq(t.slotted.bow.w, ["exchange_immune"], "bow w slot round-trips")
	c.eq(t.slotted.daggers.e, [], "untouched slots stay empty")
	c.eq(t.hunts.size(), 1, "one hunt recorded")
	c.eq(str(t.hunts[0].monster), "swampfang", "hunt monster")
	c.eq(str(t.hunts[0].result), "win", "hunt result")
	c.near(float(t.hunts[0].seconds), 83.3, 0.11, "hunt seconds")
	c.ok(str(t.hunts[0].date) != "", "dated")
	c.eq(int(t.version), HHSave.VERSION, "versioned")
	var ups := t.upgrades_for("lance")
	c.eq(ups.q, ["pierce_wide"], "upgrades_for shapes the launch cfg")
	ups.q.append("x")
	c.eq(t.slotted.lance.q, ["pierce_wide"], "...as a copy")
	c.ok(t.unslot("lance", "q", "pierce_wide"), "unslot")
	c.eq(t.slotted.lance.q, [], "slot empty again")
	c.ok(t.owns("pierce_wide"), "still owned")
	# a player built from the save carries the upgrades into the sim
	var sim := HHSim.new(HHArena.round_flat(1, 20.0, 0.0), 1)
	var u := sim.add_player("p1", Vector2i(0, 4), "fire", "water", "bow", t.upgrades_for("bow"))
	c.ok(HHUpgrades.has(u, "energized_double"), "the sim unit has the saved bow upgrade")
	c.ok(HHUpgrades.has(u, "exchange_immune"), "...and the any upgrade")
	HHSave.wipe()
	c.ok(not FileAccess.file_exists(TEST_PATH), "test file deleted")
	HHSave.path = HHSave.DEFAULT_PATH


func test_save_tolerates_junk(c: HHSelfTest.HHCheck) -> void:
	HHSave.path = TEST_PATH
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{ "version": 1, "owned": ["pierce_wide", "bogus", "pierce_wide"], "slotted": { "lance": { "q": ["pierce_wide", "bogus"], "w": ["energized_double"] } }, "hunts": [1, { "monster": "x" }] }')
	f.close()
	var s := HHSave.load_or_new()
	c.eq(s.owned, ["pierce_wide"], "unknown and duplicate ids dropped")
	c.eq(s.slotted.lance.q, ["pierce_wide"], "unknown slot entries dropped")
	c.eq(s.slotted.lance.w, [], "an unowned, unfitting slot entry dropped")
	c.eq(s.slotted.bow.q, [], "missing weapons get empty slots")
	c.eq(s.hunts.size(), 1, "non-dictionary hunts dropped")
	HHSave.wipe()
	var g := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	g.store_string("not json")
	g.close()
	var t := HHSave.load_or_new()
	c.eq(t.owned.size(), 0, "a corrupt file loads as new")
	HHSave.wipe()
	HHSave.path = HHSave.DEFAULT_PATH
