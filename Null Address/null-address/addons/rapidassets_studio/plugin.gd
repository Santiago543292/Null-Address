@tool
extends EditorPlugin

# Registers the Rapid Assets Studio dock in the Godot editor.

var _dock: Control

func _enter_tree() -> void:
	_dock = preload("res://addons/rapidassets_studio/studio_dock.gd").new()
	_dock.name = "Rapid Assets"
	# Hand the dock a reference to the editor interface so it can rescan the
	# FileSystem after importing assets (works across Godot 4.0–4.4).
	if _dock.has_method("set_editor_interface"):
		_dock.set_editor_interface(get_editor_interface())
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
