# Images

A local, read-only image viewer built with Quickshell and the same pinned `DCommon` library as Dux Files. It follows DMS's published colours and typography, including live theme changes.

Images is the default viewer for its supported image formats. Run `dimages [IMAGE|FOLDER]` or open an image from the file manager. Without arguments it opens Pictures, falling back to Home if Pictures does not exist.

Images always browses a folder. Opening a file selects it in its containing folder. For example, `dimages ~/Pictures` opens the first supported image there. When the folder has multiple images, a clickable thumbnail strip follows the selection. Browse with Left/Right or the thumbnails. Images are sorted by name, and subfolders are not scanned. Folders without supported images show an empty state.

| Action | Shortcut |
| --- | --- |
| Open image | Ctrl+O |
| Open folder | Ctrl+Shift+O |
| Previous / next | Left / Right |
| Zoom | Mouse wheel or Ctrl++ / Ctrl+- |
| Pan | Drag, or two-finger scroll |
| Fit | F |
| Actual pixels | 1 |
| Rotate the view | R |
| Fullscreen | F11 |
| Leave fullscreen / close | Escape |

Rotation only changes the view. Files are never saved, deleted or modified. At 100%, one image pixel occupies one physical screen pixel, including on fractional-scale displays.

This first version displays still images, including the first frame of GIFs. RAW/HEIC, image editing and tiled decoding are out of scope. Qt's 128 MiB decoded-image allocation limit protects against oversized images.

The package runs the checks in `tests/check.py` during its Nix build, including headless QML integration checks.
