import CoreGraphics

/// Joins the frames of a scrolling capture into one tall image.
public enum Stitcher {
    /// Each row of the image as `columns` gray samples. Rows stay 1:1, so a
    /// scroll of N pixels shifts the rows by exactly N.
    public static func signatures(_ image: CGImage, columns: Int = 48) -> [[UInt8]]? {
        let height = image.height
        guard height > 0, let context = CGContext(data: nil, width: columns, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * height)
        // Bitmap row 0 is the top row of the image.
        return (0..<height).map { row in Array(UnsafeBufferPointer(start: bytes + row * columns, count: columns)) }
    }

    /// How many pixels `next` scrolled past `previous`: 0 when nothing moved,
    /// nil when no offset matches (the content changed, or it scrolled more
    /// than one frame).
    public static func offset(previous: CGImage, next: CGImage, minOverlap: Int = 24) -> Int? {
        guard previous.height == next.height, let a = signatures(previous), let b = signatures(next) else { return nil }
        return offset(a, b, minOverlap: minOverlap)
    }

    public static func offset(_ a: [[UInt8]], _ b: [[UInt8]], minOverlap: Int = 24) -> Int? {
        let height = a.count
        guard height == b.count, height > minOverlap else { return nil }
        let columns = a.first?.count ?? 0
        // Rows that are one flat color match anywhere; skip them in the score.
        let busy = (0..<height).filter { row in
            guard let lo = b[row].min(), let hi = b[row].max() else { return false }
            return hi - lo > 8
        }
        guard busy.count >= 4 else { return nil }
        var best = (dy: -1, score: Double.infinity)
        for dy in 0...(height - minOverlap) {
            let rows = busy.filter { $0 + dy < height }
            guard rows.count >= max(4, busy.count / 8) else { continue }
            let limit = best.score * Double(rows.count * columns)
            var total = 0
            var stopped = false
            for row in rows {
                let x = a[row + dy], y = b[row]
                for c in 0..<columns { total += abs(Int(x[c]) - Int(y[c])) }
                if Double(total) > limit { stopped = true; break }
            }
            if stopped { continue }
            let score = Double(total) / Double(rows.count * columns)
            if score < best.score { best = (dy, score) }
            if score == 0 && dy > 0 { break }
        }
        return best.score <= 3 ? best.dy : nil
    }

    /// Stacks the frames: all of the first, then the new bottom rows of each
    /// following frame. `offsets[i]` is how far frame i scrolled past frame i-1.
    public static func compose(_ frames: [CGImage], offsets: [Int]) -> CGImage? {
        guard let first = frames.first, frames.count == offsets.count + 1 else { return nil }
        let width = first.width
        let height = first.height + offsets.reduce(0, +)
        guard let context = AnnotationRenderer.makeContext(size: CGSize(width: width, height: height)) else { return nil }
        AnnotationRenderer.drawImage(first, in: CGRect(x: 0, y: 0, width: width, height: first.height), context: context)
        var y = first.height
        for (frame, dy) in zip(frames.dropFirst(), offsets) where dy > 0 {
            guard let strip = frame.cropping(to: CGRect(x: 0, y: frame.height - dy, width: frame.width, height: dy)) else { continue }
            AnnotationRenderer.drawImage(strip, in: CGRect(x: 0, y: y, width: width, height: dy), context: context)
            y += dy
        }
        return context.makeImage()
    }
}

/// Reads single pixels from a CGImage.
public enum PixelReader {
    /// The sRGB color of the pixel at (x, y), top-left origin.
    public static func rgb(at point: CGPoint, in image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8)? {
        let x = Int(point.x), y = Int(point.y)
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return ok ? (bytes[0], bytes[1], bytes[2]) : nil
    }

    public static func hex(at point: CGPoint, in image: CGImage) -> String? {
        rgb(at: point, in: image).map { HexColor.string(r: $0.r, g: $0.g, b: $0.b) }
    }
}
