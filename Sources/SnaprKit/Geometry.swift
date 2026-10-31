import CoreGraphics

/// Selection math shared by the capture overlay, the editor, and the tests.
public enum SelectionGeometry {
    /// The rectangle spanned by two drag points, in either direction.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Maps a selection in view points (top-left origin) to whole image
    /// pixels, clamped to the image.
    public static func pixelRect(selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        let scaled = CGRect(x: selection.minX * sx, y: selection.minY * sy,
                            width: selection.width * sx, height: selection.height * sy)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let rounded = CGRect(x: scaled.minX.rounded(), y: scaled.minY.rounded(),
                             width: scaled.width.rounded(), height: scaled.height.rounded())
        return rounded.intersection(bounds)
    }

    /// Constrains a drag so width equals height (Shift while drawing).
    public static func square(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let side = max(abs(b.x - a.x), abs(b.y - a.y))
        return CGPoint(x: a.x + (b.x >= a.x ? side : -side), y: a.y + (b.y >= a.y ? side : -side))
    }

    /// Snaps a line end to the nearest 45 degree angle (Shift while drawing).
    public static func snap45(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }
}
