import AppKit
import SnaprKit

/// The menu bar item. AppKit, not MenuBarExtra: MenuBarExtra(isInserted:)
/// loops forever on macOS 26 when the system hides or shows the item.
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()
    private static let autosaveName = "SnaprMenuBarItem"
    private var item: NSStatusItem?

    /// Shows or hides the item, as Settings say.
    func update() {
        let show = Prefs.defaults.bool(forKey: Prefs.Key.showMenuBarIcon)
        if show, item == nil {
            // Position 0 is the spot nearest the clock, the last to be pushed
            // out by a crowded menu bar or the notch. Set once; after that the
            // system keeps wherever the person drags it with ⌘.
            let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
            if UserDefaults.standard.object(forKey: positionKey) == nil {
                UserDefaults.standard.set(0, forKey: positionKey)
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = Self.autosaveName
            item.button?.image = Self.menuBarImage()
            item.button?.toolTip = "Snapr"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !show, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    /// The app icon's drawing (camera in a viewfinder) as a template image,
    /// on the icon's 1024 canvas, scaled to the menu bar.
    static func menuBarImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let scale = (side - 2) / 560   // the art spans 232...792 on the canvas
            let transform = NSAffineTransform()
            transform.translateX(by: 1, yBy: 1)
            transform.scale(by: scale)
            transform.translateX(by: -232, yBy: -232)

            let path = NSBezierPath()
            // Viewfinder corners: an L of two rounded bars in each corner.
            for (x, y) in [(232.0, 232.0), (620.0, 232.0), (232.0, 728.0), (620.0, 728.0)] {
                path.append(NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 172, height: 64), xRadius: 32, yRadius: 32))
            }
            for (x, y) in [(232.0, 232.0), (728.0, 232.0), (232.0, 620.0), (728.0, 620.0)] {
                path.append(NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 64, height: 172), xRadius: 32, yRadius: 32))
            }
            // Camera, drawn like front.svg: scaled 1.25 around the center.
            let grow = NSAffineTransform()
            grow.translateX(by: 512, yBy: 512)
            grow.scale(by: 1.25)
            grow.translateX(by: -512, yBy: -512)
            let camera = NSBezierPath()
            camera.windingRule = .evenOdd
            camera.append(NSBezierPath(roundedRect: NSRect(x: 362, y: 402, width: 300, height: 220), xRadius: 48, yRadius: 48))
            camera.append(NSBezierPath(ovalIn: NSRect(x: 456, y: 456, width: 112, height: 112)))
            let bump = NSBezierPath(roundedRect: NSRect(x: 432, y: 372, width: 160, height: 56), xRadius: 28, yRadius: 28)
            NSColor.black.setFill()
            transform.transform(path).fill()
            // Filled apart, so the lens stays a hole.
            transform.transform(grow.transform(camera)).fill()
            transform.transform(grow.transform(bump)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snapr"
        return image
    }

    /// Rebuilt on every open, so changed shortcuts show right away.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let hotkeys = HotkeyCenter.shared
        for action in CaptureAction.allCases {
            let entry = NSMenuItem(title: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            entry.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            if let shortcut = hotkeys.shortcut(for: action), let character = shortcut.menuCharacter {
                entry.keyEquivalent = String(character)
                var mask: NSEvent.ModifierFlags = []
                if shortcut.hasCommand { mask.insert(.command) }
                if shortcut.hasShift { mask.insert(.shift) }
                if shortcut.hasOption { mask.insert(.option) }
                if shortcut.hasControl { mask.insert(.control) }
                entry.keyEquivalentModifierMask = mask
            }
            menu.addItem(entry)
            if action == .window || action == .delayed { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open File…"), #selector(openFile)))
        menu.addItem(item(String(localized: "Open From Clipboard"), #selector(openClipboard)))
        let copyLast = item(String(localized: "Copy Last Capture"), #selector(copyLastCapture), key: "c")
        copyLast.keyEquivalentModifierMask = [.command, .option]
        copyLast.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyLast.isEnabled = CaptureCoordinator.shared.lastCapture != nil
        menu.addItem(copyLast)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(item(String(localized: "Snapr Help"), #selector(openHelp), key: "?"))
        menu.addItem(item(String(localized: "About Snapr"), #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Snapr"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = CaptureAction(rawValue: raw) else { return }
        CaptureCoordinator.shared.perform(action)
    }

    @objc private func openFile() { EditorController.openFile() }
    @objc private func openClipboard() { EditorController.openClipboard() }
    @objc private func copyLastCapture() {
        guard let capture = CaptureCoordinator.shared.lastCapture else { return }
        Output.copy(capture)
        HUD.show("Copied", symbol: "checkmark.circle")
    }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func openHelp() { HelpWindow.show() }
    @objc private func openAbout() { AboutPanel.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
