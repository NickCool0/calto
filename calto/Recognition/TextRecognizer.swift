import CaltoKit
import Foundation
import Vision

/// On-device text recognition (Vision) for screenshots, used when the chosen model can't read images
/// or the user wants images never to leave the Mac.
enum TextRecognizer {
    static func recognizeText(in images: [ImageAttachment]) async throws -> [String] {
        var results: [String] = []
        for image in images {
            results.append(try await recognizeText(in: image.data))
        }
        return results
    }

    static func recognizeText(in data: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: data)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
