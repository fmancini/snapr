import CoreGraphics
import Foundation
import Testing
@testable import SnaprKit

@Test func rectFromDragInAnyDirection() {
    let rect = SelectionGeometry.rect(from: CGPoint(x: 50, y: 40), to: CGPoint(x: 10, y: 100))
    #expect(rect == CGRect(x: 10, y: 40, width: 40, height: 60))
}

@Test func selectionMapsToRetinaPixels() {
    let px = SelectionGeometry.pixelRect(selection: CGRect(x: 10, y: 20, width: 100, height: 50),
                                         viewSize: CGSize(width: 1000, height: 600),
                                         imageSize: CGSize(width: 2000, height: 1200))
    #expect(px == CGRect(x: 20, y: 40, width: 200, height: 100))
}

@Test func selectionIsClampedToImage() {
    let px = SelectionGeometry.pixelRect(selection: CGRect(x: 900, y: 500, width: 300, height: 300),
                                         viewSize: CGSize(width: 1000, height: 600),
                                         imageSize: CGSize(width: 1000, height: 600))
    #expect(px == CGRect(x: 900, y: 500, width: 100, height: 100))
}

@Test func shortcutDisplay() {
    let shortcut = Shortcut(key: 0x13, command: true, shift: true) // kVK_ANSI_2
    #expect(shortcut.display == "⇧⌘2")
    #expect(shortcut.isValid)
    #expect(!Shortcut(key: 0x13, shift: true).isValid)
}

@Test("OCR line joining", arguments: [
    (["Hello", "world"], false, "Hello world"),
    (["Hello", "world"], true, "Hello\nworld"),
    (["inter-", "national"], false, "international"),
    (["  a ", "", "b"], false, "a b"),
])
func joinsLines(_ lines: [String], keep: Bool, expected: String) {
    #expect(OCRText.join(lines, keepLineBreaks: keep) == expected)
}

@Test func fileNames() {
    var parts = DateComponents()
    parts.year = 2026; parts.month = 10; parts.day = 31; parts.hour = 20; parts.minute = 5; parts.second = 9
    let date = Calendar(identifier: .gregorian).date(from: parts)!
    #expect(CaptureFileName.make(date: date) == "Snapr 2026-10-31 at 20.05.09.png")
    let taken: Set = ["a.png", "a 2.png"]
    #expect(CaptureFileName.unique("a.png") { taken.contains($0) } == "a 3.png")
}

@Test func counterNumbersIncrease() {
    var state = EditorState()
    #expect(state.nextCounter == 1)
    var counter = Annotation(tool: .counter, start: .zero, end: .zero, color: .red, width: 4)
    counter.number = 1
    state.annotations.append(counter)
    #expect(state.nextCounter == 2)
}

@Test func hitTestsArrowAndRectangleOutline() {
    let arrow = Annotation(tool: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), color: .red, width: 4)
    #expect(arrow.hit(CGPoint(x: 50, y: 3)))
    #expect(!arrow.hit(CGPoint(x: 50, y: 30)))
    let box = Annotation(tool: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), color: .red, width: 4)
    #expect(box.hit(CGPoint(x: 0, y: 50)))
    #expect(!box.hit(CGPoint(x: 50, y: 50)))
}

/// An image whose rows are distinct noise, so every scroll offset is unique.
func noiseImage(width: Int, height: Int, seed: UInt64) -> CGImage {
    var rng = seed
    let context = AnnotationRenderer.makeContext(size: CGSize(width: width, height: height))!
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 8) {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let v = Double((rng >> 33) % 256) / 255
            context.setFillColor(CGColor(gray: v, alpha: 1))
            context.fill(CGRect(x: x, y: y, width: 8, height: 2))
        }
    }
    return context.makeImage()!
}

@Test func stitcherFindsScrollOffset() throws {
    let page = noiseImage(width: 200, height: 600, seed: 7)
    let a = try #require(page.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 300)))
    let b = try #require(page.cropping(to: CGRect(x: 0, y: 120, width: 200, height: 300)))
    #expect(Stitcher.offset(previous: a, next: b) == 120)
    #expect(Stitcher.offset(previous: a, next: a) == 0)
    let joined = try #require(Stitcher.compose([a, b], offsets: [120]))
    #expect(joined.height == 420)
}

@Test func rendererDrawsMarksAndCrops() throws {
    let context = AnnotationRenderer.makeContext(size: CGSize(width: 100, height: 80))!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
    let base = try #require(context.makeImage())
    var box = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 50), color: .red, width: 4)
    box.id = UUID()
    let image = try #require(AnnotationRenderer.render(base: base, state: EditorState(annotations: [box])))
    let edge = try #require(PixelReader.rgb(at: CGPoint(x: 35, y: 10), in: image))
    #expect(edge.r > 200 && edge.g < 120)
    let inside = try #require(PixelReader.rgb(at: CGPoint(x: 35, y: 30), in: image))
    #expect(inside.r > 240 && inside.g > 240)
    let cropped = try #require(AnnotationRenderer.render(base: base, state: EditorState(crop: CGRect(x: 0, y: 0, width: 40, height: 30))))
    #expect(cropped.width == 40 && cropped.height == 30)
}

@Test func hexColor() {
    #expect(HexColor.string(r: 255, g: 10, b: 0) == "#FF0A00")
}
