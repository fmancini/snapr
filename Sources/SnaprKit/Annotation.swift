import CoreGraphics
import Foundation

/// A color with alpha, stored as plain numbers so it stays Sendable.
public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    /// White or black, whichever reads better on this color.
    public var contrasting: RGBA {
        (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? RGBA(0, 0, 0) : RGBA(1, 1, 1)
    }

    public static let red = RGBA(0.96, 0.23, 0.25)
    public static let orange = RGBA(1, 0.58, 0.0)
    public static let yellow = RGBA(1, 0.84, 0.04)
    public static let green = RGBA(0.2, 0.78, 0.35)
    public static let blue = RGBA(0.04, 0.52, 1)
    public static let purple = RGBA(0.69, 0.32, 0.87)
    public static let black = RGBA(0.1, 0.1, 0.1)
    public static let white = RGBA(1, 1, 1)
    public static let presets: [RGBA] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

/// The editor tools. The order is the toolbar order.
public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select, arrow, rectangle, oval, line, freehand, highlighter, text, counter, blur, spotlight, crop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .freehand: "Draw"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Step Counter"
        case .blur: "Pixelate"
        case .spotlight: "Spotlight"
        case .crop: "Crop"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .oval: "circle"
        case .line: "line.diagonal"
        case .freehand: "scribble"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "checkerboard.rectangle"
        case .spotlight: "light.max"
        case .crop: "crop"
        }
    }

    /// The single key that picks the tool in the editor.
    public var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .oval: "o"
        case .line: "l"
        case .freehand: "d"
        case .highlighter: "h"
        case .text: "t"
        case .counter: "c"
        case .blur: "b"
        case .spotlight: "s"
        case .crop: "x"
        }
    }

    public static func forKey(_ key: Character) -> Tool? {
        allCases.first { $0.key == Character(key.lowercased()) }
    }

    /// Tools that leave an annotation on the image.
    public var draws: Bool { self != .select && self != .crop }
    /// Tools drawn from a list of points rather than two corners.
    public var isPath: Bool { self == .freehand || self == .highlighter }
}

/// One mark on the image. Geometry is in image pixels, top-left origin.
public struct Annotation: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var tool: Tool
    public var start: CGPoint
    public var end: CGPoint
    public var points: [CGPoint] = []
    public var color: RGBA
    /// Stroke width in pixels. Text and counters scale from it.
    public var width: CGFloat
    public var text: String = ""
    public var number: Int = 0

    public init(tool: Tool, start: CGPoint, end: CGPoint, color: RGBA, width: CGFloat) {
        self.tool = tool
        self.start = start
        self.end = end
        self.color = color
        self.width = width
    }

    public var rect: CGRect { SelectionGeometry.rect(from: start, to: end) }
    public var fontSize: CGFloat { max(12, width * 5) }
    public var counterDiameter: CGFloat { max(20, width * 7) }

    /// The area the mark covers, for hit testing and selection outlines.
    public var bounds: CGRect {
        let pad = width / 2 + 2
        switch tool {
        case .text:
            let size = AnnotationRenderer.textSize(text.isEmpty ? " " : text, fontSize: fontSize)
            return CGRect(origin: start, size: size).insetBy(dx: -4, dy: -4)
        case .counter:
            let d = counterDiameter
            return CGRect(x: start.x - d / 2, y: start.y - d / 2, width: d, height: d)
        case .freehand, .highlighter:
            guard let first = points.first else { return rect }
            var box = CGRect(origin: first, size: .zero)
            for p in points { box = box.union(CGRect(origin: p, size: .zero)) }
            return box.insetBy(dx: -pad * (tool == .highlighter ? 3 : 1), dy: -pad * (tool == .highlighter ? 3 : 1))
        default:
            return rect.insetBy(dx: -pad, dy: -pad)
        }
    }

    /// True when a click at `point` should pick this mark.
    public func hit(_ point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        switch tool {
        case .arrow, .line:
            return Self.distance(point, toSegment: start, end) <= width / 2 + tolerance
        case .rectangle, .oval:
            let outer = rect.insetBy(dx: -width / 2 - tolerance, dy: -width / 2 - tolerance)
            let inner = rect.insetBy(dx: width / 2 + tolerance, dy: width / 2 + tolerance)
            return outer.contains(point) && (inner.isNull || !inner.contains(point))
        case .freehand, .highlighter:
            let reach = (tool == .highlighter ? width * 2 : width / 2) + tolerance
            return zip(points, points.dropFirst()).contains { Self.distance(point, toSegment: $0, $1) <= reach }
        default:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    public func moved(by delta: CGVector) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        copy.end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        copy.points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        return copy
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Everything an undo step restores: the marks and the crop.
public struct EditorState: Equatable, Sendable {
    public var annotations: [Annotation] = []
    /// Crop in image pixels, or nil for the whole image.
    public var crop: CGRect?

    public init(annotations: [Annotation] = [], crop: CGRect? = nil) {
        self.annotations = annotations
        self.crop = crop
    }

    /// The number the next step counter gets.
    public var nextCounter: Int {
        (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
    }

    /// The topmost mark under a point.
    public func annotation(at point: CGPoint) -> Annotation? {
        annotations.last { $0.hit(point) }
    }
}
