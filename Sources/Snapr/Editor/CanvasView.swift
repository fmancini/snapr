import AppKit
import Carbon.HIToolbox
import SnaprKit

/// Draws the capture with its marks and turns mouse drags into marks.
/// The view is measured in points; marks are stored in image pixels.
final class CanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var dragStart: CGPoint?
    private var moveOrigin: EditorState?
    private var cropRect: CGRect?
    private var textField: NSTextField?
    private var editingText: Annotation?
    private var magnificationObserver: NSObjectProtocol?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        resize()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat { model.capture.scale }
    private var scrollView: NSScrollView? { enclosingScrollView }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let scrollView, magnificationObserver == nil else { return }
        magnificationObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateZoomLabel() }
        }
    }

    // MARK: Model callbacks

    func stateChanged() {
        resize()
        needsDisplay = true
    }

    func toolChanged() {
        commitTextEditing()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func resize() {
        let visible = model.visibleRect
        let size = CGSize(width: visible.width / scale, height: visible.height / scale)
        if frame.size != size { setFrameSize(size) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .select ? .arrow : model.tool == .text ? .iBeam : .crosshair)
    }

    // MARK: Coordinates

    /// View point to image pixel.
    private func pixel(_ point: CGPoint) -> CGPoint {
        let origin = model.visibleRect.origin
        return CGPoint(x: point.x * scale + origin.x, y: point.y * scale + origin.y)
    }

    /// Image pixel rect to view rect.
    private func viewRect(_ rect: CGRect) -> CGRect {
        let origin = model.visibleRect.origin
        return CGRect(x: (rect.minX - origin.x) / scale, y: (rect.minY - origin.y) / scale,
                      width: rect.width / scale, height: rect.height / scale)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        let origin = model.visibleRect.origin
        context.translateBy(x: -origin.x, y: -origin.y)
        context.interpolationQuality = (scrollView?.magnification ?? 1) > 2 ? .none : .high
        var marks = model.state.annotations.filter { $0.id != editingText?.id }
        if let draft = model.draft { marks.append(draft) }
        AnnotationRenderer.draw(base: model.capture.image, annotations: marks, in: context)
        context.restoreGState()

        if let selected = model.selected {
            let rect = viewRect(selected.bounds)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1 / (scrollView?.magnification ?? 1))
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(rect)
            context.setLineDash(phase: 0, lengths: [])
        }
        if let cropRect {
            let rect = viewRect(cropRect)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(rect)
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0, alpha: 0.45))
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(1)
            context.stroke(rect)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = pixel(convert(event.locationInWindow, from: nil))
        commitTextEditing()
        dragStart = point
        switch model.tool {
        case .select:
            if let hit = model.state.annotation(at: point) {
                model.selectedID = hit.id
                moveOrigin = model.state
                if event.clickCount == 2, hit.tool == .text { beginTextEditing(hit) }
            } else {
                model.selectedID = nil
            }
        case .text:
            if let hit = model.state.annotation(at: point), hit.tool == .text {
                beginTextEditing(hit)
            } else {
                var text = Annotation(tool: .text, start: point, end: point, color: model.color, width: model.strokeWidth)
                text.text = ""
                beginTextEditing(text)
            }
            dragStart = nil
        case .counter:
            var counter = Annotation(tool: .counter, start: point, end: point, color: model.color, width: model.strokeWidth)
            counter.number = model.state.nextCounter
            model.add(counter)
            dragStart = nil
        case .crop:
            cropRect = CGRect(origin: point, size: .zero)
        default:
            var draft = Annotation(tool: model.tool, start: point, end: point, color: model.color, width: model.strokeWidth)
            draft.points = [point]
            model.draft = draft
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        autoscroll(with: event)
        var point = pixel(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch model.tool {
        case .select:
            guard let origin = moveOrigin, let id = model.selectedID,
                  let original = origin.annotations.first(where: { $0.id == id }) else { return }
            var state = origin
            if let index = state.annotations.firstIndex(where: { $0.id == id }) {
                state.annotations[index] = original.moved(by: CGVector(dx: point.x - start.x, dy: point.y - start.y))
            }
            model.preview(state)
        case .crop:
            if shift { point = SelectionGeometry.square(from: start, to: point) }
            cropRect = SelectionGeometry.rect(from: start, to: point)
            needsDisplay = true
        default:
            guard var draft = model.draft else { return }
            if shift {
                switch draft.tool {
                case .arrow, .line: point = SelectionGeometry.snap45(from: start, to: point)
                case .rectangle, .oval, .blur, .spotlight: point = SelectionGeometry.square(from: start, to: point)
                default: break
                }
            }
            draft.end = point
            if draft.tool.isPath { draft.points.append(point) }
            model.draft = draft
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; moveOrigin = nil }
        switch model.tool {
        case .select:
            if let origin = moveOrigin, origin != model.state, let selected = model.selected {
                model.replace(selected, from: origin)
            }
        case .crop:
            if let rect = cropRect { model.crop(to: rect) }
            cropRect = nil
            needsDisplay = true
        default:
            guard let draft = model.draft else { return }
            model.draft = nil
            let big = draft.tool.isPath ? draft.points.count > 1 : (draft.rect.width > 3 || draft.rect.height > 3)
            if big { model.add(draft) }
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.selectedID != nil { model.selectedID = nil } else { model.finish() }
            return
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelection()
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            if nudge(event) { return }
        default:
            break
        }
        if flags.isEmpty, let character = event.charactersIgnoringModifiers?.first {
            if let tool = Tool.forKey(character) { model.tool = tool; return }
            if let digit = Int(String(character)), (1...6).contains(digit) {
                model.color = RGBA.presets[digit - 1]
                return
            }
        }
        super.keyDown(with: event)
    }

    private func nudge(_ event: NSEvent) -> Bool {
        guard var selected = model.selected else { return false }
        let step = (event.modifierFlags.contains(.shift) ? 10 : 1) * scale
        let delta: CGVector = switch Int(event.keyCode) {
        case kVK_LeftArrow: CGVector(dx: -step, dy: 0)
        case kVK_RightArrow: CGVector(dx: step, dy: 0)
        case kVK_UpArrow: CGVector(dx: 0, dy: -step)
        default: CGVector(dx: 0, dy: step)
        }
        selected = selected.moved(by: delta)
        model.replace(selected)
        return true
    }

    @objc func copy(_ sender: Any?) { model.copyImage() }

    @objc func delete(_ sender: Any?) { model.deleteSelection() }

    // MARK: Text

    private func beginTextEditing(_ annotation: Annotation) {
        editingText = annotation
        let fontSize = annotation.fontSize / scale
        let field = NSTextField(string: annotation.text)
        field.font = .systemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = NSColor(cgColor: annotation.color.cgColor)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = "Text"
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        let origin = viewRect(CGRect(origin: annotation.start, size: .zero)).origin
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(160, fontSize * 10), height: fontSize * 1.4)
        addSubview(field)
        textField = field
        needsDisplay = true
        window?.makeFirstResponder(field)
    }

    func commitTextEditing() {
        guard let field = textField, var annotation = editingText else { return }
        textField = nil
        editingText = nil
        field.removeFromSuperview()
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        annotation.text = text
        let exists = model.state.annotations.contains { $0.id == annotation.id }
        if text.isEmpty {
            if exists { model.selectedID = annotation.id; model.deleteSelection() }
        } else if exists {
            model.replace(annotation)
        } else {
            model.add(annotation)
        }
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func cancelTextEditing() {
        textField?.removeFromSuperview()
        textField = nil
        editingText = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelTextEditing(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { commitTextEditing(); return true }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField else { return }
        let needed = field.intrinsicContentSize.width + 20
        if needed > field.frame.width { field.frame.size.width = needed }
    }

    // MARK: Zoom

    func zoomToInitial() {
        guard let scrollView else { return }
        let available = scrollView.contentView.bounds.size
        if bounds.width > available.width - 40 || bounds.height > available.height - 40 {
            zoom(.fit)
        } else {
            scrollView.magnification = 1
        }
        updateZoomLabel()
    }

    func zoom(_ zoom: EditorModel.Zoom) {
        guard let scrollView else { return }
        switch zoom {
        case .in: scrollView.animator().magnification = min(scrollView.magnification * 1.25, scrollView.maxMagnification)
        case .out: scrollView.animator().magnification = max(scrollView.magnification / 1.25, scrollView.minMagnification)
        case .actual: scrollView.animator().magnification = 1
        case .fit:
            let available = scrollView.frame.size
            let fit = min((available.width - 48) / bounds.width, (available.height - 48) / bounds.height, 1)
            scrollView.magnification = max(fit, scrollView.minMagnification)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.updateZoomLabel() }
    }

    private func updateZoomLabel() {
        model.zoomPercent = Int(((scrollView?.magnification ?? 1) * 100).rounded())
    }
}
