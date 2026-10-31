import AppKit
import Observation
import SnaprKit
import SwiftUI

/// One editor window's state: the capture, the marks, the tool, undo.
@Observable
final class EditorModel {
    let capture: Capture
    private(set) var state = EditorState()
    var tool: Tool = .arrow {
        didSet { if tool != .select { selectedID = nil }; canvas?.toolChanged() }
    }
    var color: RGBA = .red {
        didSet { restyleSelection { $0.color = color } }
    }
    /// 0 thin, 1 medium, 2 thick.
    var widthLevel = 1 {
        didSet { restyleSelection { $0.width = strokeWidth } }
    }
    var selectedID: UUID? { didSet { canvas?.needsDisplay = true } }
    /// The mark being drawn right now, not yet in the state.
    var draft: Annotation? { didSet { canvas?.needsDisplay = true } }
    var zoomPercent = 100

    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored weak var window: NSWindow?

    init(capture: Capture) {
        self.capture = capture
    }

    /// Stroke width in image pixels, so marks look the same on 1x and 2x captures.
    var strokeWidth: CGFloat { [2, 4, 7][widthLevel] * capture.scale }

    var selected: Annotation? { state.annotations.first { $0.id == selectedID } }

    /// The area shown, in image pixels.
    var visibleRect: CGRect { state.crop ?? CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height) }

    var title: String {
        let size = visibleRect.size
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    // MARK: Changes (each one is an undo step)

    func apply(_ new: EditorState, name: String) {
        let old = state
        guard old != new else { return }
        state = new
        window?.undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.apply(old, name: name) }
        }
        window?.undoManager?.setActionName(name)
        canvas?.stateChanged()
    }

    /// Replaces the state without an undo step, for live drags.
    func preview(_ new: EditorState) {
        state = new
        canvas?.needsDisplay = true
    }

    func add(_ annotation: Annotation) {
        var new = state
        new.annotations.append(annotation)
        apply(new, name: annotation.tool.title)
    }

    func replace(_ annotation: Annotation, from old: EditorState? = nil) {
        var new = state
        guard let index = new.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        new.annotations[index] = annotation
        if let old { state = old }
        apply(new, name: "Change")
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        var new = state
        new.annotations.removeAll { $0.id == id }
        selectedID = nil
        apply(new, name: "Delete")
    }

    func crop(to rect: CGRect) {
        var new = state
        let bounds = CGRect(x: 0, y: 0, width: capture.image.width, height: capture.image.height)
        let area = rect.integral.intersection(bounds)
        guard area.width >= 4, area.height >= 4 else { return }
        new.crop = area
        apply(new, name: "Crop")
        tool = .select
    }

    func resetCrop() {
        var new = state
        new.crop = nil
        apply(new, name: "Reset Crop")
    }

    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard var annotation = selected else { return }
        change(&annotation)
        replace(annotation)
    }

    // MARK: Output

    func rendered() -> Capture {
        let image = AnnotationRenderer.render(base: capture.image, state: state) ?? capture.image
        var source = capture.sourceRect
        if let crop = state.crop, let rect = source {
            source = CGRect(x: rect.minX + crop.minX / capture.scale, y: rect.minY + crop.minY / capture.scale,
                            width: crop.width / capture.scale, height: crop.height / capture.scale)
        }
        return Capture(image: image, scale: capture.scale, date: capture.date, sourceRect: source)
    }

    func copyImage() {
        canvas?.commitTextEditing()
        Output.copy(rendered())
        HUD.show("Copied", symbol: "checkmark.circle")
    }

    func copyText() {
        let image = rendered().image
        Task { await OCR.copyText(in: image) }
    }

    func save() {
        canvas?.commitTextEditing()
        if let url = Output.save(rendered()) {
            HUD.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "checkmark.circle")
        }
    }

    func saveAs() {
        canvas?.commitTextEditing()
        Output.saveAs(rendered(), from: window)
    }

    func pin() {
        canvas?.commitTextEditing()
        PinWindow.show(rendered())
        window?.close()
    }

    enum Zoom { case `in`, out, actual, fit }

    func zoom(_ zoom: Zoom) { canvas?.zoom(zoom) }

    /// Esc with nothing selected: copy (if Settings say so) and close.
    func finish() {
        if Prefs.escCopies { copyImage() }
        window?.close()
    }
}
