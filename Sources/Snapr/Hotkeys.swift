import AppKit
import Carbon.HIToolbox
import Observation
import SnaprKit
import SwiftUI

/// Every capture Snapr can start. The menu, the global hotkeys, and the
/// URL scheme all use this one list.
enum CaptureAction: String, CaseIterable, Identifiable {
    case area, fullscreen, window, scrolling, repeatArea, delayed, text, color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Capture Area"
        case .fullscreen: "Capture Screen"
        case .window: "Capture Window"
        case .scrolling: "Scrolling Capture"
        case .repeatArea: "Repeat Last Area"
        case .delayed: "Capture Area in 3 Seconds"
        case .text: "Capture Text"
        case .color: "Pick Color"
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .fullscreen: "display"
        case .window: "macwindow"
        case .scrolling: "arrow.up.and.down.text.horizontal"
        case .repeatArea: "arrow.clockwise"
        case .delayed: "timer"
        case .text: "text.viewfinder"
        case .color: "eyedropper"
        }
    }

    /// Defaults avoid ⇧⌘3, ⇧⌘4, and ⇧⌘5, which macOS keeps for itself.
    var defaultShortcut: Shortcut? {
        switch self {
        case .fullscreen: Shortcut(key: kVK_ANSI_1, command: true, shift: true)
        case .area: Shortcut(key: kVK_ANSI_2, command: true, shift: true)
        case .window: Shortcut(key: kVK_ANSI_2, command: true, shift: true, option: true)
        case .repeatArea: Shortcut(key: kVK_ANSI_1, command: true, shift: true, option: true)
        case .scrolling: Shortcut(key: kVK_ANSI_7, command: true, shift: true)
        case .text: Shortcut(key: kVK_ANSI_8, command: true, shift: true)
        case .color: Shortcut(key: kVK_ANSI_9, command: true, shift: true)
        case .delayed: nil
        }
    }

    /// snapr://grab/area, snapr://ocr, snapr://color
    var urlPath: String {
        switch self {
        case .area: "grab/area"
        case .fullscreen: "grab/fullscreen"
        case .window: "grab/window"
        case .scrolling: "grab/scrolling"
        case .repeatArea: "grab/repeat"
        case .delayed: "grab/delayed"
        case .text: "ocr"
        case .color: "color"
        }
    }

    init?(url: URL) {
        guard url.scheme == "snapr" else { return nil }
        let path = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }.joined(separator: "/")
        guard let match = Self.allCases.first(where: { $0.urlPath == path }) else { return nil }
        self = match
    }
}

/// Global hotkeys through Carbon: no permission needed, and the key never
/// reaches the front app.
@Observable
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Registration result per action. Non-zero: another app owns the combo.
    private(set) var failures: [CaptureAction: OSStatus] = [:]
    private(set) var shortcuts: [CaptureAction: Shortcut] = [:]
    @ObservationIgnored private var refs: [CaptureAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handlerInstalled = false
    /// While a recorder listens, hotkeys pause so the combo can be typed.
    @ObservationIgnored var paused = false

    private static let signature = OSType(0x534E_4150) // 'SNAP'

    private init() {
        load()
    }

    func shortcut(for action: CaptureAction) -> Shortcut? { shortcuts[action] }

    func set(_ shortcut: Shortcut?, for action: CaptureAction) {
        let key = "hotkey.\(action.rawValue)"
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            Prefs.defaults.set(data, forKey: key)
        } else {
            Prefs.defaults.set("none", forKey: key)
        }
        load()
        registerAll()
    }

    func resetAll() {
        for action in CaptureAction.allCases { Prefs.defaults.removeObject(forKey: "hotkey.\(action.rawValue)") }
        load()
        registerAll()
    }

    private func load() {
        var map: [CaptureAction: Shortcut] = [:]
        for action in CaptureAction.allCases {
            let stored = Prefs.defaults.object(forKey: "hotkey.\(action.rawValue)")
            if let data = stored as? Data, let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                map[action] = shortcut
            } else if stored == nil, let shortcut = action.defaultShortcut {
                map[action] = shortcut
            }
        }
        shortcuts = map
    }

    func registerAll() {
        installHandler()
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs = [:]
        var failed: [CaptureAction: OSStatus] = [:]
        for (index, action) in CaptureAction.allCases.enumerated() {
            guard let shortcut = shortcuts[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs[action] = ref } else { failed[action] = status }
        }
        failures = failed
    }

    func fire(_ id: UInt32) {
        guard !paused, id >= 1, Int(id) <= CaptureAction.allCases.count else { return }
        CaptureCoordinator.shared.perform(CaptureAction.allCases[Int(id) - 1])
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, nil, nil)
    }
}

private nonisolated func hotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    let number = id.id
    Task { @MainActor in HotkeyCenter.shared.fire(number) }
    return noErr
}

extension Shortcut {
    /// The shortcut a key-down event types, or nil for a bare key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(key: Int(event.keyCode), command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
        guard isValid else { return nil }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if hasCommand { modifiers.insert(.command) }
        if hasShift { modifiers.insert(.shift) }
        if hasOption { modifiers.insert(.option) }
        if hasControl { modifiers.insert(.control) }
        return modifiers
    }
}

/// A shortcut field: click, type a combo. Delete clears it, Esc cancels.
struct ShortcutRecorder: View {
    let action: CaptureAction
    @State private var center = HotkeyCenter.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: Space.xs) {
            if center.failures[action] != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Another app already uses this shortcut.")
            }
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : center.shortcut(for: action)?.display ?? "None")
                    .monospacedDigit()
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(recording ? Palette.accent : nil)
            .help("Click, then press the new shortcut. Delete clears it.")
            if center.shortcut(for: action) != nil {
                Button {
                    center.set(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        center.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                center.set(nil, for: action)
                stop()
            default:
                guard let shortcut = Shortcut(event: event) else { NSSound.beep(); return nil }
                center.set(shortcut, for: action)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        center.paused = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
