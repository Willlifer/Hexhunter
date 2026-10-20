extends RefCounted
## Lane UI (H800+): the HUD paints headless for every weapon, status and
## monster state (through HHHud.Paint into a scratch canvas item), every
## glyph is well formed, the bar's layout holds together, the thumbnails
## exist for every registry id, and the lobby's tiles and sockets paint.


func _paint_hud(hud: HHHud) -> bool:
	var rid := RenderingServer.canvas_item_create()
	var ok := hud.paint(HHHud.Paint.new(rid), Vector2(1600, 900))
	RenderingServer.free_rid(rid)
	return ok


func test_hud_paints_every_weapon_status_and_state(c: HHSelfTest.HHCheck) -> void:
	var states := [{}, { "smoulder": true }, { "cold": 0.8 }, { "charge": 0.9 }, { "reeds_burnt": true }, { "untargetable": true }]
	for w in HHRegistry.ids("weapon"):
		var sim := HHSim.new(HHArena.round_flat(1, 25.0, 0.6), 1)
		var p := sim.add_player("p1", Vector2i(0, 0), "thunder", "dark", str(w))
		var m := sim.add_monster("spirewalker", Vector2i(6, 0), 20000.0, 2, [])
		var hud := HHHud.new()
		hud.sim = sim
		hud.player_id = "p1"
		hud.monster_id = "spirewalker"
		c.ok(_paint_hud(hud), "%s: paints at rest" % w)
		for s in HHHud.STATUS:
			p.statuses[s] = { "ticks": 95 }
		p.statuses["mystery"] = { "ticks": 400 }
		for k in ["q", "w", "e", "r", "t"]:
			p.cooldowns[k] = 40
		p.guard = 20
		p.potions = 0
		p.hp = float(p.max_hp) * 0.3
		p.regen = { "x": 1 }
		m.hp = float(m.max_hp) * 0.4
		hud.tick(0.5)
		for st in states:
			for k in st:
				m[k] = st[k]
			c.ok(_paint_hud(hud), "%s: paints with statuses, cooldowns, state %s" % [w, str(st)])
		p.hp = 0.0
		sim.over = "dead"
		c.ok(_paint_hud(hud), "%s: paints FALLEN at 0 hp" % w)
		p.hp = float(p.max_hp)
		sim.over = "win"
		c.ok(_paint_hud(hud), "%s: paints VICTORY at full hp" % w)
		hud.free()
	var bare := HHHud.new()
	c.ok(not _paint_hud(bare), "no sim: nothing painted, no error")
	bare.free()


func test_glyphs_are_well_formed(c: HHSelfTest.HHCheck) -> void:
	for id in HHHud.GLYPHS:
		var ops := HHHud.glyph_ops(str(id))
		c.ok(not ops.is_empty(), "glyph %s has ops" % id)
		var inside := true
		for op in ops:
			var pts := PackedVector2Array()
			if op.has("line"):
				pts = op.line
			elif op.has("poly"):
				pts = op.poly
				if pts.size() < 3:
					inside = false
			elif op.has("dot"):
				pts = PackedVector2Array([op.dot])
			for q in pts:
				if not (q.is_finite() and q.x > -0.15 and q.x < 1.15 and q.y > -0.15 and q.y < 1.15):
					inside = false
		c.ok(inside, "glyph %s stays in its box" % id)
	c.eq(HHHud.glyph_ops("nope"), [], "unknown glyph: no ops")
	for w in HHRegistry.ids("weapon"):
		for k in ["q", "w", "e", "r", "t"]:
			c.ok(str(HHHud.skill_icon(str(w), k)) in HHHud.GLYPHS, "%s %s has a skill icon" % [w, k])
	for el in HHFormulas.ELEMENTS:
		c.ok(str(el) in HHHud.GLYPHS, "element %s has a glyph" % el)
	for s in HHHud.STATUS:
		c.ok(str(HHHud.STATUS[s].icon) in HHHud.GLYPHS, "status %s has a glyph" % s)
	for s in HHHud.MONSTER_STATE:
		c.ok(str(HHHud.MONSTER_STATE[s].icon) in HHHud.GLYPHS, "monster state %s has a glyph" % s)


func test_bar_layout(c: HHSelfTest.HHCheck) -> void:
	for size in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		var L := HHHud.layout(size)
		var screen := Rect2(Vector2.ZERO, size)
		var orb_c: Vector2 = L.orb.c
		var orb_r: float = L.orb.r
		c.near(orb_c.x, size.x * 0.5, 0.01, "%s: the orb is centred" % size)
		var rects: Array = (L.slots as Dictionary).values() + [L.element, L.backup, L.potion]
		var ok := true
		for r in rects:
			var rr: Rect2 = r
			if not screen.encloses(rr) or not (L.plate as Rect2).encloses(rr):
				ok = false
			var near := Vector2(clampf(orb_c.x, rr.position.x, rr.end.x), clampf(orb_c.y, rr.position.y, rr.end.y))
			if near.distance_to(orb_c) < orb_r:
				ok = false
		c.ok(ok, "%s: every slot on screen, on the plate, clear of the orb" % size)
		c.ok(orb_c.y + orb_r <= size.y, "%s: the orb stays on screen" % size)
		c.ok((L.monster as Rect2).position.y > 0.0 and (L.status as Vector2).y < (L.plate as Rect2).position.y, "%s: monster bar on top, statuses above the plate" % size)


func test_sweep_and_slot_paint(c: HHSelfTest.HHCheck) -> void:
	var rid := RenderingServer.canvas_item_create()
	var pt := HHHud.Paint.new(rid)
	for f in [0.0, 0.01, 0.25, 0.5, 0.75, 0.999, 1.0]:
		HHHud.sweep(pt, Rect2(10, 10, 60, 60), f)
		HHHud.slot(pt, Rect2(10, 10, 60, 60), "pierce", Color(0.5, 0.2, 0.1), "q", f, "1.0", f > 0.5, f)
	HHHud.slot(pt, Rect2(10, 10, 60, 60), "", Color(0.5, 0.2, 0.1), "q")          # no glyph: the letter
	HHHud.plate(pt, Rect2(0, 0, 300, 80), true, true, 0.5)
	HHHud.thumb_disc(pt, null, Vector2(40, 40), 20.0)
	RenderingServer.free_rid(rid)
	c.ok(true, "sweep, slot, plate and an empty thumb paint for every fraction")
	c.eq(HHHud._secs(45), "1.5", "seconds under 10 keep a decimal")
	c.eq(HHHud._secs(600), "20", "seconds over 10 round up")


func test_thumbnails_exist_for_every_registry_id(c: HHSelfTest.HHCheck) -> void:
	for kind in ["arena", "monster", "weapon"]:
		for id in HHRegistry.ids(kind):
			var path := HHHud.thumb_path(kind, str(id))
			c.ok(FileAccess.file_exists(path) or ResourceLoader.exists(path), "thumbnail %s exists (tools/ui_thumbs.gd)" % path)
			var tex := HHHud.thumb(kind, str(id))
			c.ok(tex != null and tex.get_width() > 0, "thumbnail %s %s loads" % [kind, id])
	c.eq(HHHud.thumb("monster", "nobody"), null, "no thumbnail: null")


func test_lobby_tiles_and_sockets_paint(c: HHSelfTest.HHCheck) -> void:
	var parent := Control.new()
	var rid := RenderingServer.canvas_item_create()
	var pt := HHHud.Paint.new(rid)
	for kind in ["arena", "monster", "weapon"]:
		for row in HHRegistry.rows(kind):
			var t := HHLobbyTile.make(parent, Rect2(0, 0, 250, 140), row, kind)
			c.ok(t.thumb != null, "%s tile %s carries its thumbnail" % [kind, row.id])
			t.selected = true
			t.paint(pt)
			t.locked = true
			t.paint(pt)
	var bare := HHLobbyTile.make(parent, Rect2(0, 0, 250, 140), HHRegistry.rows("arena")[0])
	c.eq(bare.thumb, null, "no kind: the tag tile")
	bare.paint(pt)
	var d := HHLobbyDisc.new()
	d.id = "ice"
	d.title = "Ice"
	d.color = HHLook.element_color("ice")
	d.size = Vector2(80, 140)
	c.eq(d.hint(), "", "not hovered: no hint")
	d.hover = true
	d.next_sets = "backup"
	c.eq(d.hint(), "set backup", "hovered: says what the click sets")
	d.slot = "active"
	d.paint(pt)
	d.locked = true
	c.eq(d.hint(), "", "locked: no hint")
	d.paint(pt)
	d.free()
	RenderingServer.free_rid(rid)
	parent.free()
