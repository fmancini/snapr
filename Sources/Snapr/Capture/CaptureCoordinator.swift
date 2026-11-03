import AppKit
import SnaprKit

/// Runs every capture action and hands the result to the after-capture steps.
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// The last area, in global top-left points, for Repeat Last Area.
    private(set) var lastArea: (displayID: CGDirectDisplayID, local: CGRect, global: CGRect)?
    /// The latest capture, for Copy Last Capture in the menu bar item.
    private(set) var lastCapture: Capture?
    private var busy = false

    func handle(url: URL) {
        guard Prefs.urlScheme else { return }
        if let action = CaptureAction(url: url) { perform(action) }
    }

    func perform(_ action: CaptureAction) {
        guard !busy, !OverlayController.isOpen else { return }
        guard ScreenCapturer.ensurePermission() else { return }
        busy = true
        Task {
            defer { busy = false }
            // Let the menu close before the screen freezes.
            try? await Task.sleep(for: .milliseconds(120))
            switch action {
            case .area: await area(.area)
            case .window: await area(.window)
            case .fullscreen: await fullscreen()
            case .repeatArea: await repeatArea()
            case .delayed:
                HUD.show("Capturing in 3 seconds", symbol: "timer")
                try? await Task.sleep(for: .seconds(3))
                await area(.area)
            case .text: await text()
            case .color: await color()
            case .scrolling: await scrolling()
            }
        }
    }

    // MARK: Actions

    private func area(_ mode: OverlayMode) async {
        guard let result = await OverlayController.pick(mode) else { return }
        switch result {
        case let .area(shot, pixels, global):
            guard let image = shot.image.cropping(to: pixels) else { return }
            lastArea = (shot.displayID, global.offsetBy(dx: -shot.originCG.x, dy: -shot.originCG.y), global)
            deliver(Capture(image: image, scale: shot.scale, sourceRect: global))
        case let .window(info):
            await window(info)
        case .color:
            break
        }
    }

    private func window(_ info: WindowInfo) async {
        do {
            let image = try await ScreenCapturer.capture(windowID: info.id, shadow: Prefs.windowShadow)
            let scale = NSScreen.screens.first { appKitRect(fromCG: info.frame).intersects($0.frame) }?.backingScaleFactor ?? 2
            deliver(Capture(image: image, scale: scale, sourceRect: info.frame))
        } catch {
            HUD.show("\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    private func fullscreen() async {
        let screen = NSScreen.underMouse
        do {
            let image = try await ScreenCapturer.capture(displayID: screen.displayID, rect: nil)
            let frame = CGRect(origin: screen.originCG, size: screen.frame.size)
            deliver(Capture(image: image, scale: screen.backingScaleFactor, sourceRect: frame))
        } catch {
            HUD.show("\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    private func repeatArea() async {
        guard let last = lastArea,
              let screen = NSScreen.screens.first(where: { $0.displayID == last.displayID }) else {
            HUD.show("Capture an area first", symbol: "rectangle.dashed")
            return
        }
        do {
            let image = try await ScreenCapturer.capture(displayID: last.displayID, rect: last.local)
            deliver(Capture(image: image, scale: screen.backingScaleFactor, sourceRect: last.global))
        } catch {
            HUD.show("\(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    private func text() async {
        guard case let .area(shot, pixels, _)? = await OverlayController.pick(.text),
              let image = shot.image.cropping(to: pixels) else { return }
        await OCR.copyText(in: image)
    }

    private func color() async {
        guard case let .color(hex)? = await OverlayController.pick(.color) else { return }
        Output.copyText(hex)
        HUD.show("Copied \(hex)", symbol: "eyedropper", swatch: hex)
    }

    private func scrolling() async {
        guard case let .area(shot, _, global)? = await OverlayController.pick(.scrolling) else { return }
        let local = global.offsetBy(dx: -shot.originCG.x, dy: -shot.originCG.y)
        if let capture = await ScrollingCapture.run(displayID: shot.displayID, local: local, global: global, scale: shot.scale) {
            deliver(capture)
        }
    }

    // MARK: After capture

    /// Copy, save, and show, as Settings say.
    func deliver(_ capture: Capture) {
        lastCapture = capture
        let copied = Prefs.afterCopy
        if copied { Output.copy(capture) }
        let saved = Prefs.afterSave && Output.save(capture) != nil
        switch Prefs.afterShow {
        case .preview: PreviewPanel.show(capture)
        case .editor: EditorController.open(capture)
        case .nothing:
            if copied && saved {
                HUD.show("Copied and saved", symbol: "checkmark.circle")
            } else if copied {
                HUD.show("Copied", symbol: "checkmark.circle")
            } else if saved {
                HUD.show("Saved", symbol: "checkmark.circle")
            }
        }
    }
}
