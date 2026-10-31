import AppKit
import ImageIO
import SnaprKit

/// Self-test for agents: runs the app's real functions, prints PASS or FAIL
/// per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Snapr-self.store /Applications/Snapr.app/Contents/MacOS/Snapr --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            let sample = SampleImage.capture()

            // S-007 hotkeys
            let center = HotkeyCenter.shared
            check("default area shortcut is ⇧⌘2", center.shortcut(for: .area)?.display == "⇧⌘2")
            center.set(Shortcut(key: 0x11, command: true, option: true, control: true), for: .text) // T
            check("a changed shortcut is stored", center.shortcut(for: .text)?.display == "⌃⌥⌘T")
            center.set(nil, for: .text)
            check("a cleared shortcut stays cleared", center.shortcut(for: .text) == nil)
            center.resetAll()
            check("restore defaults brings shortcuts back", center.shortcut(for: .text) != nil)

            // S-030 URL scheme
            check("snapr://grab/area maps to area", CaptureAction(url: URL(string: "snapr://grab/area")!) == .area)
            check("snapr://ocr maps to text", CaptureAction(url: URL(string: "snapr://ocr")!) == .text)
            check("unknown links are ignored", CaptureAction(url: URL(string: "snapr://nope")!) == nil)

            // S-006 copy and save
            let board = NSPasteboard(name: NSPasteboard.Name("com.felipemancini.snapr.selftest"))
            Output.copy(sample, to: board)
            let pasted = NSImage(pasteboard: board)
            check("copy puts the image at its point size", pasted?.size == sample.pointSize, "\(pasted?.size ?? .zero)")
            check("copy includes PNG data", board.data(forType: .png) != nil)
            let folder = URL(fileURLWithPath: "/tmp/Snapr-selftest-saves", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            let first = Output.save(sample, folder: folder)
            let second = Output.save(sample, folder: folder)
            check("save writes a dated PNG", first?.lastPathComponent.hasPrefix("Snapr ") == true && first.map { FileManager.default.fileExists(atPath: $0.path) } == true)
            check("a second save in the same second gets a new name", second != nil && second != first)
            if let first, let source = CGImageSourceCreateWithURL(first as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                check("the saved file keeps full resolution", image.width == sample.image.width)
            } else {
                check("the saved file can be read back", false)
            }

            // S-011 to S-013 editor
            let editor = EditorController.open(sample)
            let model = editor.model
            model.add(Annotation(tool: .rectangle, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 400, y: 300), color: .red, width: 8))
            check("drawing adds a mark", model.state.annotations.count == 1)
            editor.window?.undoManager?.undo()
            check("undo removes the mark", model.state.annotations.isEmpty)
            editor.window?.undoManager?.redo()
            check("redo brings it back", model.state.annotations.count == 1)
            model.crop(to: CGRect(x: 50, y: 60, width: 500, height: 300))
            let rendered = model.rendered()
            check("crop sets the output size", rendered.image.width == 500 && rendered.image.height == 300)
            model.resetCrop()
            check("reset crop shows the whole image", model.rendered().image.width == sample.image.width)
            editor.window?.close()

            // S-020 OCR
            let result = await OCR.recognize(sample.image, keepLineBreaks: true, language: "auto")
            check("OCR reads the heading", result?.text.contains("Quarterly") == true, result?.text.prefix(60).description ?? "nil")
            check("OCR keeps one line per row", (result?.lineCount ?? 0) >= 4)

            // S-024 stitching on the real sample
            let top = sample.image.cropping(to: CGRect(x: 0, y: 0, width: sample.image.width, height: 600))!
            let lower = sample.image.cropping(to: CGRect(x: 0, y: 200, width: sample.image.width, height: 600))!
            check("stitching finds a 200 px scroll", Stitcher.offset(previous: top, next: lower) == 200)

            // S-021 color
            check("color under a pixel reads as hex", PixelReader.hex(at: CGPoint(x: 4, y: 4), in: sample.image) != nil)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
