import AppKit
import Carbon.HIToolbox
import SnaprKit

/// What the overlay is picking.
enum OverlayMode {
    case area, window, text, color, scrolling

    var hint: String {
        switch self {
        case .area: "Drag to capture an area. Click a window, or press Space for window mode."
        case .window: "Click a window to capture it. Space switches to area mode."
        case .text: "Drag over the text to copy it."
        case .color: "Click to copy the color."
        case .scrolling: "Drag over the content to scroll."
        }
    }
}

enum OverlayResult {
    /// A rectangle in pixels of a display shot, plus the same area in global CG points.
    case area(DisplayShot, pixels: CGRect, global: CGRect)
    case window(WindowInfo)
    case color(String)
}

/// The full-screen picker over frozen screenshots of every display.
final class OverlayController {
    private(set) var mode: OverlayMode
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<OverlayResult?, Never>?
    let targets: [WindowInfo]
    /// The window under the mouse in window mode.
    var hovered: WindowInfo?
    private static var current: OverlayController?

    private init(mode: OverlayMode) {
        self.mode = mode
        targets = (mode == .area || mode == .window) ? WindowInfo.onScreen() : []
    }

    static var isOpen: Bool { current != nil }

    /// Freezes the screens, lets the person pick, and returns nil on Esc.
    static func pick(_ mode: OverlayMode) async -> OverlayResult? {
        guard current == nil else { return nil }
        let shots: [DisplayShot]
        do { shots = try await ScreenCapturer.captureAllDisplays() } catch {
            HUD.show(error.localizedDescription, symbol: "exclamationmark.triangle")
            return nil
        }
        let controller = OverlayController(mode: mode)
        current = controller
        return await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.open(shots)
        }
    }

    private func open(_ shots: [DisplayShot]) {
        for shot in shots {
            let window = OverlayWindow(shot: shot, controller: self)
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        (windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
        redrawAll()
    }

    func toggleWindowMode() {
        switch mode {
        case .area: mode = .window
        case .window: mode = .area
        default: return
        }
        updateHover()
        redrawAll()
    }

    func updateHover() {
        guard mode == .area || mode == .window else { hovered = nil; return }
        let mouse = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: mouse.x, y: mainHeight - mouse.y)
        hovered = targets.first { $0.frame.contains(point) }
    }

    func redrawAll() {
        for window in windows { window.contentView?.needsDisplay = true }
    }

    func finish(_ result: OverlayResult?) {
        NSCursor.pop()
        for window in windows { window.orderOut(nil) }
        windows = []
        Self.current = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

final class OverlayWindow: NSWindow {
    init(shot: DisplayShot, controller: OverlayController) {
        super.init(contentRect: shot.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(shot: shot, controller: controller)
        setFrame(shot.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Draws the frozen screen, the dimming, the selection, and the magnifier.
final class OverlayView: NSView {
    let shot: DisplayShot
    unowned let controller: OverlayController
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var mouse: CGPoint?

    init(shot: DisplayShot, controller: OverlayController) {
        self.shot = shot
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        if window?.isKeyWindow == false { window?.makeKey() }
        controller.updateHover()
        controller.redrawAll()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        mouse = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, controller.mode != .color, controller.mode != .window else { return }
        let point = convert(event.locationInWindow, from: nil).clamped(to: bounds)
        mouse = point
        selection = SelectionGeometry.rect(from: start, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        let point = convert(event.locationInWindow, from: nil)
        if controller.mode == .color {
            let pixel = CGPoint(x: point.x * shot.scale, y: point.y * shot.scale)
            controller.finish(PixelReader.hex(at: pixel, in: shot.image).map(OverlayResult.color))
            return
        }
        if let selection, selection.width >= 4, selection.height >= 4 {
            let pixels = SelectionGeometry.pixelRect(selection: selection, viewSize: bounds.size,
                                                     imageSize: CGSize(width: shot.image.width, height: shot.image.height))
            let global = selection.offsetBy(dx: shot.originCG.x, dy: shot.originCG.y)
            controller.finish(.area(shot, pixels: pixels, global: global))
            return
        }
        selection = nil
        if let window = controller.hovered {
            controller.finish(.window(window))
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { controller.finish(nil) }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape: controller.finish(nil)
        case kVK_Space: controller.toggleWindowMode()
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow: nudge(event)
        default: super.keyDown(with: event)
        }
    }

    /// Arrow keys move the pointer one point, for precise edges.
    private func nudge(_ event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var position = CGEvent(source: nil)?.location ?? .zero
        switch Int(event.keyCode) {
        case kVK_LeftArrow: position.x -= step
        case kVK_RightArrow: position.x += step
        case kVK_UpArrow: position.y -= step
        default: position.y += step
        }
        CGWarpMouseCursorPosition(position)
        CGAssociateMouseAndMouseCursorPosition(1)
        mouse = CGPoint(x: position.x - shot.originCG.x, y: position.y - shot.originCG.y)
        if let start = dragStart, let mouse { selection = SelectionGeometry.rect(from: start, to: mouse) }
        controller.redrawAll()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        AnnotationRenderer.drawImage(shot.image, in: bounds, context: context)

        let hole: CGRect? = selection ?? (controller.hovered.map {
            $0.frame.offsetBy(dx: -shot.originCG.x, dy: -shot.originCG.y)
        }).flatMap { $0.intersects(bounds) ? $0 : nil }
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        context.addPath(dim)
        context.setFillColor(CGColor(gray: 0, alpha: 0.32))
        context.fillPath(using: .evenOdd)

        if let hole {
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
            context.setLineWidth(1)
            context.stroke(hole.insetBy(dx: -0.5, dy: -0.5))
            if selection != nil { drawSizeLabel(for: hole, in: context) }
        }

        guard let mouse, bounds.contains(mouse) else { return }
        if selection == nil && controller.mode != .window {
            drawCrosshair(at: mouse, in: context)
        }
        if controller.mode != .window {
            drawMagnifier(at: mouse, in: context)
        }
        if selection == nil && dragStart == nil {
            drawLabel(controller.mode.hint, centeredAt: CGPoint(x: bounds.midX, y: bounds.maxY - 48), in: context, size: 13)
        }
    }

    private func drawCrosshair(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
        context.setLineDash(phase: 0, lengths: [4, 4])
        let x = point.x.rounded(.down) + 0.5, y = point.y.rounded(.down) + 0.5
        context.strokeLineSegments(between: [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height),
                                             CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)])
        context.restoreGState()
    }

    /// 15 by 15 pixels around the pointer, 8 points per pixel, with the center outlined.
    private func drawMagnifier(at point: CGPoint, in context: CGContext) {
        let pixels = 15, cell: CGFloat = 8
        let side = CGFloat(pixels) * cell
        let labelHeight: CGFloat = 24
        var origin = CGPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + side > bounds.maxX - 8 { origin.x = point.x - 24 - side }
        if origin.y + side + labelHeight > bounds.maxY - 8 { origin.y = point.y - 24 - side - labelHeight }
        let box = CGRect(origin: origin, size: CGSize(width: side, height: side))

        let px = Int(point.x * shot.scale), py = Int(point.y * shot.scale)
        let half = pixels / 2
        let source = CGRect(x: px - half, y: py - half, width: pixels, height: pixels)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: CGColor(gray: 0, alpha: 0.4))
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.addPath(CGPath(roundedRect: box.insetBy(dx: -2, dy: -2), cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(CGPath(roundedRect: box, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.clip()
        let visible = source.intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))
        if !visible.isEmpty, let piece = shot.image.cropping(to: visible) {
            context.interpolationQuality = .none
            let target = CGRect(x: box.minX + (visible.minX - source.minX) * cell,
                                y: box.minY + (visible.minY - source.minY) * cell,
                                width: visible.width * cell, height: visible.height * cell)
            AnnotationRenderer.drawImage(piece, in: target, context: context)
        }
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.15))
        context.setLineWidth(0.5)
        for i in 1..<pixels {
            let offset = CGFloat(i) * cell
            context.strokeLineSegments(between: [CGPoint(x: box.minX + offset, y: box.minY), CGPoint(x: box.minX + offset, y: box.maxY),
                                                 CGPoint(x: box.minX, y: box.minY + offset), CGPoint(x: box.maxX, y: box.minY + offset)])
        }
        let center = CGRect(x: box.minX + CGFloat(half) * cell, y: box.minY + CGFloat(half) * cell, width: cell, height: cell)
        context.setLineWidth(1.5)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.stroke(center.insetBy(dx: -0.75, dy: -0.75))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.stroke(center.insetBy(dx: -2, dy: -2))
        context.restoreGState()

        let hex = PixelReader.hex(at: CGPoint(x: px, y: py), in: shot.image) ?? ""
        let text = controller.mode == .color ? hex : "\(Int(point.x)), \(Int(point.y))   \(hex)"
        drawLabel(text, centeredAt: CGPoint(x: box.midX, y: box.maxY + 4 + labelHeight / 2), in: context)
    }

    private func drawSizeLabel(for rect: CGRect, in context: CGContext) {
        let text = "\(Int((rect.width * shot.scale).rounded())) × \(Int((rect.height * shot.scale).rounded()))"
        var center = CGPoint(x: rect.midX, y: rect.maxY + 18)
        if center.y > bounds.maxY - 16 { center.y = rect.maxY - 18 }
        drawLabel(text, centeredAt: center, in: context)
    }

    private func drawLabel(_ text: String, centeredAt center: CGPoint, in context: CGContext, size: CGFloat = 12) {
        let textSize = AnnotationRenderer.textSize(text, fontSize: size, bold: false)
        let box = CGRect(x: center.x - textSize.width / 2 - 8, y: center.y - textSize.height / 2 - 3,
                         width: textSize.width + 16, height: textSize.height + 6)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.75))
        context.addPath(CGPath(roundedRect: box, cornerWidth: box.height / 2, cornerHeight: box.height / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
        AnnotationRenderer.drawText(text, at: CGPoint(x: box.minX + 8, y: box.minY + 3), fontSize: size,
                                    color: .white, bold: false, in: context)
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, rect.minX), rect.maxX), y: min(max(y, rect.minY), rect.maxY))
    }
}
