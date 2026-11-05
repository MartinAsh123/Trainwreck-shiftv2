extends SceneTree
# Tiles PNGs into one sheet: -- <out.png> <cols> <in1.png> <in2.png> ...
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var cols := int(a[1])
	var files := a.slice(2)
	var first := Image.load_from_file(files[0])
	var w := first.get_width()
	var h := first.get_height()
	var rows := int(ceil(files.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in files.size():
		var img := Image.load_from_file(files[i])
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(a[0])
	quit(0)
