# asset_normalizer_dock.gd
# Dock UI: pick a model + preset, tweak, create the prefab, optionally plug it into the car.
@tool
extends VBoxContainer

const N = preload("asset_normalizer.gd")

var undo_redo: EditorUndoRedoManager

var _models: Array[String] = []
var _preset_keys: Array = N.PRESETS.keys()

var _model_list: OptionButton
var _preset: OptionButton
var _forward: OptionButton
var _fit_axis: OptionButton
var _fit_size: SpinBox
var _pivot: OptionButton
var _collision: OptionButton
var _out_path: LineEdit
var _assign: CheckBox
var _report: RichTextLabel

# ————— lifecycle —————

func _ready() -> void:
	_build_ui()
	_refresh_models()
	_on_preset_selected(0)

# ————— ui —————

func _build_ui() -> void:
	add_theme_constant_override("separation", 6)

	_add_label("Source model (res://TripoModels)")
	var row := HBoxContainer.new()
	add_child(row)
	_model_list = OptionButton.new()
	_model_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_model_list.clip_text = true
	_model_list.item_selected.connect(func(_i: int) -> void: _update_out_path())
	row.add_child(_model_list)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_refresh_models)
	row.add_child(refresh)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)

	_preset = _add_option(grid, "Preset", _preset_keys.map(func(k: String) -> String: return N.PRESETS[k].label))
	_preset.item_selected.connect(_on_preset_selected)
	_forward = _add_option(grid, "Model faces", ["+Z (Tripo default)", "-Z", "+X", "-X"])
	_fit_axis = _add_option(grid, "Fit axis", ["Width (X)", "Height (Y)", "Depth (Z)", "Longest"])

	_add_label("Fit size (m)", grid)
	_fit_size = SpinBox.new()
	_fit_size.min_value = 0.01
	_fit_size.max_value = 100.0
	_fit_size.step = 0.01
	_fit_size.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(_fit_size)

	_pivot = _add_option(grid, "Pivot", ["Bottom center", "Top center", "Center"])
	_collision = _add_option(grid, "Collision", ["None", "Box", "Convex", "Trimesh (static)"])

	_add_label("Output")
	_out_path = LineEdit.new()
	add_child(_out_path)

	_assign = CheckBox.new()
	_assign.text = "Assign to PassengerCar in open scene"
	_assign.button_pressed = true
	add_child(_assign)

	var create := Button.new()
	create.text = "Create prefab"
	create.pressed.connect(_on_create)
	add_child(create)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.fit_content = true
	_report.selection_enabled = true
	_report.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_report)

func _add_label(text: String, parent: Node = self) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)

func _add_option(grid: GridContainer, label: String, items: Array) -> OptionButton:
	_add_label(label, grid)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = SIZE_EXPAND_FILL
	for item in items:
		ob.add_item(item)
	grid.add_child(ob)
	return ob

# ————— handlers —————

func _refresh_models() -> void:
	_models = N.find_models()
	_model_list.clear()
	for m in _models:
		_model_list.add_item(m.trim_prefix("res://TripoModels/"))
	if _models.is_empty():
		_model_list.add_item("(no models yet — import one from Tripo)")
		_model_list.disabled = true
	else:
		_model_list.disabled = false
	_update_out_path()

func _on_preset_selected(index: int) -> void:
	var p: Dictionary = N.PRESETS[_preset_keys[index]]
	_fit_axis.select(p.fit_axis)
	_fit_size.value = p.fit_size
	_pivot.select(p.pivot)
	_collision.select(p.collision)
	_update_out_path()

func _update_out_path() -> void:
	var source := _selected_model()
	if source.is_empty():
		_out_path.text = ""
		return
	_out_path.text = N.default_out_path(source, _preset_key())

func _on_create() -> void:
	var source := _selected_model()
	if source.is_empty():
		_show_error("Pick a source model first.")
		return
	var preset: Dictionary = N.PRESETS[_preset_key()]
	var options := {
		"source": source,
		"out_path": _out_path.text.strip_edges(),
		"forward": _forward.selected,
		"fit_axis": _fit_axis.selected,
		"fit_size": _fit_size.value,
		"pivot": _pivot.selected,
		"collision": _collision.selected,
		"tri_budget": preset.tri_budget,
		"max_width": preset.max_width,
		"max_depth": preset.max_depth,
	}
	var result := N.normalize(options)
	if not result.ok:
		_show_error(result.error)
		return

	EditorInterface.get_resource_filesystem().update_file(result.out_path)
	var assigned := ""
	if _assign.button_pressed and not String(preset.slot).is_empty():
		assigned = _assign_to_car(result.out_path, preset.slot)
	_show_result(result, assigned)

func _assign_to_car(prefab_path: String, slot: String) -> String:
	var car := _find_car(EditorInterface.get_edited_scene_root())
	if car == null:
		return ""
	var prefab := ResourceLoader.load(prefab_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	undo_redo.create_action("Assign %s" % slot)
	undo_redo.add_do_property(car, slot, prefab)
	undo_redo.add_undo_property(car, slot, car.get(slot))
	undo_redo.commit_action()
	return "%s.%s" % [car.name, slot]

# ————— helpers —————

func _selected_model() -> String:
	if _models.is_empty() or _model_list.selected < 0:
		return ""
	return _models[_model_list.selected]

func _preset_key() -> String:
	return _preset_keys[maxi(_preset.selected, 0)]

func _find_car(node: Node) -> PassengerCar:
	if node == null:
		return null
	if node is PassengerCar:
		return node
	for child in node.get_children():
		var found := _find_car(child)
		if found:
			return found
	return null

func _show_error(msg: String) -> void:
	_report.text = "[color=#ff7070]%s[/color]" % msg

func _show_result(result: Dictionary, assigned: String) -> void:
	var s: Vector3 = result.size
	var lines: Array[String] = [
		"[color=#8fd18f]Saved[/color] %s" % result.out_path,
		"Size: %.2f W × %.2f H × %.2f D m" % [s.x, s.y, s.z],
		"Scale applied: ×%.3f" % result.scale,
		"Triangles: %d" % result.tris,
	]
	if not assigned.is_empty():
		lines.append("Assigned to %s" % assigned)
	for w in result.warnings:
		lines.append("[color=#ffcc66]⚠ %s[/color]" % w)
	_report.text = "\n".join(lines)
