import Foundation

/// Every setting, its key, and its default. Views bind with
/// `@AppStorage(Prefs.Key.x, store: Prefs.defaults)`.
enum Prefs {
    static let testSuite = "com.felipemancini.snapr.test"

    /// The real defaults, or a throwaway suite during tests and snapshots.
    static let defaults: UserDefaults = Store.isOverridden ? UserDefaults(suiteName: testSuite)! : .standard

    enum Key {
        static let afterCopy = "after.copy"
        static let afterSave = "after.save"
        static let afterShow = "after.show"
        static let saveFolder = "save.folder"
        static let saveFormat = "save.format"
        static let downscale = "save.downscale"
        static let windowShadow = "window.shadow"
        static let previewAutoClose = "preview.autoClose"
        static let escCopies = "editor.escCopies"
        static let ocrKeepBreaks = "ocr.keepBreaks"
        static let ocrLanguage = "ocr.language"
        static let scrollMaxHeight = "scroll.maxHeight"
        static let showMenuBarIcon = "menubar.show"
        static let urlScheme = "url.enabled"
    }

    /// What appears after a capture.
    enum AfterShow: String, CaseIterable, Identifiable {
        case preview, editor, nothing
        var id: String { rawValue }
        var title: String {
            switch self {
            case .preview: "Preview thumbnail"
            case .editor: "Editor"
            case .nothing: "Nothing"
            }
        }
    }

    enum SaveFormat: String, CaseIterable, Identifiable {
        case png, jpeg
        var id: String { rawValue }
        var title: String { self == .png ? "PNG" : "JPEG" }
        var ext: String { self == .png ? "png" : "jpg" }
    }

    static func prepare() {
        if Store.isOverridden { defaults.removePersistentDomain(forName: testSuite) }
        defaults.register(defaults: [
            Key.afterCopy: true,
            Key.afterSave: false,
            Key.afterShow: AfterShow.preview.rawValue,
            Key.saveFolder: URL.desktopDirectory.path,
            Key.saveFormat: SaveFormat.png.rawValue,
            Key.downscale: false,
            Key.windowShadow: true,
            Key.previewAutoClose: true,
            Key.escCopies: true,
            Key.ocrKeepBreaks: true,
            Key.ocrLanguage: "auto",
            Key.scrollMaxHeight: 20000,
            Key.showMenuBarIcon: true,
            Key.urlScheme: true,
        ])
    }

    static var afterCopy: Bool { defaults.bool(forKey: Key.afterCopy) }
    static var afterSave: Bool { defaults.bool(forKey: Key.afterSave) }
    static var afterShow: AfterShow { AfterShow(rawValue: defaults.string(forKey: Key.afterShow) ?? "") ?? .preview }
    static var saveFolder: URL { URL(fileURLWithPath: defaults.string(forKey: Key.saveFolder) ?? URL.desktopDirectory.path) }
    static var saveFormat: SaveFormat { SaveFormat(rawValue: defaults.string(forKey: Key.saveFormat) ?? "") ?? .png }
    static var downscale: Bool { defaults.bool(forKey: Key.downscale) }
    static var windowShadow: Bool { defaults.bool(forKey: Key.windowShadow) }
    static var previewAutoClose: Bool { defaults.bool(forKey: Key.previewAutoClose) }
    static var escCopies: Bool { defaults.bool(forKey: Key.escCopies) }
    static var ocrKeepBreaks: Bool { defaults.bool(forKey: Key.ocrKeepBreaks) }
    static var ocrLanguage: String { defaults.string(forKey: Key.ocrLanguage) ?? "auto" }
    static var scrollMaxHeight: Int { max(2000, defaults.integer(forKey: Key.scrollMaxHeight)) }
    static var urlScheme: Bool { defaults.bool(forKey: Key.urlScheme) }
}
