extends "res://tools/element_preview.gd"
## Lane IC review renders (H470-H479): the crystal read through the real fight
## (HHFight: sim, bodies, arena view, HHReactionFx, HUD). Needs a window:
##   godot --path . --script res://tools/crystal_read_preview.gd [-- --out design/elements] [--only read,pass,shatter_read]
## Writes:
##   crystal_read.png     the hunter on water (backup fire) beside four crystals:
##                        fire 3 / ice 1 (water breaks it: primed, x7 BREAK),
##                        water 1 / ice 1 (water feeds, fire breaks: x3 W: BREAK),
##                        dark 2 / ice 2 (primed, x6), light 1 / ice 3 (primed, x5);
##                        the HUD hint over the element pair
##   crystal_pass.png     the hunter boxed by six crystals walking out through them
##   shatter_read.png     a x9 Shatter mid-burst (SHATTER x9)
## and crystal_sheet.png.


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out_dir))
	if _want("read"):
		await _read()
	if _want("pass"):
		await _pass()
	if _want("shatter_read"):
		await _shatter_read()
	_sheet_named("crystal_sheet")
	print("crystal_read_preview: done -> ", _abs(out_dir))
	quit(0)


func _sheet_named(key: String) -> void:
	if order.is_empty():
		return
	var cols := 2
	var rows := int(ceil(float(order.size()) / cols))
	var w := SAVE.x / 2
	var h := SAVE.y / 2
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in order.size():
		var img: Image = (shots[order[i]] as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(_abs(out_dir).path_join(key + ".png"))


func _crystallise(f: HHFight, hex: Vector2i, el: String, tier: int, ice: int) -> void:
	_paint(f, [hex], el, tier)
	_tick(f)
	_paint(f, [hex], "ice", ice)
	_tick(f)


func _read() -> void:
	var f := _fight("pond", "swampfang", "water", "fire")
	await process_frame
	_place(f, "swampfang", 7)
	var c := _toward(f, "swampfang", 3)
	var ring := f.sim.arena.ring(c, 1)
	_crystallise(f, c, "fire", 3, 1)
	_crystallise(f, ring[0], "water", 1, 1)
	_crystallise(f, ring[2], "dark", 2, 2)
	_crystallise(f, ring[4], "light", 1, 3)
	await _frames(f, f.sim.arena.surface(c), 11.0, 36.0, 24)
	await _shot("crystal_read")
	f.queue_free()
	await process_frame


func _pass() -> void:
	var f := _fight("pond", "swampfang", "ice", "fire")
	await process_frame
	_place(f, "swampfang", 8)
	var p := f.sim.unit("p1")
	var start: Vector2i = p.hex
	var ring := f.sim.arena.ring(start, 1)
	_paint(f, ring, "fire", 1)
	_tick(f)
	_paint(f, ring, "ice", 1)
	_tick(f)
	var goal := _toward(f, "swampfang", 4)
	_tick(f, { "p1": { "move": goal, "move_pos": f.sim.arena.stand(goal) } })
	for i in 9:
		_tick(f)
	await _frames(f, f.sim.arena.surface(start), 9.0, 38.0, 12)
	await _shot("crystal_pass")
	f.queue_free()
	await process_frame


func _shatter_read() -> void:
	var f := _fight("pond", "swampfang", "thunder", "fire")
	await process_frame
	_place(f, "swampfang", 4)
	var m := f.sim.unit("swampfang")
	var p := f.sim.unit("p1")
	var hx := f.sim.nearest_hex_of(m, p.hex)
	_crystallise(f, hx, "fire", 3, 3)
	var at := f.sim.arena.surface(hx)
	await _frames(f, at, 12.0, 34.0, 12)
	f.sim.events = []
	f.sim.strike(p, m, 220.0, hx, "basic")
	for e in f.sim.events:
		f._consume(e)
	await _frames(f, at, 12.0, 34.0, 8)
	await _shot("shatter_read")
	f.queue_free()
	await process_frame
