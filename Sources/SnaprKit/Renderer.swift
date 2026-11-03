import CoreGraphics
import CoreText
import Foundation

/// Draws a base image and its marks. One code path serves the live canvas
/// and the exported image. Every function expects a flipped context
/// (top-left origin) measured in image pixels.
public enum AnnotationRenderer {
    /// The image with every mark, cropped. This is what Copy and Save use.
    public static func render(base: CGImage, state: EditorState) -> CGImage? {
        let size = CGSize(width: base.width, height: base.height)
        guard let context = makeContext(size: size) else { return nil }
        draw(base: base, annotations: state.annotations, in: context)
        guard let full = context.makeImage() else { return nil }
        guard let crop = state.crop?.integral.intersection(CGRect(origin: .zero, size: size)),
              !crop.isEmpty else { return full }
        return full.cropping(to: crop)
    }

    /// A flipped sRGB bitmap context of the given pixel size.
    public static func makeContext(size: CGSize) -> CGContext? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        return context
    }

    public static func draw(base: CGImage, annotations: [Annotation], in context: CGContext) {
        drawImage(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), context: context)
        for annotation in annotations where annotation.tool != .spotlight {
            draw(annotation, base: base, in: context)
        }
        let spots = annotations.filter { $0.tool == .spotlight }.map(\.rect)
        if !spots.isEmpty {
            drawSpotlight(spots, size: CGSize(width: base.width, height: base.height), in: context)
        }
    }

    /// Draws a CGImage right side up into a flipped context.
    public static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    public static func draw(_ a: Annotation, base: CGImage, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(a.color.cgColor)
        context.setFillColor(a.color.cgColor)
        context.setLineWidth(a.width)
        let shadow = { context.setShadow(offset: CGSize(width: 0, height: a.width / 3), blur: a.width,
                                         color: CGColor(gray: 0, alpha: 0.35)) }
        switch a.tool {
        case .arrow:
            shadow()
            drawArrow(from: a.start, to: a.end, width: a.width, in: context)
        case .line:
            shadow()
            context.strokeLineSegments(between: [a.start, a.end])
        case .rectangle:
            shadow()
            context.addPath(CGPath(roundedRect: a.rect, cornerWidth: min(a.width, a.rect.width / 2),
                                   cornerHeight: min(a.width, a.rect.height / 2), transform: nil))
            context.strokePath()
        case .oval:
            shadow()
            context.strokeEllipse(in: a.rect)
        case .freehand:
            shadow()
            strokePath(a.points.isEmpty ? [a.start, a.end] : a.points, in: context)
        case .highlighter:
            context.setBlendMode(.multiply)
            context.setStrokeColor(a.color.with(alpha: 0.45).cgColor)
            context.setLineWidth(a.width * 4)
            context.setLineCap(.square)
            strokePath(a.points.isEmpty ? [a.start, a.end] : a.points, in: context)
        case .text:
            shadow()
            drawText(a.text, at: a.start, fontSize: a.fontSize, color: a.color, in: context)
        case .counter:
            shadow()
            let d = a.counterDiameter
            context.fillEllipse(in: CGRect(x: a.start.x - d / 2, y: a.start.y - d / 2, width: d, height: d))
            context.setShadow(offset: .zero, blur: 0, color: nil)
            let label = "\(a.number)"
            let fontSize = d * 0.55
            let size = textSize(label, fontSize: fontSize, bold: true)
            drawText(label, at: CGPoint(x: a.start.x - size.width / 2, y: a.start.y - size.height / 2),
                     fontSize: fontSize, color: a.color.contrasting, bold: true, in: context)
        case .blur:
            pixelate(a.rect, base: base, block: max(8, a.width * 3), in: context)
        case .spotlight, .select, .crop:
            break
        }
    }

    static func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: first)
        if points.count < 3 {
            for p in points.dropFirst() { path.addLine(to: p) }
        } else {
            // Midpoint quadratic curves smooth the mouse samples.
            for i in 1..<points.count - 1 {
                let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: points[i])
            }
            path.addLine(to: points[points.count - 1])
        }
        context.addPath(path)
        context.strokePath()
    }

    static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0.5 else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = min(max(width * 4.5, 14), length * 0.8)
        let spread: CGFloat = .pi / 7
        let base = CGPoint(x: end.x - cos(angle) * head * 0.75, y: end.y - sin(angle) * head * 0.75)
        context.strokeLineSegments(between: [start, base])
        let left = CGPoint(x: end.x - cos(angle - spread) * head, y: end.y - sin(angle - spread) * head)
        let right = CGPoint(x: end.x - cos(angle + spread) * head, y: end.y - sin(angle + spread) * head)
        context.beginPath()
        context.move(to: end)
        context.addLine(to: left)
        context.addQuadCurve(to: right, control: base)
        context.closePath()
        context.setLineWidth(max(1, width / 3))
        context.drawPath(using: .fillStroke)
    }

    static func pixelate(_ rect: CGRect, base: CGImage, block: CGFloat, in context: CGContext) {
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !area.isEmpty, let piece = base.cropping(to: area) else { return }
        let w = max(1, Int((area.width / block).rounded(.up)))
        let h = max(1, Int((area.height / block).rounded(.up)))
        guard let small = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let tiny = small.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        drawImage(tiny, in: area, context: context)
        context.restoreGState()
    }

    static func drawSpotlight(_ rects: [CGRect], size: CGSize, in context: CGContext) {
        context.saveGState()
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        for rect in rects {
            path.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)) // grid: ok exported image pixels
        }
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 0.5))
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    // MARK: Text

    static func font(size: CGFloat, bold: Bool) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        return base ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func lines(_ text: String, fontSize: CGFloat, color: RGBA, bold: Bool) -> [CTLine] {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: fontSize, bold: bold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return text.components(separatedBy: "\n").map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes))
        }
    }

    /// The size a text mark takes, top-left anchored.
    public static func textSize(_ text: String, fontSize: CGFloat, bold: Bool = true) -> CGSize {
        let all = lines(text, fontSize: fontSize, color: .black, bold: bold)
        let lineHeight = fontSize * 1.25
        let width = all.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return CGSize(width: ceil(width), height: ceil(lineHeight * CGFloat(all.count)))
    }

    /// Draws text with its top-left corner at `origin`.
    public static func drawText(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: RGBA,
                                bold: Bool = true, in context: CGContext) {
        let lineHeight = fontSize * 1.25
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in lines(text, fontSize: fontSize, color: color, bold: bold).enumerated() {
            var ascent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, nil, nil)
            let baseline = origin.y + CGFloat(index) * lineHeight + (lineHeight - fontSize) / 2 + ascent
            context.textPosition = CGPoint(x: origin.x, y: baseline)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
