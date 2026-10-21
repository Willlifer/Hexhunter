extends RefCounted
## H423 (the author: "Detangle this. They should be separate variables and easy
## to tune separately ... it should change them all independently"): every
## eruption and reaction has its own HHTune keys, and moving one reaction's
## key moves no other reaction.

const OWN := {
	"detonate": ["det_mult_per_point", "det_mult_per_axis", "det_mult_per_water", "det_frost_mult", "detonate_ring_frac", "detonate_stagger"],
	"steam": ["steam_min_tier", "steam_mult_min", "steam_mult_max", "steam_ring_frac", "steam_stagger"],
	"eclipse": ["eclipse_min_tier", "eclipse_mult_per_point", "eclipse_ring_frac", "eclipse_stagger", "eclipse_exposed_ticks"],
	"overheat": ["overheat_mult", "overheat_ring_frac", "overheat_stagger", "overheat_splash_steps"],
	"geyser": ["geyser_mult", "geyser_ring_frac", "geyser_stagger", "geyser_splash_steps"],
	"glint": ["glint_mult", "glint_ring_frac", "glint_stagger", "glint_splash_steps"],
	"flux": ["flux_mult", "flux_ring_frac", "flux_stagger", "flux_splash_steps", "flux_vuln_ticks", "flux_vuln_mult"],
	"shatter": ["shatter_mult_per_point", "shatter_mult_per_ice", "shatter_ring_frac", "shatter_stagger", "shatter_splash_steps"],
	"swirl": ["swirl_radius_line", "swirl_radius_area", "swirl_area_min_hexes", "swirl_reaction_mult"],
}


func test_each_reaction_has_its_own_keys(c: HHSelfTest.HHCheck) -> void:
	var seen := {}
	for r in OWN:
		for k in OWN[r]:
			c.ok(HHTune.has(k), "%s: %s exists" % [r, k])
			c.ok(not seen.has(k), "%s is %s's alone" % [k, r])
			seen[k] = r
	for gone in ["eruption_ring_frac", "burst_splash_steps", "steam_mult_per_point"]:
		c.ok(not HHTune.has(gone), "the shared key %s is gone" % gone)


func _mults() -> Dictionary:
	return {
		"detonate": float(HHFormulas.fuse_mult(6, 2, 1).value),
		"steam": float(HHFormulas.steam_mult(4).value),
		"eclipse": float(HHFormulas.eruption_mult("eclipse", 4).value),
		"overheat": float(HHFormulas.burst_mult("overheat").value),
		"geyser": float(HHFormulas.burst_mult("geyser").value),
		"glint": float(HHFormulas.burst_mult("glint").value),
		"flux": float(HHFormulas.burst_mult("flux").value),
		"shatter": float(HHFormulas.shatter_mult(3, 2).value),
	}


func test_one_key_moves_one_reaction(c: HHSelfTest.HHCheck) -> void:
	var lever := { "detonate": "det_mult_per_point", "steam": "steam_mult_min", "eclipse": "eclipse_mult_per_point", "overheat": "overheat_mult",
		"geyser": "geyser_mult", "glint": "glint_mult", "flux": "flux_mult", "shatter": "shatter_mult_per_point" }
	var base := _mults()
	for r in lever:
		var k: String = lever[r]
		HHTune.set_value(k, HHTune.value(k) + 1.0)
		var now := _mults()
		for other in now:
			if other == r:
				c.ok(not is_equal_approx(float(now[other]), float(base[other])), "%s moves %s" % [k, r])
			else:
				c.near(float(now[other]), float(base[other]), 1e-9, "%s leaves %s alone" % [k, other])
		HHTune.set_value(k, HHTune.default_of(k))
