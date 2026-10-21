extends RefCounted
## H423 (the author: "Detangle this. They should be separate variables and easy
## to tune separately ... it should change them all independently"): every
## eruption and reaction has its own HHTune keys, and moving one reaction's
## key moves no other reaction.

const OWN := {
	"detonate": ["det_aa_mult_per_point", "det_aa_mult_per_axis", "det_aa_mult_per_water", "det_frost_mult", "detonate_ring_frac", "detonate_stagger"],
	"steam": ["steam_min_tier", "steam_aa_mult_min", "steam_aa_mult_max", "steam_ring_frac", "steam_stagger"],
	"eclipse": ["eclipse_min_tier", "eclipse_aa_mult_per_point", "eclipse_ring_frac", "eclipse_stagger", "eclipse_exposed_ticks"],
	"overheat": ["overheat_aa_mult", "overheat_ring_frac", "overheat_stagger", "overheat_splash_steps"],
	"geyser": ["geyser_aa_mult", "geyser_ring_frac", "geyser_stagger", "geyser_splash_steps"],
	"glint": ["glint_aa_mult", "glint_ring_frac", "glint_stagger", "glint_splash_steps"],
	"flux": ["flux_aa_mult", "flux_ring_frac", "flux_stagger", "flux_splash_steps", "flux_vuln_ticks", "flux_vuln_mult"],
	"shatter": ["shatter_aa_mult_per_point", "shatter_aa_mult_per_ice", "shatter_ring_frac", "shatter_stagger", "shatter_splash_steps"],
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
	var lever := { "detonate": "det_aa_mult_per_point", "steam": "steam_aa_mult_min", "eclipse": "eclipse_aa_mult_per_point", "overheat": "overheat_aa_mult",
		"geyser": "geyser_aa_mult", "glint": "glint_aa_mult", "flux": "flux_aa_mult", "shatter": "shatter_aa_mult_per_point" }
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


## H427: the comparison reference. Today's anchors hold, every row is a live
## multiple of the auto attack, the generated page matches the live values
## (rerun tools/reaction_table.gd after a retune), and F1 can draw it.
func test_reaction_table(c: HHSelfTest.HHCheck) -> void:
	var rows := HHFormulas.reaction_table()
	var by := {}
	for r in rows:
		by["%s|%s" % [r.reaction, r.case]] = float(r.mult)
	c.near(float(by["Steam|water + fire consumed T = 2"]), float(by["Detonate|thunder on fire 1 (1 point)"]), 1e-6, "anchor: Steam 1+1 = thunder on fire 1")
	c.near(float(by["Steam|water + fire consumed T = 6"]), float(by["Detonate|thunder on dark 3 + fire 3"]), 1e-6, "anchor: Steam 3+3 = thunder on dark 3 + fire 3")
	HHTune.set_value("geyser_aa_mult", 4.0)
	var live := HHFormulas.reaction_table().filter(func(r): return str(r.reaction) == "Geyser")
	c.near(float(live[0].mult), 4.0, 1e-6, "the table reads the live key")
	HHTune.set_value("geyser_aa_mult", HHTune.default_of("geyser_aa_mult"))
	var tool: GDScript = load("res://tools/reaction_table.gd")
	var page := FileAccess.get_file_as_string("res://design/elements/reaction_table.md").replace("\r", "")
	c.eq(page, str(tool.render()), "design/elements/reaction_table.md is current (rerun tools/reaction_table.gd)")
	c.ok(HHTunePanel.reaction_lines().contains("Steam"), "F1's read-only table")
