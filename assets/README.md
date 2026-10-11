# AXE GOKZ icon

`reference-axe.jpg` is the JPEG supplied by the user. `axe-gokz.png` is the
transparent RGBA master, created with the built-in imagegen tool. `axe-gokz.ico`
contains 32-bit icons at 16, 24, 32, 48, 64, 128 and 256 pixels and is used for
the executable, window title bar, and installer header.

Regenerate the ICO after changing the PNG:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\assets\export-icon.ps1
```

The script only converts the format and creates Windows icon sizes. It preserves
the alpha channel; no additional image generation dependency is needed to build.

Generation prompt:

> Use case: background-extraction. Asset type: Windows application icon for AXE GOKZ Resource Installer. Edit target: the supplied JPEG of a pixel-art diamond axe. Remove only the white JPEG background and edge compression artifacts; keep the axe silhouette, diagonally angled brown/purple handle toward bottom left, cyan/teal blue pixel blade at top right, dark navy outline, square pixel geometry and original colors. Reconstruct crisp clean square pixel edges from the low-resolution JPEG. Center the entire axe on a square transparent RGBA canvas with a small transparent margin so the whole silhouette remains visible at 16 through 256 pixels. Preserve its pixel-art identity, do not add text, gradients, shadows, border, badge, tiles or a background. Actual transparent background, not a checkerboard image. Output a single isolated high-resolution icon.
