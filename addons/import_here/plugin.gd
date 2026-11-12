@tool
extends EditorPlugin
## Import Here: adds "Import Files Here..." and "Import Folder Here..." to the
## FileSystem dock's right-click menu. Requires Godot 4.4+ (EditorContextMenuPlugin).

const ImportHereMenu := preload("import_here_menu.gd")

var _menu: EditorContextMenuPlugin


func _enter_tree() -> void:
	_menu = ImportHereMenu.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _menu)


func _exit_tree() -> void:
	if _menu:
		remove_context_menu_plugin(_menu)
		_menu.cleanup()
		_menu = null
