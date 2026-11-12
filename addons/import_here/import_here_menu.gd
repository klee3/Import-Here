@tool
extends EditorContextMenuPlugin
## Context menu entries for the FileSystem dock.
## Right-click a folder, a file, or empty space -> "Import Files Here..." opens the
## OS file picker (multi-select). The chosen files are simply COPIED into that folder;
## Godot's own import pipeline then detects and imports them (nothing is imported
## manually by this plugin).

const SETTING_LAST_DIR := "import_here/last_directory"

## How Godot is told about the copied files:
## "focus" = send the editor the same "window regained focus" notification the OS
##           sends when you alt-tab back. Godot reacts exactly as if you had left and
##           returned: quick incremental rescan + normal import. (Recommended)
## "scan"  = call EditorFileSystem.scan() (full project scan, slower).
## "none"  = copy only; Godot notices when you next focus the editor window.
const REFRESH_METHOD := "focus"

# [pattern list, description]. "All Files" first so it is the default.
const FILTERS := [
	["*.*", "All Files"],
	["*.png, *.jpg, *.jpeg, *.webp, *.svg, *.bmp, *.tga, *.exr, *.hdr, *.dds, *.ktx", "Images"],
	["*.wav, *.ogg, *.mp3", "Audio"],
	["*.glb, *.gltf, *.fbx, *.obj, *.dae, *.blend", "3D Models"],
	["*.ttf, *.otf, *.woff, *.woff2", "Fonts"],
]

var _dialog: FileDialog
var _target_dir := "res://"


func _popup_menu(_paths: PackedStringArray) -> void:
	add_context_menu_item("Import Files Here...", _on_import_files, _get_icon("Load"))
	add_context_menu_item("Import Folder Here...", _on_import_folder, _get_icon("Folder"))


func cleanup() -> void:
	_free_dialog()


# --- menu callbacks ---------------------------------------------------------

func _on_import_files(paths: Variant) -> void:
	_open_dialog(PackedStringArray(paths), false)


func _on_import_folder(paths: Variant) -> void:
	_open_dialog(PackedStringArray(paths), true)


# --- dialog -----------------------------------------------------------------

func _open_dialog(paths: PackedStringArray, folder_mode: bool) -> void:
	_target_dir = _resolve_target(paths)
	_free_dialog()

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true # OS picker; falls back to Godot's if unsupported
	_dialog.ok_button_text = "Import"
	_dialog.current_dir = _start_dir()

	if folder_mode:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Import folder into %s" % _target_dir
		_dialog.dir_selected.connect(_on_dir_selected)
	else:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_dialog.title = "Import files into %s" % _target_dir
		for f in FILTERS:
			_dialog.add_filter(f[0], f[1])
		_dialog.files_selected.connect(_on_files_selected)

	_dialog.canceled.connect(_free_dialog)
	EditorInterface.get_base_control().add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _free_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _on_files_selected(selected: PackedStringArray) -> void:
	_free_dialog()
	await _wait_one_frame() # don't free/replace the dialog while it is emitting
	_copy_all(selected)


func _on_dir_selected(dir: String) -> void:
	_free_dialog()
	await _wait_one_frame()
	_copy_all(PackedStringArray([dir]))


func _wait_one_frame() -> void:
	await EditorInterface.get_base_control().get_tree().process_frame


# --- target folder ----------------------------------------------------------

## Folder -> that folder. File -> its parent. Empty space -> current dock folder.
func _resolve_target(paths: PackedStringArray) -> String:
	var p := ""
	if paths.size() > 0:
		p = paths[0]
	else:
		p = EditorInterface.get_current_directory()
	if p.is_empty():
		p = "res://"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p)):
		p = p.get_base_dir()
	return p


func _start_dir() -> String:
	var es := EditorInterface.get_editor_settings()
	if es.has_setting(SETTING_LAST_DIR):
		var last := String(es.get_setting(SETTING_LAST_DIR))
		if DirAccess.dir_exists_absolute(last):
			return last
	return OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)


# --- copying (the only thing this plugin does) -------------------------------

func _copy_all(sources: PackedStringArray) -> void:
	if sources.is_empty():
		return

	EditorInterface.get_editor_settings().set_setting(
			SETTING_LAST_DIR, sources[0].trim_suffix("/").get_base_dir())

	var t_start := Time.get_ticks_msec()
	var target_abs := ProjectSettings.globalize_path(_target_dir)
	var copied := 0
	var failed := 0
	var first_path := ""
	for src in sources:
		var dest := _copy_into(src, target_abs)
		if dest.is_empty():
			failed += 1
			continue
		copied += 1
		if first_path.is_empty():
			first_path = _target_dir.path_join(dest.get_file())

	if copied == 0:
		push_warning("[Import Here] Nothing was copied (%d failed)." % failed)
		return

	print("[Import Here] Copied %d item(s) into %s in %d ms%s" % [
			copied, _target_dir, Time.get_ticks_msec() - t_start,
			"" if failed == 0 else " (%d failed, see errors)" % failed])

	# Hand over to Godot: it detects the new files and imports them by itself.
	if REFRESH_METHOD == "none":
		return
	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_select_path.bind(first_path), CONNECT_ONE_SHOT)
	if REFRESH_METHOD == "scan":
		fs.scan()
	else:
		# The file picker closing already triggered Godot's focus-in rescan *before*
		# we copied, so replay that notification now that the files exist.
		EditorInterface.get_base_control().get_tree().notification(
				MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)


## Copies a file or folder into target_abs. Returns the new absolute path, or "".
func _copy_into(src: String, target_abs: String) -> String:
	src = src.simplify_path()
	var is_dir := DirAccess.dir_exists_absolute(src)

	if is_dir:
		# Don't copy a folder into itself.
		if (target_abs.trim_suffix("/") + "/").begins_with(src.trim_suffix("/") + "/"):
			push_warning("[Import Here] Skipped %s (target is inside it)." % src)
			return ""
	elif not FileAccess.file_exists(src):
		push_warning("[Import Here] Not found: %s" % src)
		return ""

	var item_name := src.trim_suffix("/").get_file()
	if item_name.is_empty():
		return ""

	var dest := _unique_path(target_abs, item_name, is_dir)
	var err: Error = _copy_dir(src, dest) if is_dir else DirAccess.copy_absolute(src, dest)
	if err != OK:
		push_error("[Import Here] Failed to copy %s (%s)" % [src, error_string(err)])
		return ""
	return dest


## Never overwrites: "tree.png" -> "tree_1.png" -> "tree_2.png" ...
func _unique_path(dir_abs: String, item_name: String, is_dir: bool) -> String:
	var candidate := dir_abs.path_join(item_name)
	var stem := item_name if is_dir else item_name.get_basename()
	var ext := "" if is_dir else item_name.get_extension()
	var i := 1
	while FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
		var new_name := "%s_%d" % [stem, i]
		if not ext.is_empty():
			new_name += "." + ext
		candidate = dir_abs.path_join(new_name)
		i += 1
	return candidate


func _copy_dir(src: String, dest: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dest)
	if err != OK:
		return err
	for f in DirAccess.get_files_at(src):
		err = DirAccess.copy_absolute(src.path_join(f), dest.path_join(f))
		if err != OK:
			return err
	for d in DirAccess.get_directories_at(src):
		err = _copy_dir(src.path_join(d), dest.path_join(d))
		if err != OK:
			return err
	return OK


# --- helpers ----------------------------------------------------------------

func _select_path(path: String) -> void:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		EditorInterface.select_file(path)


func _get_icon(icon_name: String) -> Texture2D:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme and editor_theme.has_icon(icon_name, "EditorIcons"):
		return editor_theme.get_icon(icon_name, "EditorIcons")
	return null
