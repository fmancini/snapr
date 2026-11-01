import AppKit
import SnaprKit

/// The menu bar item. AppKit, not MenuBarExtra: MenuBarExtra(isInserted:)
/// loops forever on macOS 26 when the system hides or shows the item.
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()
    private var item: NSStatusItem?

    /// Shows or hides the item, as Settings say.
    func update() {
        let show = Prefs.defaults.bool(forKey: Prefs.Key.showMenuBarIcon)
        if show, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapr")
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

    /// Rebuilt on every open, so changed shortcuts show right away.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
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
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func openHelp() { HelpWindow.show() }
    @objc private func openAbout() { AboutPanel.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
