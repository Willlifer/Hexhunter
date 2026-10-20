extends RefCounted
## Lane V (L-12): the monsters' reactive state on the body. Each body is
## built headless, fed a unit dictionary through set_state, and the role
## materials are checked: emission off at rest, on (and tinted) in state.
## Also the HUD's status table covers every status the sim applies, and the
## player's weapons come from Lane A's coloured set (L-13).


func _body(id: String) -> HHMonsterBody:
	var b := HHMonsterBody.new()
	if not b.build(id):
		b.free()
		return null
	return b


func _energy(b: HHMonsterBody, role: String) -> float:
	var m := b.role_material(role)
	return m.emission_energy_multiplier if m.emission_enabled else 0.0


func test_role_materials_shared(c: HHSelfTest.HHCheck) -> void:
	var b := _body("colambros")
	c.ok(b != null, "colambros body builds")
	if b == null:
		return
	var quill: MeshInstance3D = null
	for mi in b.meshes:
		if str(mi.name) == "body_quill":
			quill = mi
	c.ok(quill != null, "body_quill mesh present (one mesh per role, H303)")
	if quill != null:
		c.ok(quill.get_surface_override_material(0) == b.role_material("quill"), "the quill surface uses the body's shared quill material")
	c.eq(_energy(b, "quill"), 0.0, "quills dark before any state")
	b.update(0.05)
	c.eq(_energy(b, "quill"), 0.0, "set_state never called: still dark (no-op until fed)")
	b.free()


func test_colambros_smoulder(c: HHSelfTest.HHCheck) -> void:
	var b := _body("colambros")
	if b == null:
		c.ok(false, "colambros body builds")
		return
	b.set_state({ "id": "colambros", "smoulder": false })
	b.update(0.05)
	c.eq(_energy(b, "quill"), 0.0, "not smouldering: quills dark")
	c.eq(b.state_name, "", "no state label")
	b.set_state({ "id": "colambros", "smoulder": true })
	b.update(0.05)
	var e := _energy(b, "quill")
	c.ok(e > 1.0, "smouldering: quill emission on (%.2f)" % e)
	c.ok(b.role_material("quill").emission.r > b.role_material("quill").emission.b, "ember colour is warm")
	c.ok(b.role_material("quill").albedo_color != Color.WHITE, "quill albedo tinted toward the ember")
	c.ok(_energy(b, "eye") > 0.5, "eyes glow too")
	c.ok(b.glow > 0.3, "glow reports the pulse (%.2f)" % b.glow)
	c.eq(b.state_name, "smouldering", "state label for the HUD")
	b.set_state({ "id": "colambros", "smoulder": false })
	b.update(0.05)
	c.eq(_energy(b, "quill"), 0.0, "back to dark when the flag drops")
	c.eq(b.role_material("quill").albedo_color, Color.WHITE, "tint cleared")
	b.free()


func test_rimeslithe_cold(c: HHSelfTest.HHCheck) -> void:
	var b := _body("rimeslithe")
	if b == null:
		c.ok(false, "rimeslithe body builds")
		return
	b.set_state({ "id": "rimeslithe", "cold": 0.0 })
	b.update(0.05)
	c.eq(_energy(b, "crystal"), 0.0, "cold 0: crystals at their smoky rest")
	c.eq(b.role_material("crystal").albedo_color, Color.WHITE, "cold 0: no tint")
	b.set_state({ "id": "rimeslithe", "cold": 0.5 })
	b.update(0.05)
	var half := _energy(b, "crystal")
	c.ok(half > 0.3, "cold 0.5: crystals lit (%.2f)" % half)
	var tint := b.role_material("crystal").albedo_color
	c.ok(tint.b > tint.r, "tint leans cyan (r %.2f b %.2f)" % [tint.r, tint.b])
	c.eq(b.state_name, "", "0.5 is not yet 'cold' for the HUD")
	b.set_state({ "id": "rimeslithe", "cold": 1.0 })
	b.update(0.05)
	var full := _energy(b, "crystal")
	c.ok(full > half * 1.5, "cold 1.0 brighter than 0.5 (%.2f > %.2f)" % [full, half])
	c.eq(b.state_name, "cold", "state label above 0.5")
	c.near(b.glow, 1.0, 0.001, "glow is the meter")
	b.free()


func test_spirewalker_charge_and_reeds(c: HHSelfTest.HHCheck) -> void:
	var b := _body("spirewalker")
	if b == null:
		c.ok(false, "spirewalker body builds")
		return
	b.set_state({ "id": "spirewalker", "charge": 0.0, "reeds_burnt": false })
	b.update(0.05)
	c.ok(_energy(b, "arc") > 0.5, "beads keep a resting violet at charge 0 (%.2f)" % _energy(b, "arc"))
	c.ok(b.bead_count() >= 6 and b.bead_count() <= 12, "arc beads clustered from the mesh (%d)" % b.bead_count())
	var arcs := b.skeleton.get_node_or_null("arcs") as MeshInstance3D
	c.ok(arcs != null, "arc ribbon node built under the skeleton")
	c.ok(arcs != null and not arcs.visible, "no arcs below the threshold")
	c.eq(b.state_name, "", "not charged")
	b.set_state({ "id": "spirewalker", "charge": 0.9, "reeds_burnt": false })
	b.update(0.1)
	c.ok(_energy(b, "arc") > 3.0, "charged: beads bright (%.2f)" % _energy(b, "arc"))
	c.ok(_energy(b, "reed") > 0.8, "charged: reed tips take the violet (%.2f)" % _energy(b, "reed"))
	c.ok(arcs != null and arcs.visible, "arcs showing above 0.6")
	c.ok(arcs != null and (arcs.mesh as ImmediateMesh).get_surface_count() == 1, "arc ribbons drawn")
	c.eq(b.state_name, "charged", "state label")
	for i in b.bead_count():
		var p := b.bead_pos(i)
		c.ok(p.y > 1.5 and p.y < 4.5, "bead %d sits over the back (y %.2f)" % [i, p.y])
	b.set_state({ "id": "spirewalker", "charge": 0.0, "reeds_burnt": true })
	b.update(0.1)
	c.eq(_energy(b, "arc"), 0.0, "reeds burnt: beads dark")
	c.ok(arcs != null and not arcs.visible, "reeds burnt: arcs gone")
	c.ok(b.role_material("reed").albedo_color.get_luminance() < 0.5, "reeds burnt: reed albedo charred")
	c.eq(b.state_name, "reeds_burnt", "state label while cut")
	c.eq(b.glow, 0.0, "no glow while cut")
	b.free()


func test_swampfang_darkness_cue(c: HHSelfTest.HHCheck) -> void:
	var b := _body("swampfang")
	if b == null:
		c.ok(false, "swampfang body builds")
		return
	b.set_state({ "id": "swampfang" })
	b.update(0.05)
	c.eq(_energy(b, "eye"), 0.0, "eyes plain at rest")
	b.cue("darkness", 1.0)
	b.update(0.05)
	c.ok(_energy(b, "eye") > 0.5, "darkness: eyes glow (%.2f)" % _energy(b, "eye"))
	c.ok(_energy(b, "frill") > 0.3, "darkness: frill glows (%.2f)" % _energy(b, "frill"))
	c.eq(b.state_name, "darkness", "state label")
	b.update(1.2)
	c.eq(_energy(b, "eye"), 0.0, "cue runs out")
	c.eq(b.state_name, "", "label clears")
	b.free()


func test_swampfang_cue_from_bound_sim(c: HHSelfTest.HHCheck) -> void:
	var a := HHArena.round_flat(1, 25.0, 0.6)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 0))
	s.add_monster("swampfang", Vector2i(6, 0), 3000.0, 2, [])
	var b := _body("swampfang")
	if b == null:
		c.ok(false, "swampfang body builds")
		return
	b.bind(s, "swampfang")
	b.update(0.05)
	c.eq(_energy(b, "eye"), 0.0, "bound, no telegraph: dark")
	s.telegraph("swampfang", [Vector2i(0, 0)], 45, { "name": "darkness", "element": "dark" })
	b.update(0.05)
	c.ok(_energy(b, "eye") > 0.5, "the darkness telegraph lights the eyes through the bound sim")
	b.free()


func test_hud_status_table(c: HHSelfTest.HHCheck) -> void:
	for st in ["slow", "freeze", "poison", "paralysis", "burn"]:
		c.ok(HHHud.STATUS.has(st), "HUD icon for %s" % st)
		var row: Dictionary = HHHud.STATUS[st]
		c.ok(str(row.get("glyph", "")) != "" and row.has("color"), "%s has a glyph and colour" % st)
	c.ok(HHHud.MONSTER_STATE.has("smouldering") and HHHud.MONSTER_STATE.has("charged") and HHHud.MONSTER_STATE.has("cold"), "monster-state icons")
	var a := HHArena.round_flat(1, 25.0, 0.6)
	var s := HHSim.new(a, 1)
	s.add_player("p1", Vector2i(0, 0))
	s.add_monster("colambros", Vector2i(6, 0), 3000.0, 2, [])
	s.unit("colambros")["smoulder"] = true
	c.eq(HHHud.monster_state_of(s.unit("colambros")), "smouldering", "monster state read from the unit")
	s.unit("colambros")["smoulder"] = false
	c.eq(HHHud.monster_state_of(s.unit("colambros")), "", "no state")
	c.eq(HHHud.monster_state_of({ "id": "rimeslithe", "cold": 0.8 }), "cold", "cold above half")
	c.eq(HHHud.monster_state_of({ "id": "spirewalker", "charge": 0.7 }), "charged", "charged above 0.6")
	c.eq(HHHud.monster_state_of({ "id": "spirewalker", "charge": 0.7, "reeds_burnt": true }), "reeds_burnt", "burnt reeds win")
	s.apply_status(s.unit("p1"), "slow", 60)
	s.apply_status(s.unit("p1"), "burn", 120)
	var rows := HHHud.status_rows(s.unit("p1"))
	c.eq(rows.size(), 2, "two status rows")
	c.eq(str(rows[0].name), "burn", "longest first")
	c.near(float(rows[0].seconds), 4.0, 0.01, "seconds from ticks")


func test_weapons_from_lane_a_set(c: HHSelfTest.HHCheck) -> void:
	c.eq(HHPlayerBody.WEAPON_DIR, "res://art/weapons/", "loader points at the coloured set")
	c.ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://art/weapons/bw_temp")), "bw_temp removed")
	for w in ["lance", "daggers", "bow"]:
		var row := HHPlayerBody.weapon_row(w)
		c.ok(not row.is_empty(), "%s resolves to a manifest row" % w)
		c.ok(str(row.get("glb", "")).begins_with("res://art/weapons/") and not str(row.get("glb", "")).contains("bw_temp"), "%s glb is Lane A's" % w)
	c.eq(str(HHPlayerBody.weapon_row("daggers").get("glb", "")), "res://art/weapons/karambit.glb", "daggers -> karambit")
	c.eq(str(HHPlayerBody.weapon_row("daggers").get("offhand_glb", "")), "res://art/weapons/karambit_l.glb", "the mirrored off-hand karambit")
	var b := HHPlayerBody.new()
	if not b.build("bow"):
		c.ok(false, "bow body builds")
		b.free()
		return
	c.ok(b.weapon_main != null, "bow hung")
	c.ok(b.arrow != null, "arrow instanced from the weapons table")
	c.ok(b.equip("daggers") and b.weapon_off != null, "daggers: off hand hung")
	c.ok(b.equip("lance") and b.weapon_main != null and b.weapon_off == null, "lance: one glb")
	b.free()
