import AppKit
import Carbon.HIToolbox

/// A capture floating above every window. Drag to move, scroll to zoom,
/// double-click to edit, Esc to close.
final class PinWindow: NSPanel {
    private(set) static var all: [PinWindow] = []

    let capture: Capture
    private var zoom: CGFloat = 1
    private var translucent = false

    static func show(_ capture: Capture) {
        let window = PinWindow(capture: capture)
        all.append(window)
        window.orderFrontRegardless()
        window.makeKey()
    }

    init(capture: Capture) {
        self.capture = capture
        let screen = NSScreen.underMouse.visibleFrame
        var size = capture.pointSize
        let fit = min(1, screen.width * 0.8 / size.width, screen.height * 0.8 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        var frame = capture.sourceRect.map(appKitRect(fromCG:)) ?? .zero
        if frame.size != size || !screen.intersects(frame) {
            frame = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        }
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        zoom = fit
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = capture.pointSize
        contentView = PinView(window: self)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        Self.all.removeAll { $0 === self }
    }

    @objc func copy(_ sender: Any?) {
        Output.copy(capture)
        HUD.show("Copied", symbol: "checkmark.circle")
    }

    @objc func edit(_ sender: Any?) {
        EditorController.open(capture)
        close()
    }

    @objc func toggleTranslucent(_ sender: Any?) {
        translucent.toggle()
        alphaValue = translucent ? 0.5 : 1
    }

    @objc func setZoomFromMenu(_ sender: NSMenuItem) { setZoom(CGFloat(sender.tag) / 100) }

    @objc func closeFromMenu(_ sender: Any?) { close() }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 0.1), 4)
        let size = CGSize(width: capture.pointSize.width * zoom, height: capture.pointSize.height * zoom)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                 display: true)
    }

    func zoomBy(_ delta: CGFloat) { setZoom(zoom * (1 + delta)) }

    var isTranslucent: Bool { translucent }
}

private final class PinView: NSView {
    private unowned let pin: PinWindow
    private let closeButton: NSButton

    init(window: PinWindow) {
        pin = window
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Close"))!,
                               target: window, action: #selector(PinWindow.closeFromMenu(_:)))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = window.capture.image
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.isHidden = true
        closeButton.toolTip = String(localized: "Close (Esc)")
        closeButton.frame = CGRect(x: 6, y: 6, width: 20, height: 20)
        closeButton.autoresizingMask = [.maxXMargin, .minYMargin]
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { pin.edit(nil) } else { super.mouseDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 200 : event.scrollingDeltaY / 20
        pin.zoomBy(delta)
    }

    override func magnify(with event: NSEvent) { pin.zoomBy(event.magnification) }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { pin.close() } else { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for percent in [50, 100, 200] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(PinWindow.setZoomFromMenu(_:)), keyEquivalent: "")
            item.tag = percent
            item.target = pin
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let translucent = NSMenuItem(title: String(localized: "Semi-Transparent"), action: #selector(PinWindow.toggleTranslucent(_:)), keyEquivalent: "")
        translucent.state = pin.isTranslucent ? .on : .off
        menu.addItem(translucent)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Copy"), action: #selector(PinWindow.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: String(localized: "Edit"), action: #selector(PinWindow.edit(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Close"), action: #selector(PinWindow.closeFromMenu(_:)), keyEquivalent: ""))
        for item in menu.items where item.target == nil && !item.isSeparatorItem { item.target = pin }
        return menu
    }
}
