import AppKit
import Carbon.HIToolbox
import SnaprKit
import SwiftUI

/// Scrolls the content under an area and stitches the frames into one tall
/// image. Posting scroll events needs Accessibility.
enum ScrollingCapture {
    @MainActor private final class Session {
        var stopped = false
        var height = 0
    }

    static func run(displayID: CGDirectDisplayID, local: CGRect, global: CGRect, scale: CGFloat) async -> Capture? {
        guard Permissions.requestAccessibility() else {
            HUD.show("Scrolling capture needs Accessibility", symbol: "hand.raised")
            Permissions.openAccessibilitySettings()
            return nil
        }
        let session = Session()
        let border = BorderPanel(around: global)
        let controls = ScrollControls(below: global) { session.stopped = true }
        border.orderFrontRegardless()
        controls.panel.orderFrontRegardless()
        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .leftMouseDown || Int(event.keyCode) == kVK_Escape {
                MainActor.assumeIsolated { session.stopped = true }
            }
        }
        defer {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            border.orderOut(nil)
            controls.panel.orderOut(nil)
        }

        let center = CGPoint(x: global.midX, y: global.midY)
        let savedMouse = CGEvent(source: nil)?.location
        CGWarpMouseCursorPosition(center)
        defer { if let savedMouse { CGWarpMouseCursorPosition(savedMouse) } }

        guard var previous = try? await ScreenCapturer.capture(displayID: displayID, rect: local) else { return nil }
        var frames = [previous]
        var offsets: [Int] = []
        var still = 0
        let maxHeight = Prefs.scrollMaxHeight
        session.height = previous.height
        controls.update(height: session.height)
        let step = Int32(max(40, local.height * 0.55))

        while !session.stopped && session.height < maxHeight {
            let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)
            scroll?.location = center
            scroll?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(260))
            guard !session.stopped, let next = try? await ScreenCapturer.capture(displayID: displayID, rect: local) else { break }
            let last = previous
            let offset = await Task.detached { Stitcher.offset(previous: last, next: next) }.value // grid: ok scroll offset, not a view offset
            guard let offset else { break }
            if offset == 0 {
                still += 1
                if still >= 2 { break }
                continue
            }
            still = 0
            frames.append(next)
            offsets.append(offset)
            previous = next
            session.height += offset
            controls.update(height: session.height)
        }
        let allFrames = frames, allOffsets = offsets
        guard let image = await Task.detached(operation: { Stitcher.compose(allFrames, offsets: allOffsets) }).value else { return nil }
        return Capture(image: image, scale: scale, sourceRect: global)
    }
}

/// A click-through outline just outside the scrolling area.
private final class BorderPanel: NSPanel {
    init(around rect: CGRect) {
        let frame = appKitRect(fromCG: rect).insetBy(dx: -3, dy: -3)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSHostingView(rootView: Rectangle().strokeBorder(Palette.accent, lineWidth: 2).themed())
    }
}

@Observable
private final class ScrollStatus {
    var height = 0
}

private final class ScrollControls {
    let panel: NSPanel
    private let status = ScrollStatus()

    init(below rect: CGRect, stop: @escaping () -> Void) {
        let area = appKitRect(fromCG: rect)
        let size = CGSize(width: 260, height: 52)
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        let screen = NSScreen.screens.first { $0.frame.intersects(area) }?.visibleFrame ?? .zero
        if origin.y < screen.minY { origin.y = area.maxY + 12 }
        panel = NSPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: ScrollControlsView(status: status, stop: stop).themed())
    }

    func update(height: Int) { status.height = height }
}

private struct ScrollControlsView: View {
    let status: ScrollStatus
    let stop: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            ProgressView().controlSize(.small)
            Text("\(status.height) px").monospacedDigit().font(.callout)
            Spacer()
            Button("Stop", action: stop)
                .buttonStyle(.borderedProminent)
                .help("Stop scrolling and keep what is captured (Esc)")
        }
        .padding(.horizontal, Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
    }
}
