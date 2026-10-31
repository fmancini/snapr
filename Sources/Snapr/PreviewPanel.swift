import AppKit
import SwiftUI

/// The thumbnail that floats in the corner after a capture.
enum PreviewPanel {
    private static var panel: NSPanel?
    private static var closeTask: Task<Void, Never>?
    static let width: CGFloat = 280

    static var window: NSWindow? { panel }

    static func show(_ capture: Capture) {
        close()
        let size = thumbnailSize(capture)
        let screen = NSScreen.underMouse.visibleFrame
        let frame = CGRect(x: screen.maxX - size.width - Space.lg, y: screen.minY + Space.lg,
                           width: size.width, height: size.height)
        let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = PreviewView(capture: capture, hoverChanged: { hovering in
            hovering ? closeTask?.cancel() : scheduleClose()
        })
        let host = NSHostingView(rootView: view.themed())
        host.sizingOptions = []
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel
        scheduleClose()
    }

    static func thumbnailSize(_ capture: Capture) -> CGSize {
        let ratio = CGFloat(capture.image.height) / max(1, CGFloat(capture.image.width))
        let height = min(220, max(120, width * ratio))
        return CGSize(width: width, height: height)
    }

    static func scheduleClose() {
        closeTask?.cancel()
        guard Prefs.previewAutoClose, !Snapshot.requested else { return }
        closeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { close() }
        }
    }

    static func close() {
        closeTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct PreviewView: View {
    let capture: Capture
    var hoverChanged: (Bool) -> Void = { _ in }
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        ZStack {
            Rectangle().fill(.background.secondary)
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(Space.sm)
            if hovering { actions.transition(.opacity) }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        .contentShape(shape)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
            hoverChanged(inside)
        }
        .onTapGesture(count: 2) { edit() }
        .onDrag {
            Output.temporaryFile(capture).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        }
        .help("Double-click to edit. Drag into any app.")
    }

    private var actions: some View {
        VStack(spacing: 0) {
            HStack {
                actionButton("Close", symbol: "xmark") { PreviewPanel.close() }
                Spacer()
                actionButton("Pin to Screen", symbol: "pin") {
                    PinWindow.show(capture)
                    PreviewPanel.close()
                }
            }
            Spacer()
            HStack(spacing: Space.sm) {
                actionButton("Copy", symbol: "doc.on.doc") {
                    Output.copy(capture)
                    PreviewPanel.close()
                    HUD.show("Copied", symbol: "checkmark.circle")
                }
                actionButton("Save", symbol: "square.and.arrow.down") {
                    if let url = Output.save(capture) { HUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle") }
                    PreviewPanel.close()
                }
                actionButton("Copy Text", symbol: "text.viewfinder") {
                    PreviewPanel.close()
                    Task { await OCR.copyText(in: capture.image) }
                }
                Spacer()
                Button("Edit", action: edit)
                    .buttonStyle(.glassProminent)
                    .help("Open in the editor")
            }
        }
        .padding(Space.sm)
        .background(.black.opacity(0.18))
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .help(title)
        .accessibilityLabel(title)
    }

    private func edit() {
        PreviewPanel.close()
        EditorController.open(capture)
    }
}
