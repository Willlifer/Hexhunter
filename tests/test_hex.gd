extends RefCounted
## HHHex: the odd-r math.


func test_distance_and_neighbors(c: HHSelfTest.HHCheck) -> void:
	var o := Vector2i(0, 0)
	c.eq(HHHex.distance(o, o), 0, "self distance")
	var ns := HHHex.neighbors(o)
	c.eq(ns.size(), 6, "six neighbours")
	for n in ns:
		c.eq(HHHex.distance(o, n), 1, "neighbour at 1: %s" % n)
	c.eq(HHHex.distance(Vector2i(0, 0), Vector2i(3, 3)), 5, "odd-r distance (0,0)->(3,3)")
	c.eq(HHHex.area(o, 2).size(), 19, "area r2 = 19")
	c.eq(HHHex.ring(o, 2).size(), 12, "ring r2 = 12")


func test_cube_roundtrip(c: HHSelfTest.HHCheck) -> void:
	for col in range(-4, 5):
		for row in range(-4, 5):
			var h := Vector2i(col, row)
			c.eq(HHHex.to_offset(HHHex.to_cube(h)), h, "cube roundtrip %s" % h)


func test_world_roundtrip(c: HHSelfTest.HHCheck) -> void:
	for col in range(-6, 7):
		for row in range(-6, 7):
			var h := Vector2i(col, row)
			var w := HHHex.to_world(h, 1.0)
			c.eq(HHHex.from_world(w, 1.0), h, "world roundtrip %s" % h)
	var w := HHHex.to_world(Vector2i(1, 1), 1.0)
	c.near(w.x, sqrt(3.0) * 1.5, 1e-5, "odd row shifts half a hex")
	c.near(w.y, 1.5, 1e-5, "row spacing 1.5")


func test_line_and_ray(c: HHSelfTest.HHCheck) -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(4, 0)
	var l := HHHex.line(a, b)
	c.eq(l.size(), 5, "line length = distance + 1")
	c.eq(l[0], a, "line starts at a")
	c.eq(l[-1], b, "line ends at b")
	var r := HHHex.ray(a, b, 3)
	c.eq(r.size(), 3, "ray of 3")
	c.eq(r[2], Vector2i(3, 0), "ray heads along the row")
	c.eq(HHHex.trail(a, b).size(), 4, "trail excludes origin")
	c.eq(HHHex.fringe([a], 1).size(), 7, "fringe r1 of one hex = 7")
