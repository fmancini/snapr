# Snapr stories

Snapshot pages: `menu`, `overlay`, `preview`, `editor`, `pin`, `ocr`,
`settings-general`, `settings-hotkeys`, `settings-advanced`.

## M1 Core capture loop

### S-001 Menu bar item with capture commands
As the user, I click the menu bar icon and pick a capture command.
Screens: 01-menu-bar-item
Acceptance:
- [snap] Menu lists Area, Fullscreen, Window, Scrolling, Repeat Area,
  Delayed (3s), Capture Text, Pick Color, Open File, Open From Clipboard,
  Settings, Quit, each with its shortcut.
- [manual] The app has no Dock icon until an editor window opens.
UX: menu items are verbs ("Capture Area"). Settings opens with Cmd+,.
Status: todo

### S-002 Grant Screen Recording at first capture
As the user, the first capture asks for Screen Recording and tells me why.
Screens: settings-advanced
Acceptance:
- [manual] Without permission, an alert explains and opens System Settings.
- [snap] Settings shows the state of Screen Recording and Accessibility.
UX: one line: "Snapr needs Screen Recording to take screenshots."
Status: todo

### S-003 Capture an area
As the user, I press Cmd+Shift+2, drag a rectangle, and get a capture.
Screens: 02-capture-overlay
Depends: S-002
Acceptance:
- [manual] The overlay freezes all displays, shows a crosshair, a magnifier
  with the pixel grid, and the selection size in points.
- [manual] Esc cancels; Space switches to window pick mode.
- [unit] Selection rect maps to image pixels at the display scale.
UX: size label sits under the cursor, never off screen.
Status: todo

### S-004 Capture fullscreen and a window
As the user, I capture the screen under the cursor, or click a window.
Screens: 02-capture-overlay
Depends: S-003
Acceptance:
- [manual] Cmd+Shift+1 captures the display under the mouse.
- [manual] In window mode the hovered window is highlighted; click captures
  it with a transparent background and shadow.
Status: todo

### S-005 After-capture preview
As the user, a thumbnail appears after a capture with Copy, Save, Edit,
Pin, and Text actions, and I can drag the image out.
Screens: 03-preview-thumbnail, preview
Depends: S-003
Acceptance:
- [snap] Thumbnail panel in the bottom corner, buttons with tooltips.
- [manual] Dragging the thumbnail drops a PNG in Finder or another app.
- [manual] It closes on Esc, on its close button, or after 8 s idle.
Status: todo

### S-006 Copy and save automatically
As the user, I choose what happens after a capture: copy, save, show.
Screens: settings-general
Acceptance:
- [unit] Save names files `Snapr YYYY-MM-DD at HH.mm.ss.png` in the folder.
- [snap] General tab: after-capture checkboxes, folder, format, 1x downscale.
Status: todo

### S-007 Global hotkeys
As the user, I change every capture shortcut in Settings.
Screens: 11-settings-hotkeys, settings-hotkeys
Acceptance:
- [snap] Recorders for Area, Fullscreen, Window, Scrolling, Repeat, Text,
  Color.
- [manual] A new shortcut works right away, without a restart.
UX: help note on freeing Cmd+Shift+3/4 in System Settings.
Status: todo

## M2 Editor

### S-010 Open the editor
As the user, I open a capture, a file, or the clipboard in an editor window.
Screens: 04-editor-window, editor
Depends: S-005
Status: todo

### S-011 Draw shapes
Arrow (A), Rectangle (R), Oval (O), Line (L), Freehand (D), Highlighter (H)
with color and width. Select, move, delete, undo/redo.
Screens: editor
Acceptance:
- [snap] Toolbar shows the tools with shortcut tooltips.
- [unit] Undo removes the last annotation; redo restores it.
Status: todo

### S-012 Text, counter, blur, spotlight
Text (T), Counter (C) numbering 1, 2, 3, Blur/pixelate (B), Spotlight (S)
dims everything outside a rectangle.
Screens: editor
Status: todo

### S-013 Crop and export
Crop tool, Reset Crop; Cmd+C copies the flattened image; Cmd+S saves.
Esc copies and closes (setting).
Screens: editor
Acceptance:
- [unit] Rendering composes annotations at full pixel resolution.
Status: todo

### S-014 Zoom
Zoom in, out, 100%, fit; pinch and Cmd+scroll.
Screens: editor
Status: todo

## M3 Tools

### S-020 Capture text and QR codes
As the user, I press Cmd+Shift+4, select an area, and its text is copied.
Screens: 07-ocr-result, ocr
Acceptance:
- [manual] A QR code in the area copies its payload instead.
- [manual] A HUD says "Copied N lines" or "No text found".
- [unit] Line-break removal joins lines with spaces.
Status: todo

### S-021 Pick a pixel color
As the user, I press Cmd+Shift+C, hover with the magnifier, click, and the
hex color is copied.
Screens: overlay
Status: todo

### S-022 Pin a capture
As the user, I pin a capture as a borderless floating window.
Screens: 06-pin-window, pin
Acceptance:
- [manual] Drag to move, scroll to zoom, double click opens the editor,
  Esc or the close button closes it. Context menu: 50/100/200%,
  semi-transparent, copy, edit, close.
Status: todo

### S-023 Repeat and delayed capture
Repeat the last area; capture after 3 seconds.
Screens: 01-menu-bar-item
Status: todo

### S-024 Scrolling capture
As the user, I select an area, Snapr scrolls the content beneath and
stitches the frames into one tall image.
Screens: 08-scrolling-capture
Acceptance:
- [unit] Stitching finds the overlap between two frames and joins them.
- [manual] Esc or a click stops; max height from settings.
Status: todo

## M4 System and polish

### S-030 URL scheme
`snapr://grab/area|fullscreen|window|scrolling|repeat`, `snapr://ocr`,
`snapr://color`.
Status: todo

### S-031 Launch at login, hide menu bar icon
Screens: settings-advanced
Status: todo

### S-032 App icon
Status: todo

### S-033 Help window
As the user, I open Help > Snapr Help (⌘?) or Snapr Help in the menu bar
item and read how every capture, tool, and setting works.
Screens: help-<topic>
Acceptance:
- [snap] Eight topics in a sidebar: Getting Started, Capturing, Editor,
  Preview and Pin, Text and Color, Scrolling Capture, Automation,
  Troubleshooting. English and Spanish.
- [snap] Shortcuts on the pages match Settings > Shortcuts.
Status: done

### S-034 About and credits
As the user, About Snapr shows the version and credits: created by
Felipe Mancini.
Screens: about
Status: done

## Later

- Backdrop panel (gradients, padding, radii, shadow, aspect presets).
  Screens: 05-backdrop-panel
- Ruler and Magnifier annotation tools.
- Screenshot library. Screens: 09-library
- Snap to objects.

## Dropped

- Cloud and S3 upload. Screens: 13-settings-upload
- License, purchase, nag splash. Screens: 14-settings-license
- Telemetry and diagnostics.
