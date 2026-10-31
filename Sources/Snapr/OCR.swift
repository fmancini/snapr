import AppKit
import SnaprKit
import Vision

/// Text and QR codes in images, through Vision. Runs on this Mac only.
enum OCR {
    struct Result {
        var text: String
        var isCode: Bool
        var lineCount: Int
    }

    /// A QR or bar code's payload wins over the text around it.
    static func recognize(_ image: CGImage, keepLineBreaks: Bool = Prefs.ocrKeepBreaks,
                          language: String = Prefs.ocrLanguage) async -> Result? {
        if let codes = try? await DetectBarcodesRequest().perform(on: image),
           let payload = codes.compactMap(\.payloadString).first, !payload.isEmpty {
            return Result(text: payload, isCode: true, lineCount: 1)
        }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if language == "auto" {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = [Locale.Language(identifier: language)]
        }
        guard let observations = try? await request.perform(on: image) else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        return Result(text: OCRText.join(lines, keepLineBreaks: keepLineBreaks), isCode: false, lineCount: lines.count)
    }

    /// Languages for Settings, as identifiers like "en-US".
    static var languages: [String] {
        RecognizeTextRequest().supportedRecognitionLanguages.map { $0.maximalIdentifier }
    }

    /// Recognizes, copies, and says what happened.
    static func copyText(in image: CGImage) async {
        guard let result = await recognize(image) else {
            HUD.show("No text found", symbol: "text.viewfinder")
            return
        }
        Output.copyText(result.text)
        if result.isCode {
            HUD.show("Copied code: \(String(result.text.prefix(40)))", symbol: "qrcode")
        } else {
            if result.lineCount == 1 {
                HUD.show("Copied 1 line of text", symbol: "text.viewfinder")
            } else {
                HUD.show("Copied \(result.lineCount) lines of text", symbol: "text.viewfinder")
            }
        }
    }
}
