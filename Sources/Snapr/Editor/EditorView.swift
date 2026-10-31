import AppKit
import SnaprKit
import SwiftUI

/// The editor window: a toolbar of tools and styles over a zoomable canvas.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        CanvasContainer(model: model)
            .background(.background.secondary)
            .navigationTitle("Snapr")
            .navigationSubtitle(model.title)
            .toolbar { toolbar }
            .noInitialFocus()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Tool", selection: $model.tool) {
                ForEach(Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Tools: press the letter shown in each tooltip")
        }
        ToolbarItem {
            ColorSwatches(model: model)
        }
        ToolbarItem {
            Picker("Size", selection: $model.widthLevel) {
                Label("Thin", systemImage: "circle.fill").imageScale(.small).tag(0)
                Label("Medium", systemImage: "circle.fill").imageScale(.medium).tag(1)
                Label("Thick", systemImage: "circle.fill").imageScale(.large).tag(2)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Line width and text size")
        }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
            Menu {
                Button("Zoom In") { model.zoom(.in) }
                Button("Zoom Out") { model.zoom(.out) }
                Button("Actual Size") { model.zoom(.actual) }
                Button("Zoom to Fit") { model.zoom(.fit) }
            } label: {
                Text("\(model.zoomPercent)%").monospacedDigit()
            }
            .help("Zoom")
            if model.state.crop != nil {
                Button("Reset Crop", systemImage: "arrow.uturn.backward") { model.resetCrop() }
                    .help("Show the whole image again (⌥⌘R)")
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button("Copy Text", systemImage: "text.viewfinder") { model.copyText() }
                .help("Copy the text in the image (⇧⌘T)")
            Button("Pin", systemImage: "pin") { model.pin() }
                .help("Pin to screen (⌘P)")
            Button("Save", systemImage: "square.and.arrow.down") { model.save() }
                .help("Save to the screenshots folder (⌘S)")
            Button("Copy", systemImage: "doc.on.doc") { model.copyImage() }
                .buttonStyle(.borderedProminent)
                .help("Copy the image (⌘C)")
        }
    }
}

/// Preset colors plus the system color picker.
private struct ColorSwatches: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(RGBA.presets.prefix(6).enumerated()), id: \.offset) { _, rgba in
                Button {
                    model.color = rgba
                } label: {
                    Circle()
                        .fill(Color(cgColor: rgba.cgColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.separator))
                        .padding(2)
                        .overlay(Circle().strokeBorder(model.color == rgba ? Color.primary : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(name(rgba))
                .accessibilityLabel(name(rgba))
            }
            ColorPicker("Custom Color", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")
        }
        .padding(.horizontal, Space.xs)
    }

    private var colorBinding: Binding<Color> {
        Binding {
            Color(cgColor: model.color.cgColor)
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.color = RGBA(srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
        }
    }

    private func name(_ rgba: RGBA) -> String {
        switch rgba {
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .black: String(localized: "Black")
        default: String(localized: "White")
        }
    }
}

/// Hosts the AppKit canvas in a magnifying scroll view.
struct CanvasContainer: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1
        scroll.maxMagnification = 8
        scroll.drawsBackground = false
        scroll.contentView = CenteringClipView()
        scroll.contentView.drawsBackground = false
        let canvas = CanvasView(model: model)
        scroll.documentView = canvas
        model.canvas = canvas
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}
}

/// Keeps a document smaller than the window in the middle.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let size = document.frame.size
        if rect.width > size.width { rect.origin.x = (size.width - rect.width) / 2 }
        if rect.height > size.height { rect.origin.y = (size.height - rect.height) / 2 }
        return rect
    }
}
