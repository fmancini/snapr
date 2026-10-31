import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Opens editor windows and finds the one in front.
enum EditorController {
    private(set) static var controllers: [EditorWindowController] = []

    /// The model of the key editor window, for menu commands.
    static var key: EditorModel? {
        (NSApp.keyWindow?.windowController as? EditorWindowController)?.model
            ?? (NSApp.mainWindow?.windowController as? EditorWindowController)?.model
    }

    @discardableResult
    static func open(_ capture: Capture) -> EditorWindowController {
        let controller = EditorWindowController(capture: capture)
        controllers.append(controller)
        controller.present()
        return controller
    }

    static func open(file url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            HUD.show("Could not open \(url.lastPathComponent)", symbol: "exclamationmark.triangle")
            return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
        open(Capture(image: image, scale: max(1, (dpi / 72).rounded())))
    }

    static func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open(file:))
    }

    static func openClipboard() {
        guard let image = NSImage(pasteboard: .general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            HUD.show("No image on the clipboard", symbol: "doc.on.clipboard")
            return
        }
        open(Capture(image: cg, scale: max(1, (CGFloat(cg.width) / image.size.width).rounded())))
    }

    static func closed(_ controller: EditorWindowController) {
        controllers.removeAll { $0 === controller }
        DispatchQueue.main.async { Activation.update() }
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel

    init(capture: Capture) {
        model = EditorModel(capture: capture)
        let hosting = NSHostingController(rootView: EditorView(model: model).themed())
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = CGSize(width: 720, height: 420)
        super.init(window: window)
        window.delegate = self
        model.window = window
        sizeWindow()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Big enough for the capture at 100%, within the screen.
    private func sizeWindow() {
        guard let window else { return }
        let screen = NSScreen.underMouse.visibleFrame
        let image = model.capture.pointSize
        let width = min(max(image.width + 80, 820), screen.width * 0.9)
        let height = min(max(image.height + 140, 520), screen.height * 0.9)
        window.setFrame(CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height), display: false)
    }

    func present() {
        guard let window else { return }
        Activation.bringToFront(window)
        DispatchQueue.main.async { [model] in
            model.canvas?.zoomToInitial()
            if let canvas = model.canvas { window.makeFirstResponder(canvas) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.canvas?.commitTextEditing()
        EditorController.closed(self)
    }
}
