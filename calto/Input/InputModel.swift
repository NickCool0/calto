import AppKit
import CaltoKit
import Observation

/// State of the input window: pasted/dropped/typed content, the user's instruction and feedback.
@MainActor
@Observable
final class InputModel {
    struct Notice: Equatable {
        let message: String
        let isError: Bool
    }

    var content = InputContent()
    var instruction = ""
    private(set) var thumbnails: [ImageAttachment.ID: NSImage] = [:]
    private(set) var notice: Notice?
    /// Images still being downscaled in the background.
    private(set) var pendingImages = 0

    var isProcessing: Bool {
        pendingImages > 0
    }

    func add(_ pasted: PasteboardContent) {
        switch pasted {
        case .images(let images):
            images.forEach(addImage)
        case .imageFiles(let urls):
            for url in urls {
                do {
                    addImage(try Data(contentsOf: url))
                } catch {
                    showError(String(localized: "calto can’t read “\(url.lastPathComponent)”. Drag the file into the window instead."))
                }
            }
        case .text(let text):
            content.appendText(text)
            notice = nil
        case .unsupported:
            show(.unsupportedContent)
        case .empty:
            showError(String(localized: "The clipboard is empty."))
        }
    }

    func addDropped(_ items: [DroppedInput]) {
        for item in items {
            switch item {
            case .imageData(let data):
                addImage(data)
            case .text(let text):
                content.appendText(text)
            }
        }
    }

    func addImage(_ data: Data) {
        guard content.images.count + pendingImages < InputContent.maxImages else {
            show(.tooManyImages(limit: InputContent.maxImages))
            return
        }
        pendingImages += 1
        Task {
            defer { pendingImages -= 1 }
            do {
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try ImageNormalizer.normalize(data)
                }.value
                try content.add(attachment)
                thumbnails[attachment.id] = NSImage(data: attachment.data)
                notice = nil
            } catch let error as InputError {
                show(error)
            } catch {
                show(.unreadableImage)
            }
        }
    }

    func removeImage(_ id: ImageAttachment.ID) {
        content.removeImage(id: id)
        thumbnails[id] = nil
    }

    func clear() {
        content = InputContent()
        instruction = ""
        thumbnails = [:]
        notice = nil
    }

    func recognize() {
        do {
            let request = try ExtractionRequest(content: content, instruction: instruction)
            let images = request.images.count
            let characters = request.text?.count ?? 0
            notice = Notice(
                message: String(localized: "Ready to recognize: images — \(images), characters — \(characters). Recognition arrives in the next stage."),
                isError: false
            )
        } catch {
            show(error)
        }
    }

    private func show(_ error: InputError) {
        switch error {
        case .emptyInput:
            showError(String(localized: "Paste or drop a screenshot, or type some text first."))
        case .tooManyImages(let limit):
            showError(String(localized: "You can add up to \(limit) images."))
        case .textTooLong(let limit):
            showError(String(localized: "The text is too long (maximum \(limit) characters)."))
        case .unreadableImage:
            showError(String(localized: "This image can’t be read."))
        case .unsupportedContent:
            showError(String(localized: "Only images and text can be added."))
        }
    }

    private func showError(_ message: String) {
        notice = Notice(message: message, isError: true)
    }
}
