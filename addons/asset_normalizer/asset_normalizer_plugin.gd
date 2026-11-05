# asset_normalizer_plugin.gd
# Registers the Normalize dock.
@tool
extends EditorPlugin

const _Dock = preload("asset_normalizer_dock.gd")

var _dock: _Dock

func _enter_tree() -> void:
	_dock = _Dock.new()
	_dock.name = "Normalize"
	_dock.undo_redo = get_undo_redo()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
