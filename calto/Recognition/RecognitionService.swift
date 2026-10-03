import CaltoKit
import Foundation

nonisolated enum RecognitionError: LocalizedError {
    case provider(ProviderError)
    case keychain(String)
    case appleModelUnavailable(String)
    case appleModel(String)
    case textRecognition(String)

    var errorDescription: String? {
        switch self {
        case .provider(let error): error.message
        case .keychain(let message): String(localized: "Couldn’t read the key from the Keychain: \(message)")
        case .appleModelUnavailable(let reason): reason
        case .appleModel(let message): String(localized: "Apple’s model couldn’t process the request: \(message)")
        case .textRecognition(let message): String(localized: "Couldn’t read text on the image: \(message)")
        }
    }
}

/// What recognition is doing right now, shown in the popover while it runs.
enum RecognitionStage: Equatable {
    /// Waiting for the Keychain (macOS may be asking for the password).
    case unlockingKey
    /// Reading text on the images with Vision, on this Mac.
    case readingText
    /// Waiting for the model's answer.
    case waitingForModel
}

/// Recognized events plus what is kept for the history.
struct RecognitionResult {
    var drafts: [EventDraft]
    var analysis: WireAnalysis?
}

/// Sends the input to the chosen provider and turns the answer into event drafts.
///
/// Recovery built in: if an endpoint rejects the output schema it retries in plain JSON mode, and if the
/// model can't read images it retries with text recognized on the device.
final class RecognitionService {
    private let session = URLSession(configuration: .ephemeral)
    private var report: (RecognitionStage) -> Void = { _ in }
    /// Text read from each image during this run, so no image is read twice.
    private var recognizedText: [ImageAttachment.ID: String] = [:]

    func recognize(
        _ request: ExtractionRequest,
        settings: AppSettings,
        progress: @escaping (RecognitionStage) -> Void = { _ in }
    ) async throws -> RecognitionResult {
        report = progress
        recognizedText = [:]
        defer {
            report = { _ in }
            recognizedText = [:]
        }
        // Links on the screenshots are read on this Mac in parallel, as a safety net for the notes.
        let linksOnImages = Task { await self.linksOnImages(request.images) }
        let response = try await extractEvents(request, settings: settings)
        let extraLinks = LinkDetector.links(in: request.text ?? "") + (await linksOnImages.value) + (response.analysis?.links ?? [])
        let context = ResolutionContext(
            timeZone: request.timeZone,
            referenceDate: request.referenceDate,
            defaultDurationMinutes: settings.defaultDurationMinutes,
            defaultAlarms: settings.defaultAlarms,
            extraLinks: extraLinks,
            headings: NotesHeadings(links: String(localized: "🔗 Links:"), context: String(localized: "💬 Context:"))
        )
        return RecognitionResult(drafts: EventResolver.resolve(response.events, context: context), analysis: response.analysis)
    }

    /// Never fails: a screenshot whose text can't be read just contributes no links.
    private func linksOnImages(_ images: [ImageAttachment]) async -> [String] {
        var links: [String] = []
        for image in images {
            if let text = try? await text(on: image) {
                links += LinkDetector.links(in: text)
            }
        }
        return links
    }

    private func text(on image: ImageAttachment) async throws -> String {
        if let cached = recognizedText[image.id] {
            return cached
        }
        let text = try await TextRecognizer.recognizeText(in: image.data)
        recognizedText[image.id] = text
        return text
    }

    private func extractEvents(_ request: ExtractionRequest, settings: AppSettings) async throws -> ExtractionResponse {
        let provider = settings.provider
        switch provider {
        case .mock:
            report(.waitingForModel)
            try await Task.sleep(for: .milliseconds(600))
            return try parse(MockExtractor.output(for: request))

        case .appleOnDevice:
            let text = try await recognizeText(in: request.images)
            let prompt = PromptBuilder.build(for: request, recognizedText: text)
            report(.waitingForModel)
            do {
                return try await AppleModelExtractor.extract(prompt: prompt)
            } catch let error as RecognitionError {
                throw error
            } catch {
                throw RecognitionError.appleModel(error.localizedDescription)
            }

        case .anthropic, .openAI, .gemini, .openAICompatible:
            let apiKey: String?
            do {
                if settings.mayPromptForAPIKey(provider) {
                    report(.unlockingKey)
                }
                apiKey = provider.acceptsAPIKey ? try await settings.apiKey(for: provider) : nil
            } catch {
                throw RecognitionError.keychain(error.localizedDescription)
            }
            let configuration = ProviderConfiguration(
                provider: provider,
                model: settings.currentModel,
                apiKey: apiKey,
                baseURL: settings.compatibleBaseURLValue
            )
            if settings.alwaysRecognizeTextOnDevice && !request.images.isEmpty {
                let text = try await recognizeText(in: request.images)
                return try await send(request, configuration: configuration, images: [], recognizedText: text)
            }
            do {
                return try await send(request, configuration: configuration, images: request.images, recognizedText: [])
            } catch RecognitionError.provider(.imagesNotSupported) {
                let text = try await recognizeText(in: request.images)
                return try await send(request, configuration: configuration, images: [], recognizedText: text)
            }
        }
    }

    /// Structured output first; plain JSON if the endpoint rejects the schema.
    private func send(
        _ request: ExtractionRequest,
        configuration: ProviderConfiguration,
        images: [ImageAttachment],
        recognizedText: [String]
    ) async throws -> ExtractionResponse {
        report(.waitingForModel)
        do {
            let prompt = PromptBuilder.build(for: request, recognizedText: recognizedText, imageCount: images.count)
            return try await perform(configuration, prompt: prompt, images: images, mode: .structured)
        } catch RecognitionError.provider(let error) where ExtractionResponseParser.isSchemaRejection(error) {
            let prompt = PromptBuilder.build(for: request, recognizedText: recognizedText, imageCount: images.count, includeSchema: true)
            return try await perform(configuration, prompt: prompt, images: images, mode: .jsonOnly)
        }
    }

    private func perform(
        _ configuration: ProviderConfiguration,
        prompt: ExtractionPrompt,
        images: [ImageAttachment],
        mode: OutputMode
    ) async throws -> ExtractionResponse {
        let urlRequest: URLRequest
        do {
            urlRequest = try ExtractionRequestBuilder.request(configuration, prompt: prompt, images: images, mode: mode)
        } catch {
            throw RecognitionError.provider(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw RecognitionError.provider(ModelCatalog.error(from: error, url: urlRequest.url))
        }

        guard let http = response as? HTTPURLResponse else {
            throw RecognitionError.provider(.invalidResponse)
        }
        do {
            try ExtractionResponseParser.validate(status: http.statusCode, body: data, provider: configuration.provider, sentImages: !images.isEmpty)
            let text = try ExtractionResponseParser.outputText(from: data, provider: configuration.provider)
            return try ExtractionResponseParser.response(fromOutput: text)
        } catch {
            throw RecognitionError.provider(error)
        }
    }

    private func parse(_ output: String) throws -> ExtractionResponse {
        do {
            return try ExtractionResponseParser.response(fromOutput: output)
        } catch {
            throw RecognitionError.provider(error)
        }
    }

    private func recognizeText(in images: [ImageAttachment]) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        report(.readingText)
        do {
            var texts: [String] = []
            for image in images {
                texts.append(try await text(on: image))
            }
            return texts
        } catch {
            throw RecognitionError.textRecognition(error.localizedDescription)
        }
    }
}
