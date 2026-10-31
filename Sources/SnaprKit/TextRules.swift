import Foundation

/// Joins recognized text lines.
public enum OCRText {
    /// Keeps the line breaks, or joins lines with spaces. A word split with a
    /// hyphen at the end of a line is joined back together.
    public static func join(_ lines: [String], keepLineBreaks: Bool) -> String {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if keepLineBreaks { return trimmed.joined(separator: "\n") }
        var text = ""
        for line in trimmed {
            if text.hasSuffix("-"), let first = line.first, first.isLowercase {
                text.removeLast()
                text += line
            } else {
                text += text.isEmpty ? line : " " + line
            }
        }
        return text
    }
}

/// File names for saved captures: "Snapr 2026-10-31 at 20.15.03.png".
public enum CaptureFileName {
    public static func make(date: Date, ext: String = "png", prefix: String = "Snapr") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(ext)"
    }

    /// Adds " 2", " 3" before the extension until the name is free.
    public static func unique(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while exists("\(base) \(n).\(ext)") { n += 1 }
        return "\(base) \(n).\(ext)"
    }
}

/// "#1A2B3C" from 8-bit color channels.
public enum HexColor {
    public static func string(r: UInt8, g: UInt8, b: UInt8) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}
