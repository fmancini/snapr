import AppKit
import ImageIO
import SnaprKit
import SwiftUI
import UniformTypeIdentifiers

/// Copying and saving images.
enum Output {
    /// The image as it leaves the app: 1x when "Resize retina screenshots" is on.
    static func prepared(_ capture: Capture) -> (image: CGImage, scale: CGFloat) {
        guard Prefs.downscale, capture.scale > 1,
              let context = AnnotationRenderer.makeContext(size: capture.pointSize) else { return (capture.image, capture.scale) }
        AnnotationRenderer.drawImage(capture.image, in: CGRect(origin: .zero, size: capture.pointSize), context: context)
        return (context.makeImage() ?? capture.image, 1)
    }

    static func data(_ image: CGImage, scale: CGFloat, format: Prefs.SaveFormat = .png) -> Data? {
        let data = NSMutableData()
        let type = format == .png ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale,
        ]
        if format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Puts the image on a pasteboard at its point size, as PNG and TIFF.
    static func copy(_ capture: Capture, to pasteboard: NSPasteboard = .general) {
        let (image, scale) = prepared(capture)
        let nsImage = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        if let png = data(image, scale: scale) { pasteboard.setData(png, forType: .png) }
    }

    static func copyText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Saves into the screenshots folder with a dated name. Returns the file.
    @discardableResult
    static func save(_ capture: Capture, folder: URL = Prefs.saveFolder) -> URL? {
        let format = Prefs.saveFormat
        let (image, scale) = prepared(capture)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = CaptureFileName.unique(CaptureFileName.make(date: capture.date, ext: format.ext)) {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
        let url = folder.appending(path: name)
        guard let data = data(image, scale: scale, format: format), (try? data.write(to: url)) != nil else {
            HUD.show("Could not save to \(folder.lastPathComponent)", symbol: "exclamationmark.triangle")
            return nil
        }
        return url
    }

    /// Asks where to save.
    static func saveAs(_ capture: Capture, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = CaptureFileName.make(date: capture.date)
        panel.directoryURL = Prefs.saveFolder
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let format: Prefs.SaveFormat = url.pathExtension.lowercased().hasPrefix("jp") ? .jpeg : .png
            let (image, scale) = prepared(capture)
            if let data = data(image, scale: scale, format: format) { try? data.write(to: url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }

    /// A PNG in the temporary folder, for dragging into other apps.
    static func temporaryFile(_ capture: Capture) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appending(path: "Snapr", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: CaptureFileName.make(date: capture.date))
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let (image, scale) = prepared(capture)
        guard let data = data(image, scale: scale), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}

/// A short message that floats near the bottom of the screen, then fades.
enum HUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ key: String.LocalizationValue, symbol: String, swatch: String? = nil) {
        let message = String(localized: key)
        if Snapshot.requested || SelfTest.requested { print("HUD \(message)"); return }
        hideTask?.cancel()
        panel?.orderOut(nil)
        let host = NSHostingView(rootView: HUDView(message: message, symbol: symbol, swatch: swatch).themed())
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        let screen = NSScreen.underMouse.visibleFrame
        let panel = NSPanel(contentRect: CGRect(x: screen.midX - size.width / 2, y: screen.minY + 80, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 0 } completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            }
        }
    }
}

private struct HUDView: View {
    let message: String
    let symbol: String
    let swatch: String?

    var body: some View {
        HStack(spacing: Space.sm) {
            if let swatch, let value = UInt32(swatch.dropFirst(), radix: 16) {
                Circle().fill(Color(hex: value)).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.separator))
            } else {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            Text(message).font(.callout.weight(.medium))
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .glassEffect(.regular, in: .capsule)
        .padding(Space.lg)
    }
}
