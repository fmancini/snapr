# Snapr

A fast menu bar screenshot tool for one Mac user: capture, annotate, read
text, pick colors, and pin images on top of other windows.

## Replaces
Shottr (reference), and the built-in Cmd+Shift+4 screenshot flow.

## Main jobs
1. Capture an area, a window, or the full screen with a global hotkey,
   then copy, save, or edit it.
2. Annotate a capture in an editor: arrows, shapes, text, highlighter,
   blur, step counters, crop, and copy the result.
3. Grab text (OCR/QR) or a pixel color from the screen, and pin a capture
   as a floating always-on-top window. Scrolling capture for long pages.

## Data
- Capture: image, scale, source rect, date, file URL.
- Annotation: kind, geometry, color, line width, text, number.
- Settings: hotkeys, after-capture action, save folder, format, OCR options.
No database in version one: settings in UserDefaults, images on disk.
(decided by the agent)

## Shape
Menu bar extra plus an editor window, preview thumbnail panel, pin panels,
and a full-screen capture overlay. Dock icon only while an editor is open.
macOS 26 or later. Local data. Works offline. No accounts.

## System hooks
Global hotkeys (Carbon), menu bar item, ScreenCaptureKit (Screen
Recording), Vision OCR and barcodes, Accessibility for scrolling capture,
`snapr://` URL scheme, launch at login, clipboard.

## Reference
Shottr 1.9.3 (structure from bundle analysis, `docs/screens/INDEX.md`).

## Look
Native with the system accent color; the editor toolbar and canvas follow
mac-design rules. (decided by the agent)

## Not in version one
- Cloud and S3 upload, link sharing.
- License, purchase, and splash screens.
- Screenshot library/gallery and backdrop social presets (later).
