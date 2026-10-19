extends RefCounted
## HHSfx: the manifest maps every fight event the sim raises to a sound.


func test_uses_cover_events(c: HHSelfTest.HHCheck) -> void:
	var s := HHSfx.new()
	s._ready()
	for use in ["detonate", "overheat", "overfreeze", "douse", "gale", "hurt", "stagger", "death", "swing", "step", "heal"]:
		c.ok(s.has_use(use), "use covered: " + use)
	for el in HHFormulas.ELEMENTS:
		c.ok(s.has_use("paint:" + el), "paint use covered: " + el)
	s.play_use("detonate", Vector3.ZERO)                      # headless: a no-op, never an error
	c.ok(true, "play_use is safe headless")
	s.free()
