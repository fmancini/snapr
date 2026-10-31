# Screen index: reference screenshot tool

Source: static analysis of the installed reference app bundle (v1.9.3):
Info.plist, compiled storyboards (`Main`, `Preview`, `Pin`, `Library`,
`Preferences`), and binary strings. No screenshots were taken, so each
section is a screen, not a PNG. Structure and behavior only; no text, logo,
or icon is copied.

## 01-menu-bar-item

Page: status item menu. Reached from: menu bar icon (can be hidden in settings).
Elements: capture commands (Area, Fullscreen, Window, Scrolling, Repeat Area,
Delayed 3s, OCR), Open File, Open From Clipboard, Settings, Quit.
Actions: start any capture; open the editor on an existing image.

## 02-capture-overlay

Page: full-screen frozen overlay. Reached from: area hotkey.
Layout: frozen screenshot of every display, crosshair, live magnifier with
pixel grid, size readout.
Actions: drag to select an area; click a window to pick it; Space toggles
window mode; Esc cancels. After the drag: open editor or show preview
(setting "After Area Crop, show: Editor | Preview").
Notes: snap to objects (edges detected in the image).

## 03-preview-thumbnail

Page: floating thumbnail panel. Reached from: after a capture.
Layout: image, grip to drag the image out (file promise), button row.
Actions: Copy, Save, Edit (Enter), Pin, OCR or QR, Upload, Close.
Dismissal: automatically (click outside) or manually (close button).

## 04-editor-window

Page: main editor window. Reached from: preview Edit, Open File, clipboard.
Layout: top toolbar with tools, canvas with zoom, color and size controls,
bottom status with image size and zoom.
Tools (shortcut): Arrow (A), Rectangle (R), Oval (O), Line (L), Text (T),
Freehand (D), Highlighter (H), Blur/Erase (B), Counter/step (C),
Spotlight (S), Magnifier (M), Backdrop (K), Ruler (1 or 2), Crop.
Other: color picker on hover (shows hex; copy color), Rasterize (merge),
Reset Crop, Zoom In/Out/100%/Fit/Selection, Snap to Objects, Snap to
Similar Objects, Selection Top Left/Bottom Right.
Esc action configurable: copy image and/or save image, then close.

## 05-backdrop-panel

Page: backdrop side panel in the editor. Reached from: Backdrop (K).
Modes: Solid, Colormix (vertical, diagonal, radial, mesh gradients; from/to
colors, reverse, randomize), Image (with blur).
Sliders: Padding, Inset, Outer Radius, Inner Radius, Shadow. Aspect presets
(social sizes). Autocrop, Recenter, Reset, Remove.

## 06-pin-window

Page: borderless always-on-top image window. Reached from: Pin.
Elements: image, hover toolbar (drag, copy, edit, close), zoom label.
Context menu: 50% / 100% / 200%, Semi-transparent, Copy, Edit, Close.
Actions: scroll to zoom, drag to move, Esc closes.

## 07-ocr-result

Page: text recognized from a capture (also QR codes). Reached from: OCR
hotkey (instant, copies to clipboard) or preview "OCR or QR".
Options: primary OCR language, remove line breaks.

## 08-scrolling-capture

Page: overlay over a chosen area while the app auto-scrolls the content
underneath and stitches frames. Needs Accessibility. Variants: down, up
(reverse). Settings: speed, max height.

## 09-library

Page: gallery of past screenshots. Layout: search field, layout picker
(large, medium, small tiles, file list), settings button, status/progress.

## 10-settings-general

Fields: Launch at startup; After screenshot: Copy / Save / Show; After area
crop show: Editor / Preview; Save format: Auto (PNG/JPEG) / PNG; Screenshots
folder; Resize retina screenshots (downscale to 1x); Thumbnail closing;
Window screenshot background: Transparent / Wallpaper / Solid color /
Trim shadow; Scrolling speed and max height.

## 11-settings-hotkeys

Recorders for: Fullscreen, Area, Repeat area, Any window, Active window,
Scrolling, Instant Text/QR Recognition, Show app. Help block on freeing
Cmd+Shift+3/4 from System Settings > Keyboard > Shortcuts > Screenshots.

## 12-settings-advanced

Main window: always on top, prefer 100% zoom, zoom with mouse wheel,
reverse scroll. Esc action: Copy Image, Save Image. Menubar icon: hide.
Notification: none / custom / system. OCR: primary language, line breaks.
Scrolling capture: reverse direction. URL scheme API toggle. Diagnostics.

## 13-settings-upload (dropped)

Upload to own cloud or S3 with presigned links.

## 14-settings-license and splash (dropped)

Purchase, license entry, nag splash.

## Navigation map

- Menu bar item -> capture overlay, editor (open file/clipboard), settings.
- Capture -> preview thumbnail or editor (setting).
- Preview -> editor, pin, OCR, save, copy.
- Editor -> pin, save, copy, backdrop panel.
- Settings tabs: General, Hotkeys, Advanced (Uploading, License dropped).

## Command map

| Command | Default shortcut |
| --- | --- |
| Fullscreen capture | Cmd+Shift+1 |
| Area capture | Cmd+Shift+2 |
| Repeat area capture | (unset) |
| Window capture (any) | (unset) |
| Active window capture | (unset) |
| Scrolling capture | Cmd+Shift+3 |
| Instant OCR / QR | Cmd+Shift+4 |
| Delayed capture 3s | menu only |
| Editor tools | A R O L T D H B C S M K 1/2 |
| Copy image | Cmd+C |
| Save / Save As | Cmd+S / Cmd+Shift+S |
| Pin to screen | Cmd+P |
| Open file / from clipboard | Cmd+O / Cmd+Shift+V |
| Undo / Redo | Cmd+Z / Cmd+Shift+Z |
| Zoom in / out / 100% / fit | Cmd+= / Cmd+- / Cmd+0 / Cmd+9 |
| URL scheme | `snapr://grab/area`, `grab/fullscreen`, `grab/window`, `grab/scrolling`, `grab/repeat`, `ocr` |

## Data model guess

- Capture: image (CGImage, scale), source rect, display, date, file URL.
- Annotation: kind, points/rect, color, line width, text, counter number,
  blur radius, z-order.
- Backdrop: mode, colors, gradient type, image, padding, inset, radii, shadow.
- Pin: capture, frame, zoom, opacity.
- Settings: hotkeys, after-capture actions, save folder, format, downscale,
  window background, scrolling speed/max height, OCR language, line breaks.
- Last area rect (for repeat).
