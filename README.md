# Import Here (Godot 4.4+)

Right-click in the **FileSystem dock** -> **Import Files Here...** / **Import Folder Here...**

- Right-click a **folder** -> imports into that folder
- Right-click a **file** -> imports into that file's folder
- Right-click **empty space** -> imports into the folder currently shown

The OS file picker opens (multi-select supported) and the chosen files are **copied**
into the folder. Godot's own scan then detects and imports them; the plugin does no
importing itself. Existing files are never overwritten: `tree.png` becomes `tree_1.png`.
The picker remembers the last folder you used (defaults to Downloads).

After copying, the plugin sends the editor the same "window regained focus"
notification the OS sends when you alt-tab back, so Godot rescans and imports right
away. You can change this with `REFRESH_METHOD` at the top of `import_here_menu.gd`
(`"focus"` default, `"scan"` for a full scan, `"none"` for copy only).

## Install

1. Copy the `addons/import_here` folder into your project's `addons/` folder.
2. **Project -> Project Settings -> Plugins** -> tick **Import Here**.

Needs Godot **4.4 or newer** (uses `EditorContextMenuPlugin`).
