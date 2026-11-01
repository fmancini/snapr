import AppKit
import SnaprKit
import SwiftUI

// Snapr
//   Snapr                      the app (menu bar only, editor windows on demand)
//   APP_STORE=<file> Snapr     test run: settings go to a throwaway defaults suite
//   APP_SNAPSHOT=<dir> Snapr   save PNGs of the editor, preview, pin, and every Settings tab in light and dark, then quit
//   Snapr --selftest           run the self-test and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Snapr      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 Snapr           draw the 8 pt grid and the layout probes over the window

@main
struct SnaprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// Windows are AppKit (StatusItem.swift, EditorWindow.swift, SettingsView.swift).
    /// This empty scene only carries the main menu commands.
    var body: some Scene {
        Settings { EmptyView() }
            .commands { AppCommands() }
    }
}

/// The main menu while an editor or Settings is in front.
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Snapr") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Button("Snapr Help") { HelpWindow.show() }
                .keyboardShortcut("?")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.show() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Open File…") { EditorController.openFile() }
                .keyboardShortcut("o")
            Button("Open From Clipboard") { EditorController.openClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Image") { EditorController.key?.save() }
                .keyboardShortcut("s")
            Button("Save Image As…") { EditorController.key?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        CommandGroup(replacing: .printItem) {
            Button("Pin to Screen") { EditorController.key?.pin() }
                .keyboardShortcut("p")
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Image") { EditorController.key?.copyImage() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Text in Image") { EditorController.key?.copyText() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandMenu("Tools") {
            ForEach(Tool.allCases) { tool in
                Button("\(tool.title) (\(String(tool.key).uppercased()))") { EditorController.key?.tool = tool }
            }
            Divider()
            Button("Delete Selection") { EditorController.key?.deleteSelection() }
            Button("Reset Crop") { EditorController.key?.resetCrop() }
                .keyboardShortcut("r", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { EditorController.key?.zoom(.in) }
                .keyboardShortcut("=")
            Button("Zoom Out") { EditorController.key?.zoom(.out) }
                .keyboardShortcut("-")
            Button("Actual Size") { EditorController.key?.zoom(.actual) }
                .keyboardShortcut("0")
            Button("Zoom to Fit") { EditorController.key?.zoom(.fit) }
                .keyboardShortcut("9")
            Divider()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.prepare()
        HotkeyCenter.shared.registerAll()
        if !Snapshot.requested && !SelfTest.requested { StatusItemController.shared.update() }
        Activation.update()
        if Snapshot.requested {
            Snapshot.run()
        } else if SelfTest.requested {
            SelfTest.run()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app again (Finder, Spotlight) shows Settings, the way
    /// back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindow.show() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "snapr" {
                CaptureCoordinator.shared.handle(url: url)
            } else if url.isFileURL {
                EditorController.open(file: url)
            }
        }
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Snapr lives in the menu bar. It shows a Dock icon and a main menu only
/// while an editor, Settings, or Help window is open.
enum Activation {
    static func update() {
        let needsDock = NSApp.windows.contains { window in
            window.isVisible && (window.windowController is EditorWindowController || window.identifier == SettingsWindow.id || window.identifier == HelpWindow.id)
        }
        let policy: NSApplication.ActivationPolicy = needsDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    static func bringToFront(_ window: NSWindow) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Test runs keep their settings away from the real ones.
enum Store {
    /// True when APP_STORE is set (tests, snapshots).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }
}
