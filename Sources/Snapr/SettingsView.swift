import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window: toolbar tabs, one grouped Form per tab, sized to content.
enum SettingsWindow {
    static let id = NSUserInterfaceItemIdentifier("settings")
    private static var controller: NSWindowController?
    private static var tabs: NSTabViewController?

    static var window: NSWindow? { controller?.window }

    static func show(_ tab: SettingsTab? = nil) {
        if controller == nil { build() }
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) { tabs?.selectedTabViewItemIndex = index }
        guard let window = controller?.window else { return }
        if !window.isVisible { window.center() }
        Activation.bringToFront(window)
    }

    private static func build() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: SettingsPage(tab: tab).themed())
            hosting.sizingOptions = .preferredContentSize
            hosting.title = tab.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.identifier = id
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { Activation.update() } }
        }
        self.tabs = tabs
        controller = NSWindowController(window: window)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, shortcuts, advanced, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .shortcuts: String(localized: "Shortcuts")
        case .advanced: String(localized: "Advanced")
        case .appearance: String(localized: "Appearance")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .shortcuts: "keyboard"
        case .advanced: "slider.horizontal.3"
        case .appearance: "paintpalette"
        }
    }
}

private struct SettingsPage: View {
    let tab: SettingsTab

    var body: some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .capture: CaptureSettings()
            case .shortcuts: ShortcutSettings()
            case .advanced: AdvancedSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
        .noInitialFocus()
    }
}

struct GeneralSettings: View {
    @AppStorage(Prefs.Key.afterCopy, store: Prefs.defaults) private var afterCopy = true
    @AppStorage(Prefs.Key.afterSave, store: Prefs.defaults) private var afterSave = false
    @AppStorage(Prefs.Key.afterShow, store: Prefs.defaults) private var afterShow = Prefs.AfterShow.preview.rawValue
    @AppStorage(Prefs.Key.previewAutoClose, store: Prefs.defaults) private var autoClose = true
    @AppStorage(Prefs.Key.showMenuBarIcon, store: Prefs.defaults) private var showIcon = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.current
    private let startLanguage = AppLanguage.current

    var body: some View {
        Section("After a capture") {
            Toggle("Copy to the clipboard", isOn: $afterCopy)
            Toggle("Save to the screenshots folder", isOn: $afterSave)
            Picker("Then show", selection: $afterShow) {
                ForEach(Prefs.AfterShow.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Close the preview after 8 seconds", isOn: $autoClose)
                .disabled(afterShow != Prefs.AfterShow.preview.rawValue)
        }
        Section("App") {
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: language) { _, new in new.apply() }
            if language != startLanguage {
                LabeledContent {
                    Button("Restart Snapr") { AppLanguage.relaunch() }
                } label: {
                    Text("Snapr uses the new language after a restart.")
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Show in the menu bar", isOn: $showIcon)
                .onChange(of: showIcon) { StatusItemController.shared.update() }
            if !showIcon {
                Text("Open Snapr again from Finder or Spotlight to reach Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CaptureSettings: View {
    @AppStorage(Prefs.Key.saveFolder, store: Prefs.defaults) private var folder = URL.desktopDirectory.path
    @AppStorage(Prefs.Key.saveFormat, store: Prefs.defaults) private var format = Prefs.SaveFormat.png.rawValue
    @AppStorage(Prefs.Key.downscale, store: Prefs.defaults) private var downscale = false
    @AppStorage(Prefs.Key.windowShadow, store: Prefs.defaults) private var shadow = true
    @AppStorage(Prefs.Key.scrollMaxHeight, store: Prefs.defaults) private var maxHeight = 20000

    var body: some View {
        Section("Saving") {
            LabeledContent("Screenshots folder") {
                HStack(spacing: Space.sm) {
                    Text(URL(fileURLWithPath: folder).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(folder)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Picker("Format", selection: $format) {
                ForEach(Prefs.SaveFormat.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle("Save Retina captures at 1x size", isOn: $downscale)
        }
        Section("Windows") {
            Toggle("Keep the window shadow", isOn: $shadow)
        }
        Section("Scrolling capture") {
            Stepper(value: $maxHeight, in: 2000...60000, step: 2000) {
                LabeledContent("Maximum height", value: "\(maxHeight) px")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

struct ShortcutSettings: View {
    var body: some View {
        Section {
            ForEach(CaptureAction.allCases) { action in
                LabeledContent {
                    ShortcutRecorder(action: action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("To use ⇧⌘3 or ⇧⌘4, first turn them off in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { HotkeyCenter.shared.resetAll() }
            }
        }
    }
}

struct AdvancedSettings: View {
    @AppStorage(Prefs.Key.escCopies, store: Prefs.defaults) private var escCopies = true
    @AppStorage(Prefs.Key.ocrKeepBreaks, store: Prefs.defaults) private var keepBreaks = true
    @AppStorage(Prefs.Key.ocrLanguage, store: Prefs.defaults) private var language = "auto"
    @AppStorage(Prefs.Key.urlScheme, store: Prefs.defaults) private var urlScheme = true
    @State private var screenRecording = Permissions.screenRecording
    @State private var accessibility = Permissions.accessibility
    private let languages = OCR.languages

    var body: some View {
        Section("Editor") {
            Toggle("Esc copies the image and closes the editor", isOn: $escCopies)
        }
        Section("Text recognition") {
            Picker("Language", selection: $language) {
                Text("Automatic").tag("auto")
                Divider()
                ForEach(languages, id: \.self) { id in
                    Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                }
            }
            Toggle("Keep line breaks", isOn: $keepBreaks)
        }
        Section {
            Toggle("Allow snapr:// links", isOn: $urlScheme)
        } header: {
            Text("Automation")
        } footer: {
            Text("snapr://grab/area, grab/fullscreen, grab/window, grab/scrolling, grab/repeat, ocr, color")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        Section("Permissions") {
            PermissionRow(title: "Screen Recording", detail: "Needed for every capture.", granted: screenRecording,
                          open: Permissions.openScreenRecordingSettings)
            PermissionRow(title: "Accessibility", detail: "Needed for scrolling capture.", granted: accessibility,
                          open: Permissions.openAccessibilitySettings)
        }
        .task {
            while !Task.isCancelled {
                screenRecording = Permissions.screenRecording
                accessibility = Permissions.accessibility
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings", action: open)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// The app's language: the Mac's, or one picked here. Stored in AppleLanguages
/// for this app only, which macOS reads at launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es

    var id: String { rawValue }

    /// Each language names itself, so people can find theirs.
    var title: String {
        switch self {
        case .system: String(localized: "Same as the Mac")
        case .en: "English"
        case .es: "Español"
        }
    }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String]
        return stored?.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
