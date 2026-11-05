class_name PauseMenu
extends CanvasLayer
## Esc during the shift: the tree pauses (the train, the passengers and the scares all stop) and a
## small timetable card offers Resume, Settings and Back to the main menu. Esc again resumes. The
## mouse comes back as it was (captured while walking, free at the end-of-day summary).
## Added by the player controller on its first frame (PauseMenu.attach), so no scene needs it.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

var _dim: ColorRect
var _card: PanelContainer
var _settings: SettingsPanel
var _mouse_before := Input.MOUSE_MODE_CAPTURED

static func attach(from: Node) -> PauseMenu:
	var root := from.get_tree().root
	var m := root.get_node_or_null("PauseMenu") as PauseMenu
	if m == null:
		m = PauseMenu.new()
		m.name = "PauseMenu"
		root.add_child.call_deferred(m)
	return m

func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.015, 0.01, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = MenuStyle.panel()
	center.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.add_child(v)
	var t := MenuStyle.label("Shift paused", 38, MenuStyle.EDGE, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(MenuStyle.rule())
	v.add_child(MenuStyle.button("Resume", resume))
	v.add_child(MenuStyle.button("Settings", _open_settings))
	v.add_child(MenuStyle.button("Back to the main menu", _to_menu))
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	center.add_child(_settings)

# The scene is leaving (a new day, or the main menu): never leave the tree paused behind it.
func _ready() -> void:
	get_tree().scene_changed.connect(func() -> void:
		if visible:
			resume())

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path == MAIN_MENU:
		return
	get_viewport().set_input_as_handled()
	if not visible:
		open()
	elif _settings.visible:
		_close_settings()
	else:
		resume()

func open() -> void:
	_mouse_before = Input.mouse_mode
	visible = true
	_card.visible = true
	_settings.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_card.get_child(0).get_child(2) as Button).grab_focus.call_deferred()

func resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before

func is_open() -> bool:
	return visible

func _open_settings() -> void:
	_card.visible = false
	_settings.visible = true

func _close_settings() -> void:
	_settings.visible = false
	_card.visible = true

func _to_menu() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)
