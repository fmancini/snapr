import AppKit
@preconcurrency import ScreenCaptureKit

/// One captured image and how many pixels make a point.
struct Capture {
    var image: CGImage
    var scale: CGFloat
    var date = Date.now
    /// Where it came from on screen, in global top-left points. Pins open there.
    var sourceRect: CGRect?

    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
}

/// A frozen picture of one display, taken before the overlay opens.
struct DisplayShot {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let image: CGImage

    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }
    /// The display's top-left corner in global top-left (CG) points.
    var originCG: CGPoint { screen.originCG }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Top-left corner in global CG coordinates (origin at the top-left of the main display).
    var originCG: CGPoint {
        let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGPoint(x: frame.minX, y: mainHeight - frame.maxY)
    }

    static var underMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main ?? screens[0]
    }
}

/// Converts a global CG rect (top-left origin) to an AppKit rect (bottom-left).
func appKitRect(fromCG rect: CGRect) -> CGRect {
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
}

enum CaptureError: LocalizedError {
    case noPermission, noDisplay, noWindow

    var errorDescription: String? {
        switch self {
        case .noPermission: "Snapr needs Screen Recording to take screenshots."
        case .noDisplay: "The display is not available."
        case .noWindow: "The window is not available."
        }
    }
}

/// Screenshots through ScreenCaptureKit.
enum ScreenCapturer {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// True when capture may go ahead. Otherwise asks once, then explains.
    static func ensurePermission() -> Bool {
        if hasPermission { return true }
        if !CGRequestScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Allow Screen Recording"
            alert.informativeText = "Snapr needs Screen Recording to take screenshots. Turn on Snapr in System Settings > Privacy & Security > Screen & System Audio Recording, then try again."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { Permissions.openScreenRecordingSettings() }
        }
        return hasPermission
    }

    private static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private static func ownApps(_ content: SCShareableContent) -> [SCRunningApplication] {
        content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
    }

    /// Every display, captured in parallel, without Snapr's own windows.
    static func captureAllDisplays() async throws -> [DisplayShot] {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await content()
        let own = ownApps(content)
        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let image = try await capture(display: display, excluding: own, scale: screen.backingScaleFactor, rect: nil)
            shots.append(DisplayShot(screen: screen, displayID: screen.displayID, image: image))
        }
        return shots
    }

    /// Part of a display. `rect` is in display-local top-left points.
    static func capture(displayID: CGDirectDisplayID, rect: CGRect?) async throws -> CGImage {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await content()
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { throw CaptureError.noDisplay }
        return try await capture(display: display, excluding: ownApps(content), scale: screen.backingScaleFactor, rect: rect)
    }

    private static func capture(display: SCDisplay, excluding apps: [SCRunningApplication], scale: CGFloat,
                                rect: CGRect?) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: apps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let area = rect ?? CGRect(x: 0, y: 0, width: display.frame.width, height: display.frame.height)
        if rect != nil { config.sourceRect = area }
        config.width = Int((area.width * scale).rounded())
        config.height = Int((area.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// One window by itself, with or without its shadow, on a transparent background.
    static func capture(windowID: CGWindowID, shadow: Bool) async throws -> CGImage {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await content()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw CaptureError.noWindow }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = !shadow
        config.shouldBeOpaque = false
        config.showsCursor = false
        config.captureResolution = .best
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// A window another app shows, as the overlay sees it.
struct WindowInfo {
    let id: CGWindowID
    /// Global top-left points.
    let frame: CGRect
    let owner: String

    /// On-screen windows of other apps, front to back. Needs no permission.
    static func onScreen() -> [WindowInfo] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != own,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 40, frame.height > 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return WindowInfo(id: id, frame: frame, owner: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}

/// Permission state for Settings, and the panes that change it.
enum Permissions {
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Asks for Accessibility with the system prompt. True when already granted.
    static func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
