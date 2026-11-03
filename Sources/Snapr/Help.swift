import AppKit
import SnaprKit
import SwiftUI

/// Help > Snapr Help (⌘?): a window with one page per topic. Shortcuts on
/// the pages come from Settings, so they always match what works.
enum HelpWindow {
    static let id = NSUserInterfaceItemIdentifier("help")
    private static var controller: NSWindowController?
    private static let model = HelpModel()

    static var window: NSWindow? { controller?.window }

    static func show(_ topic: HelpTopic? = nil) {
        if let topic { model.topic = topic }
        if controller == nil {
            let hosting = NSHostingController(rootView: HelpView(model: model).themed())
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.identifier = id
            window.title = String(localized: "Snapr Help")
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 860, height: 620))
            window.minSize = CGSize(width: 640, height: 420)
            window.setFrameAutosaveName("SnaprHelp")
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { Activation.update() } }
            }
            controller = NSWindowController(window: window)
            window.center()
        }
        guard let window = controller?.window else { return }
        Activation.bringToFront(window)
    }
}

@Observable
final class HelpModel {
    var topic: HelpTopic = .gettingStarted
}

/// The help pages, in sidebar order. Snapshot mode walks through every case.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, capturing, editor, previewAndPin, textAndColor, scrolling, automation, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .capturing: String(localized: "Capturing")
        case .editor: String(localized: "Editor")
        case .previewAndPin: String(localized: "Preview and Pin")
        case .textAndColor: String(localized: "Text and Color")
        case .scrolling: String(localized: "Scrolling Capture")
        case .automation: String(localized: "Automation")
        case .troubleshooting: String(localized: "Troubleshooting")
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .capturing: "camera.viewfinder"
        case .editor: "pencil.and.outline"
        case .previewAndPin: "pin"
        case .textAndColor: "text.viewfinder"
        case .scrolling: "arrow.up.and.down.text.horizontal"
        case .automation: "link"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }
}

struct HelpView: View {
    @Bindable var model: HelpModel

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $model.topic) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    Text(model.topic.title)
                        .font(.largeTitle.weight(.semibold))
                        .gridProbe("title", area: "help")
                    page(model.topic)
                        .gridProbe("page", area: "help")
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(Space.section)
                .gridArea("help", inset: Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .id(model.topic)
        }
        .navigationTitle(String(localized: "Snapr Help"))
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ topic: HelpTopic) -> some View {
        switch topic {
        case .gettingStarted: GettingStartedPage()
        case .capturing: CapturingPage()
        case .editor: EditorPage()
        case .previewAndPin: PreviewPinPage()
        case .textAndColor: TextColorPage()
        case .scrolling: ScrollingPage()
        case .automation: AutomationPage()
        case .troubleshooting: TroubleshootingPage()
        }
    }
}

// MARK: Pages

private struct GettingStartedPage: View {
    @State private var hotkeys = HotkeyCenter.shared

    var body: some View {
        Text("Snapr lives in the menu bar. Press a shortcut in any app to capture the screen, then copy, save, mark up, or pin the result.")
            .font(.title3)
            .foregroundStyle(.secondary)
        HelpSection("Your first capture") {
            HelpStep(1, "Press \(hotkeys.shortcut(for: .area)?.display ?? CaptureAction.area.title) and drag over part of the screen.")
            HelpStep(2, "A thumbnail appears in the corner of the screen. The image is already on the clipboard.")
            HelpStep(3, "Click Edit to add arrows and text, or drag the thumbnail into any app.")
        }
        HelpSection("Permissions") {
            Text("The first capture asks for Screen Recording. Turn on Snapr in System Settings, then capture again. Scrolling capture also needs Accessibility.")
            Button("Open Permission Settings") { SettingsWindow.show(.advanced) }
        }
        HelpSection("Where to find things") {
            HelpRow(symbol: "camera.viewfinder", title: "Menu bar icon", detail: "Every capture, Open File, Settings, and Help.")
            HelpRow(symbol: "gearshape", title: "Settings", detail: "What happens after a capture, where files go, shortcuts, and language.")
            HelpRow(symbol: "questionmark.circle", title: "This window", detail: "Help > Snapr Help, or ⌘? while Snapr is in front.")
        }
    }
}

private struct CapturingPage: View {
    @State private var hotkeys = HotkeyCenter.shared

    var body: some View {
        HelpSection("Captures") {
            ForEach(CaptureAction.allCases) { action in
                KeyRow(keys: hotkeys.shortcut(for: action)?.display, symbol: action.symbol, title: action.title, detail: action.helpText)
            }
            Button("Change Shortcuts") { SettingsWindow.show(.shortcuts) }
        }
        HelpSection("In the capture overlay") {
            KeyRow(keys: String(localized: "Drag"), title: String(localized: "Select an area"),
                   detail: String(localized: "The size in pixels shows under the selection."))
            KeyRow(keys: String(localized: "Click"), title: String(localized: "Capture a window"),
                   detail: String(localized: "The window under the pointer is highlighted first."))
            KeyRow(keys: String(localized: "Space"), title: String(localized: "Switch mode"),
                   detail: String(localized: "Switches between area and window mode."))
            KeyRow(keys: "← → ↑ ↓", title: String(localized: "Move the pointer"),
                   detail: String(localized: "Moves one point at a time. Hold Shift to move ten."))
            KeyRow(keys: "Esc", title: String(localized: "Cancel"), detail: String(localized: "Right-click also cancels."))
            Text("The magnifier next to the pointer shows the pixels underneath, their position, and their color, so you can line up edges exactly.")
                .foregroundStyle(.secondary)
        }
        HelpSection("After a capture") {
            Text("By default the image goes to the clipboard and a thumbnail appears. Settings > General can also save every capture, or open the editor right away.")
        }
    }
}

private struct EditorPage: View {
    var body: some View {
        Text("Open the editor from the thumbnail, with Open File, or with Open From Clipboard. Press a letter to pick a tool.")
            .foregroundStyle(.secondary)
        HelpSection("Tools") {
            ForEach(Tool.allCases) { tool in
                KeyRow(keys: String(tool.key).uppercased(), symbol: tool.symbol, title: tool.title, detail: tool.helpText)
            }
        }
        HelpSection("Working with marks") {
            KeyRow(keys: "1–6", title: String(localized: "Pick a color"), detail: String(localized: "Red, orange, yellow, green, blue, purple."))
            KeyRow(keys: "⇧", title: String(localized: "Hold Shift while drawing"),
                   detail: String(localized: "Lines snap to 45 degrees; rectangles and ovals become squares and circles."))
            KeyRow(keys: "V", title: String(localized: "Select and move"),
                   detail: String(localized: "Click a mark, drag it, or nudge it with the arrow keys. Changing the color or size restyles it."))
            KeyRow(keys: "⌫", title: String(localized: "Delete a mark"), detail: String(localized: "Removes the selected mark."))
            KeyRow(keys: "⌘Z", title: String(localized: "Undo"), detail: String(localized: "⇧⌘Z redoes. Every mark and crop can be undone."))
        }
        HelpSection("Finish") {
            KeyRow(keys: "⌘C", title: String(localized: "Copy"), detail: String(localized: "Copies the image with its marks."))
            KeyRow(keys: "⌘S", title: String(localized: "Save"), detail: String(localized: "Saves to the screenshots folder. ⇧⌘S asks where."))
            KeyRow(keys: "⌘P", title: String(localized: "Pin"), detail: String(localized: "Floats the image above every window."))
            KeyRow(keys: "⇧⌘T", title: String(localized: "Copy Text"), detail: String(localized: "Copies the text in the image."))
            KeyRow(keys: "Esc", title: String(localized: "Done"), detail: String(localized: "Copies the image and closes the editor. Settings > Advanced turns the copy off."))
        }
    }
}

private struct PreviewPinPage: View {
    var body: some View {
        HelpSection("The thumbnail") {
            Text("After a capture, a thumbnail floats in the corner of the screen for 8 seconds. Hold the pointer over it to keep it and see its buttons.")
            HelpRow(symbol: "doc.on.doc", title: "Copy", detail: "Copies the image again.")
            HelpRow(symbol: "square.and.arrow.down", title: "Save", detail: "Saves to the screenshots folder.")
            HelpRow(symbol: "text.viewfinder", title: "Copy Text", detail: "Copies the text in the image.")
            HelpRow(symbol: "pin", title: "Pin to Screen", detail: "Floats the image above every window.")
            HelpRow(symbol: "pencil", title: "Edit", detail: "Opens the editor. Double-clicking the thumbnail does the same.")
            HelpRow(symbol: "hand.draw", title: "Drag", detail: "Drop the thumbnail into Mail, Messages, Slack, Finder, or any app.")
        }
        HelpSection("Pinned images") {
            Text("A pinned image stays on top of every window, on every desktop. Use it to compare designs or keep a reference in view.")
            KeyRow(keys: String(localized: "Drag"), title: String(localized: "Move"), detail: String(localized: "Drag anywhere on the image."))
            KeyRow(keys: String(localized: "Scroll"), title: String(localized: "Zoom"), detail: String(localized: "Scroll or pinch to resize it."))
            KeyRow(keys: String(localized: "Double-click"), title: String(localized: "Edit"), detail: String(localized: "Opens it in the editor."))
            KeyRow(keys: String(localized: "Right-click"), title: String(localized: "More"),
                   detail: String(localized: "50%, 100%, 200%, semi-transparent, copy, edit, close."))
            KeyRow(keys: "Esc", title: String(localized: "Close"), detail: String(localized: "Or click the close button in its corner."))
        }
    }
}

private struct TextColorPage: View {
    @State private var hotkeys = HotkeyCenter.shared

    var body: some View {
        HelpSection("Copy text from the screen") {
            KeyRow(keys: hotkeys.shortcut(for: .text)?.display, symbol: CaptureAction.text.symbol,
                   title: CaptureAction.text.title, detail: CaptureAction.text.helpText)
            Text("Text recognition runs on this Mac. Nothing leaves your computer. If the area holds a QR code or bar code, Snapr copies what the code says instead.")
            Text("Settings > Advanced picks the language and whether line breaks are kept.")
                .foregroundStyle(.secondary)
        }
        HelpSection("Pick a color") {
            KeyRow(keys: hotkeys.shortcut(for: .color)?.display, symbol: CaptureAction.color.symbol,
                   title: CaptureAction.color.title, detail: CaptureAction.color.helpText)
            Text("Move the magnifier over the pixel you want and click. The color is copied as a hex code, like #0A84FF.")
        }
    }
}

private struct ScrollingPage: View {
    @State private var hotkeys = HotkeyCenter.shared

    var body: some View {
        Text("Scrolling capture takes a picture of something taller than the screen, like a long web page or chat, by scrolling it for you and joining the pieces.")
            .foregroundStyle(.secondary)
        HelpSection("How to use it") {
            HelpStep(1, "Press \(hotkeys.shortcut(for: .scrolling)?.display ?? CaptureAction.scrolling.title) and drag over the content that scrolls.")
            HelpStep(2, "Snapr scrolls down and shows the height so far.")
            HelpStep(3, "It stops at the end of the content. Press Esc, click, or click Stop to finish sooner.")
        }
        HelpSection("Good to know") {
            HelpRow(symbol: "hand.raised", title: "Accessibility", detail: "Snapr needs Accessibility to scroll other apps. It asks the first time.")
            HelpRow(symbol: "arrow.up.to.line", title: "Maximum height", detail: "Settings > Capture sets where it stops. The default is 20,000 pixels.")
            HelpRow(symbol: "rectangle.topthird.inset.filled", title: "Fixed headers", detail: "Leave headers and toolbars that do not scroll outside the area.")
        }
    }
}

private struct AutomationPage: View {
    var body: some View {
        Text("Start any capture from Shortcuts, Raycast, Alfred, a Stream Deck, or the Terminal with a snapr:// link.")
            .foregroundStyle(.secondary)
        HelpSection("Links") {
            ForEach(CaptureAction.allCases) { action in
                KeyRow(keys: "snapr://\(action.urlPath)", title: action.title, detail: nil, wideKeys: true)
            }
        }
        HelpSection("Example") {
            Text(verbatim: "open snapr://grab/area")
                .font(.body.monospaced())
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Settings > Advanced can turn links off.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TroubleshootingPage: View {
    var body: some View {
        HelpQuestion("Nothing happens when I press a shortcut.",
                     answer: "Another app may use the same keys. Settings > Shortcuts shows a warning next to it. Pick another shortcut.") {
            Button("Open Shortcuts Settings") { SettingsWindow.show(.shortcuts) }
        }
        HelpQuestion("Captures are black, or show only the desktop picture.",
                     answer: "Snapr does not have Screen Recording. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording. If it already looks on, remove Snapr from the list, add it again, and restart Snapr.") {
            Button("Open Screen Recording Settings") { Permissions.openScreenRecordingSettings() }
        }
        HelpQuestion("I can't see the menu bar icon.",
                     answer: "The menu bar may be full, or the icon may be hidden behind the camera notch. Check System Settings > Menu Bar. You can always open Snapr again from Finder or Spotlight to reach Settings.") {
            EmptyView()
        }
        HelpQuestion("⇧⌘3 and ⇧⌘4 still open the Mac's screenshot tool.",
                     answer: "macOS keeps those keys. Turn them off in System Settings > Keyboard > Keyboard Shortcuts > Screenshots, then set them in Snapr.") {
            EmptyView()
        }
        HelpQuestion("Scrolling capture stops right away.",
                     answer: "Snapr needs Accessibility to scroll, and the content under the area must scroll with the mouse wheel. Try a smaller area inside the scrolling part.") {
            Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
        }
    }
}

// MARK: Parts

private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(.title2.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(verbatim: "\(number)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 24, height: 24)
                .background(Palette.accent, in: Circle())
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text)
        }
    }
}

private struct HelpRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.accentText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

/// A key cap (or a gesture name) beside what it does.
private struct KeyRow: View {
    let keys: String?
    var symbol: String?
    let title: String
    let detail: String?
    var wideKeys = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(keys ?? String(localized: "No shortcut"))
                .font(.callout.monospaced())
                .foregroundStyle(keys == nil ? .secondary : .primary)
                .lineLimit(1)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .frame(width: wideKeys ? 236 : 128, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xs) {
                if let symbol {
                    Label(title, systemImage: symbol).fontWeight(.medium)
                } else {
                    Text(title).fontWeight(.medium)
                }
                if let detail { Text(detail).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct HelpQuestion<Action: View>: View {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey
    @ViewBuilder let action: Action

    init(_ question: LocalizedStringKey, answer: LocalizedStringKey, @ViewBuilder action: () -> Action) {
        self.question = question
        self.answer = answer
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(question).font(.headline)
            Text(answer).foregroundStyle(.secondary)
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Help text for actions and tools

extension CaptureAction {
    var helpText: String {
        switch self {
        case .area: String(localized: "Freezes the screen so you can drag over any part of it.")
        case .fullscreen: String(localized: "Captures the whole display under the pointer.")
        case .window: String(localized: "Captures one window with a transparent background, even if other windows cover it.")
        case .scrolling: String(localized: "Scrolls the content under an area and joins it into one tall image.")
        case .repeatArea: String(localized: "Captures the same area as last time, without selecting it again.")
        case .delayed: String(localized: "Waits 3 seconds first, so you can open a menu or hover over something.")
        case .text: String(localized: "Copies the text, QR code, or bar code inside an area.")
        case .color: String(localized: "Copies the hex code of the pixel you click.")
        }
    }
}

extension Tool {
    var helpText: String {
        switch self {
        case .select: String(localized: "Pick a mark to move, restyle, or delete it.")
        case .arrow: String(localized: "Drag from the tail to the point.")
        case .rectangle: String(localized: "Drag to frame something.")
        case .oval: String(localized: "Drag to circle something.")
        case .line: String(localized: "Drag a straight line.")
        case .freehand: String(localized: "Draw freely with the pointer.")
        case .highlighter: String(localized: "Mark text like a highlighter pen.")
        case .text: String(localized: "Click, type, and press Return. Double-click text to change it.")
        case .counter: String(localized: "Click to place numbered steps: 1, 2, 3.")
        case .blur: String(localized: "Drag over passwords, names, or anything private to pixelate it.")
        case .spotlight: String(localized: "Drag to dim everything except one area.")
        case .crop: String(localized: "Drag to keep only part of the image. Reset Crop brings the rest back.")
        }
    }
}

// MARK: About

/// Snapr > About Snapr: the standard panel with credits.
enum AboutPanel {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let bold: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(string: String(localized: "Created by") + "\n", attributes: body))
        credits.append(NSAttributedString(string: "Felipe Mancini\n\n", attributes: bold))
        credits.append(NSAttributedString(string: String(localized: "A screenshot tool for the Mac, inspired by Shottr.") + "\n", attributes: body))
        credits.append(NSAttributedString(string: String(localized: "Built with SwiftUI, ScreenCaptureKit, and Vision."), attributes: body))
        NSApp.activate()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Felipe Mancini",
        ])
        if let opened = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }) {
            window = opened
        }
    }

    /// The panel AppKit opened, for snapshots.
    private(set) static weak var window: NSWindow?
}
