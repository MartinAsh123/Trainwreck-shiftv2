extends SceneTree
# Contact sheet of frames: -- <dir> <out.png> <cols> <frame> <frame> ...
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var dir: String = a[0]
	var cols := int(a[2])
	var frames := a.slice(3)
	var w := 480
	var h := 270
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in frames.size():
		var img := Image.load_from_file(dir + "/f%08d.png" % int(frames[i]))
		img.convert(Image.FORMAT_RGB8)
		img.resize(w, h)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(a[1])
	quit(0)
