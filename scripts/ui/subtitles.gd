class_name Subtitles
extends CanvasLayer
## Spoken lines at the bottom of the screen ("Speaker: text"), one per speaker, the newest lowest;
## each fades out when its time is up. Made on first use, under the tree root:
##   Subtitles.show_line(node, "Old gentleman", "A long night to Kamenný Most.", 3.5)
## The text size follows Settings.subtitle_size, live.

const NAME_COLOR := "#e2c27d"
const MAX_LINES := 3

var _box: VBoxContainer
var _lines := {}                    # speaker -> RichTextLabel

static func show_line(from: Node, speaker: String, text: String, seconds: float) -> void:
	var root := from.get_tree().root
	var s := root.get_node_or_null("Subtitles") as Subtitles
	if s == null:
		s = Subtitles.new()
		s.name = "Subtitles"
		root.add_child.call_deferred(s)
		s._add.call_deferred(speaker, text, seconds)
		return
	s._add(speaker, text, seconds)

func _init() -> void:
	layer = 20
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_right", 160)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 6)
	margin.add_child(_box)

func _ready() -> void:
	var st := get_node_or_null("/root/Settings")
	if st:
		st.changed.connect(func(key: String) -> void:
			if key == "subtitle_size":
				for l: RichTextLabel in _box.get_children():
					l.add_theme_font_size_override("normal_font_size", _size()))

func _size() -> int:
	var st := get_node_or_null("/root/Settings")
	return int(st.get("subtitle_size")) if st else 24

func _add(speaker: String, text: String, seconds: float) -> void:
	if _lines.has(speaker) and is_instance_valid(_lines[speaker]):
		(_lines[speaker] as Node).queue_free()
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", _size())
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var who := "[color=%s]%s:[/color] " % [NAME_COLOR, speaker] if speaker != "" else ""
	l.text = "[center]%s%s[/center]" % [who, text.replace("[", "[lb]")]
	_box.add_child(l)
	_lines[speaker] = l
	while _box.get_child_count() > MAX_LINES:
		_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(maxf(seconds, 1.0))
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
