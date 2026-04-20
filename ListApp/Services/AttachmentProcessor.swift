import Foundation
import Core
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Composes the user's typed text and any `ChatAttachment`s into two strings:
///
/// - `userFacing`: what the user's chat bubble renders (their typed text + chip labels).
/// - `modelBound`: what is actually sent to the LLM. URLs and extracted image text
///   are appended as labelled blocks so the model has the literal content to work with.
enum AttachmentProcessor {

    struct Composed {
        let userFacing: String
        let modelBound: String
    }

    static func compose(userText: String, attachments: [ChatAttachment]) async -> Composed {
        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        if attachments.isEmpty {
            return Composed(userFacing: trimmedUserText, modelBound: trimmedUserText)
        }

        var userFacingParts: [String] = []
        if !trimmedUserText.isEmpty {
            userFacingParts.append(trimmedUserText)
        }
        for attachment in attachments {
            userFacingParts.append("📎 \(attachment.displayLabel)")
        }

        var modelParts: [String] = []
        if !trimmedUserText.isEmpty {
            modelParts.append(trimmedUserText)
        }

        var imageIndex = 0
        for attachment in attachments {
            switch attachment.kind {
            case .text(let body):
                modelParts.append("--- Text ---\n\(body)")
            case .url(let url):
                modelParts.append("--- URL ---\n\(url.absoluteString)")
            case .image(let fileURL):
                imageIndex += 1
                let ocr = await extractText(from: fileURL)
                if ocr.isEmpty {
                    modelParts.append("--- Image \(imageIndex) ---\n(no text extracted)")
                } else {
                    modelParts.append("--- Image \(imageIndex) ---\n\(ocr)")
                }
            }
        }

        return Composed(
            userFacing: userFacingParts.joined(separator: "\n"),
            modelBound: modelParts.joined(separator: "\n\n")
        )
    }

    // MARK: - OCR

    private static func extractText(from fileURL: URL) async -> String {
        guard let ciImage = CIImage(contentsOf: fileURL) else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(ciImage: ciImage, options: [:]).perform([request])
        }
    }
}
