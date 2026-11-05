class_name DialogueMenu
extends CanvasLayer
## A conversation's choices at the right of the screen: a title, an optional card (a ticket handed
## over...), and numbered lines to say. Keys 1..9 or a click pick one, Esc leaves. While it is open
## the player stands still and the mouse is free. Made on first use, under the tree root:
##   DialogueMenu.open(player, "Passenger", ["Ticket, please.", ...], on_pick, view)
##   DialogueMenu.close_for(who)

const BG := Color(0.07, 0.06, 0.05, 0.86)
const EDGE := Color(0.89, 0.76, 0.49, 0.9)
const CARD_BG := Color(0.93, 0.88, 0.74)
const CARD_INK := Color(0.2, 0.14, 0.09)

var _player: Node
var _owner: Node                   # whatever opened it (the one release_focus is for)
var _on_pick: Callable
var _title: Label
var _card: PanelContainer
var _card_text: RichTextLabel
var _list: VBoxContainer
var _buttons: Array[Button] = []

static func _instance(from: Node) -> DialogueMenu:
	var root := from.get_tree().root
	var m := root.get_node_or_null("DialogueMenu") as DialogueMenu
	if m == null:
		m = DialogueMenu.new()
		m.name = "DialogueMenu"
		root.add_child(m)
	return m

## Opens the menu for `who`; `on_pick(i)` is called with the chosen line's index. The player's eye
## turns to `view` (global) and stays there until it closes.
static func open(who: Node, player: Node, title: String, options: Array, on_pick: Callable, view: Transform3D) -> DialogueMenu:
	var m := _instance(who)
	m._owner = who
	m._player = player
	m._on_pick = on_pick
	m._title.text = title
	m.set_card("")
	m.set_options(options)
	m.visible = true
	if player and player.has_method("focus_on"):
		player.call("focus_on", who, view)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return m

## Closes the menu if `who` has it open.
static func close_for(who: Node) -> void:
	if not who.is_inside_tree():
		return
	var m := who.get_tree().root.get_node_or_null("DialogueMenu") as DialogueMenu
	if m and m._owner == who:
		m.close()

func is_open_for(who: Node) -> bool:
	return visible and _owner == who

func set_title(text: String) -> void:
	_title.text = text

## A card shown above the choices (BBCode; "" hides it).
func set_card(bbcode: String) -> void:
	_card.visible = bbcode != ""
	_card_text.text = bbcode

func set_options(options: Array) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	for i in options.size():
		var b := Button.new()
		b.text = "%d.  %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
		b.add_theme_color_override("font_hover_color", EDGE)
		b.add_theme_color_override("font_pressed_color", EDGE)
		b.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.46))
		b.pressed.connect(_pick.bind(i))
		_list.add_child(b)
		_buttons.append(b)

## Dims a line already asked (it can still be picked again).
func mark_asked(i: int) -> void:
	if i >= 0 and i < _buttons.size():
		_buttons[i].add_theme_color_override("font_color", Color(0.66, 0.63, 0.56))

func close() -> void:
	if not visible:
		return
	visible = false
	var p := _player
	_owner = null
	_player = null
	if p and p.has_method("release_focus"):
		p.call("release_focus")

func _pick(i: int) -> void:
	if _on_pick.is_valid():
		_on_pick.call(i)

func _init() -> void:
	layer = 21
	visible = false
	var anchor := MarginContainer.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Top right, clear of the subtitles at the bottom.
	anchor.add_theme_constant_override("margin_right", 40)
	anchor.add_theme_constant_override("margin_top", 40)
	add_child(anchor)
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(right)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	right.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", EDGE)
	col.add_child(_title)
	_card = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = CARD_BG
	cs.border_color = Color(0.55, 0.42, 0.25)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(3)
	cs.set_content_margin_all(10)
	_card.add_theme_stylebox_override("panel", cs)
	col.add_child(_card)
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.add_theme_font_size_override("normal_font_size", 16)
	_card_text.add_theme_font_size_override("bold_font_size", 16)
	_card_text.add_theme_color_override("default_color", CARD_INK)
	_card.add_child(_card_text)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	col.add_child(_list)
	var hint := Label.new()
	hint.text = "Number keys or click · Esc to leave"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.6, 0.57, 0.5))
	col.add_child(hint)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
		var i := int(k.keycode - KEY_1)
		if i < _buttons.size():
			get_viewport().set_input_as_handled()
			_pick(i)
