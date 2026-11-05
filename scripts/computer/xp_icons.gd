class_name XPIcons
extends RefCounted
## Small hand-drawn icons for the terminal desktop (drawn into any rect, any size):
## manifest (clipboard), timetable (clock), status (gauge), log (notepad), messages (envelope),
## bin, computer, user, app, friend (a telephone).

static func draw(ci: CanvasItem, kind: String, r: Rect2) -> void:
	var s := r.size.x / 32.0
	var o := r.position
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"manifest":
			ci.draw_rect(Rect2(p.call(6, 4), Vector2(20, 26) * s), Color("8a5a2b"))
			ci.draw_rect(Rect2(p.call(8, 7), Vector2(16, 21) * s), Color.WHITE)
			ci.draw_rect(Rect2(p.call(11, 2), Vector2(10, 5) * s), Color("b8b8b8"))
			for i in 5:
				ci.draw_rect(Rect2(p.call(10, 11 + i * 3.4), Vector2(12, 1.4) * s), Color("4a6fb5"))
		"timetable":
			ci.draw_circle(p.call(16, 16), 13 * s, Color("2a5bd7"))
			ci.draw_circle(p.call(16, 16), 10.5 * s, Color.WHITE)
			ci.draw_line(p.call(16, 16), p.call(16, 8), Color.BLACK, 2.0 * s)
			ci.draw_line(p.call(16, 16), p.call(22, 18), Color.BLACK, 2.0 * s)
			for i in 12:
				var a := TAU * i / 12.0
				ci.draw_circle(p.call(16 + sin(a) * 8.5, 16 - cos(a) * 8.5), 0.8 * s, Color("333"))
		"status":
			ci.draw_rect(Rect2(p.call(3, 6), Vector2(26, 20) * s), Color("3a3a3a"))
			ci.draw_rect(Rect2(p.call(5, 8), Vector2(22, 14) * s), Color("0b3d0b"))
			var pts := PackedVector2Array([p.call(6, 18), p.call(10, 14), p.call(13, 17), p.call(17, 10), p.call(21, 15), p.call(26, 11)])
			ci.draw_polyline(pts, Color("44ff44"), 1.5 * s)
			ci.draw_rect(Rect2(p.call(12, 26), Vector2(8, 3) * s), Color("777"))
		"log":
			ci.draw_rect(Rect2(p.call(6, 3), Vector2(20, 26) * s), Color.WHITE)
			ci.draw_rect(Rect2(p.call(6, 3), Vector2(20, 4) * s), Color("4a8be8"))
			for i in 6:
				ci.draw_line(p.call(9, 11 + i * 3), p.call(23, 11 + i * 3), Color("9bb6e0"), 1.0)
			ci.draw_rect(Rect2(p.call(6, 3), Vector2(20, 26) * s), Color("666"), false, 1.0)
		"messages":
			ci.draw_rect(Rect2(p.call(3, 8), Vector2(26, 18) * s), Color("f4e9c8"))
			ci.draw_polyline(PackedVector2Array([p.call(3, 8), p.call(16, 18), p.call(29, 8)]), Color("a08a50"), 1.5 * s)
			ci.draw_rect(Rect2(p.call(3, 8), Vector2(26, 18) * s), Color("a08a50"), false, 1.0)
		"friend":
			ci.draw_rect(Rect2(p.call(8, 14), Vector2(16, 14) * s), Color("3a3028"))
			ci.draw_circle(p.call(16, 21), 4.5 * s, Color("c9b27a"))
			ci.draw_rect(Rect2(p.call(4, 7), Vector2(24, 5) * s), Color("2a221c"))
			ci.draw_rect(Rect2(p.call(3, 7), Vector2(6, 8) * s), Color("2a221c"))
			ci.draw_rect(Rect2(p.call(23, 7), Vector2(6, 8) * s), Color("2a221c"))
		"bin":
			ci.draw_rect(Rect2(p.call(9, 9), Vector2(14, 19) * s), Color("bfd3e6"))
			ci.draw_rect(Rect2(p.call(7, 6), Vector2(18, 3) * s), Color("8fa9c2"))
			for i in 3:
				ci.draw_line(p.call(12 + i * 4, 12), p.call(12 + i * 4, 25), Color("7d97b0"), 1.0)
		"computer":
			ci.draw_rect(Rect2(p.call(4, 4), Vector2(24, 18) * s), Color("d8d2bd"))
			ci.draw_rect(Rect2(p.call(6, 6), Vector2(20, 14) * s), Color("2a6ad0"))
			ci.draw_rect(Rect2(p.call(10, 23), Vector2(12, 3) * s), Color("b8b19a"))
			ci.draw_rect(Rect2(p.call(6, 26), Vector2(20, 3) * s), Color("d8d2bd"))
		"user":
			ci.draw_rect(Rect2(p.call(1, 1), Vector2(30, 30) * s), Color("e8c86a"))
			ci.draw_circle(p.call(16, 12), 6 * s, Color("2b4b8a"))
			ci.draw_rect(Rect2(p.call(7, 19), Vector2(18, 10) * s), Color("2b4b8a"))
			ci.draw_rect(Rect2(p.call(1, 1), Vector2(30, 30) * s), Color.WHITE, false, 2.0)
		_:
			ci.draw_rect(Rect2(p.call(4, 5), Vector2(24, 22) * s), Color("f0f0f0"))
			ci.draw_rect(Rect2(p.call(4, 5), Vector2(24, 5) * s), Color("2a5bd7"))
			ci.draw_rect(Rect2(p.call(4, 5), Vector2(24, 22) * s), Color("555"), false, 1.0)
