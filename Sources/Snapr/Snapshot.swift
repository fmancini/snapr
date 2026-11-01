import AppKit
import IOKit.pwr_mgt
import SnaprKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots /Applications/Snapr.app/Contents/MacOS/Snapr
/// writes <page>-light.png and <page>-dark.png for the editor, the preview,
/// a pin, every Help topic, and About, and settings-<tab>-light.png and -dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=editor,settings limits the pages.
enum Snapshot {
    static var requested: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    static func run() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        func wants(_ page: String) -> Bool { only?.contains(page) ?? true }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let sample = SampleImage.capture()

            if wants("editor") {
                let editor = EditorController.open(sample)
                SampleImage.annotate(editor.model)
                try? await Task.sleep(for: .seconds(1.2))
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/editor-\(mode).png", window: editor.window)
                }
                editor.window?.close()
            }
            if wants("preview") {
                PreviewPanel.show(sample)
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/preview-\(mode).png", window: PreviewPanel.window)
                }
                PreviewPanel.close()
            }
            if wants("pin") {
                PinWindow.show(sample)
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    try? await Task.sleep(for: .seconds(0.6))
                    capture(to: "\(dir)/pin-\(mode).png", window: PinWindow.all.last)
                }
                PinWindow.all.last?.close()
            }
            if wants("help") {
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    for topic in HelpTopic.allCases {
                        HelpWindow.show(topic)
                        try? await Task.sleep(for: .seconds(0.7))
                        capture(to: "\(dir)/help-\(topic.rawValue)-\(mode).png", window: HelpWindow.window)
                    }
                }
                HelpWindow.window?.close()
            }
            if wants("about") {
                AboutPanel.show()
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    try? await Task.sleep(for: .seconds(0.7))
                    capture(to: "\(dir)/about-\(mode).png", window: AboutPanel.window)
                }
                AboutPanel.window?.close()
            }
            if wants("settings") {
                for mode in ["light", "dark"] {
                    setAppearance(mode)
                    for tab in SettingsTab.allCases {
                        SettingsWindow.show(tab)
                        try? await Task.sleep(for: .seconds(0.9))
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: SettingsWindow.window)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            NSApp.terminate(nil)
        }
    }

    private static func setAppearance(_ mode: String) {
        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
    }

    /// Captures the real window with screencapture, so glass and materials
    /// look exactly as on screen. That needs Screen Recording permission for
    /// the app that started this one. Without it, draws the view hierarchy.
    private static func capture(to path: String, window: NSWindow?) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window else {
            print("SNAPSHOT no window for \(path)")
            return
        }
        window.orderFrontRegardless()
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission)")
        }
    }
}

/// A made-up screenshot for snapshots and the self-test: a small document
/// window with a heading, text lines, and a chart.
enum SampleImage {
    static let heading = "Quarterly Report"

    static func capture() -> Capture {
        let scale: CGFloat = 2
        let size = CGSize(width: 900 * scale, height: 560 * scale)
        let context = AnnotationRenderer.makeContext(size: size)!
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let card = CGRect(x: 40 * scale, y: 40 * scale, width: 820 * scale, height: 480 * scale)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: card, cornerWidth: 16 * scale, cornerHeight: 16 * scale, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: card.minX, y: card.minY + 44 * scale, width: card.width, height: 1 * scale))
        for (i, color) in [RGBA(1, 0.37, 0.34), RGBA(1, 0.74, 0.18), RGBA(0.16, 0.78, 0.25)].enumerated() {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: card.minX + CGFloat(20 + i * 20) * scale, y: card.minY + 16 * scale,
                                           width: 12 * scale, height: 12 * scale))
        }
        AnnotationRenderer.drawText(heading, at: CGPoint(x: card.minX + 32 * scale, y: card.minY + 72 * scale),
                                    fontSize: 30 * scale, color: RGBA(0.1, 0.1, 0.12), in: context)
        let lines = ["Revenue grew 18 percent over the last quarter.",
                     "Customer support response time fell to 2 hours.",
                     "Next steps: hire two engineers and ship version 2."]
        for (i, line) in lines.enumerated() {
            AnnotationRenderer.drawText(line, at: CGPoint(x: card.minX + 32 * scale, y: card.minY + CGFloat(130 + i * 34) * scale),
                                        fontSize: 18 * scale, color: RGBA(0.3, 0.3, 0.35), bold: false, in: context)
        }
        let bars: [CGFloat] = [0.45, 0.6, 0.52, 0.78, 0.9]
        for (i, value) in bars.enumerated() {
            let height = 150 * value * scale
            let x = card.minX + CGFloat(32 + i * 72) * scale
            context.setFillColor(RGBA(0.04, 0.52, 1, 0.25 + 0.15 * Double(i)).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: x, y: card.maxY - 40 * scale - height, width: 48 * scale, height: height),
                                   cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil))
            context.fillPath()
        }
        return Capture(image: context.makeImage()!, scale: scale)
    }

    /// Marks that show every kind of tool in snapshots.
    static func annotate(_ model: EditorModel) {
        let s = model.capture.scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var arrow = Annotation(tool: .arrow, start: p(620, 120), end: p(470, 175), color: .red, width: 4 * s)
        arrow.points = []
        let box = Annotation(tool: .rectangle, start: p(62, 100), end: p(360, 150), color: .red, width: 4 * s)
        var text = Annotation(tool: .text, start: p(630, 100), end: p(630, 100), color: .red, width: 4 * s)
        text.text = "Up 18%"
        var one = Annotation(tool: .counter, start: p(110, 330), end: p(110, 330), color: .blue, width: 4 * s)
        one.number = 1
        var two = Annotation(tool: .counter, start: p(326, 270), end: p(326, 270), color: .blue, width: 4 * s)
        two.number = 2
        let blur = Annotation(tool: .blur, start: p(400, 205), end: p(560, 230), color: .red, width: 4 * s)
        var marker = Annotation(tool: .highlighter, start: p(72, 192), end: p(380, 192), color: .yellow, width: 4 * s)
        marker.points = [p(72, 192), p(380, 192)]
        model.apply(EditorState(annotations: [box, arrow, text, marker, blur, one, two]), name: "Sample")
    }
}
