import Foundation
import UniformTypeIdentifiers

/// Where and how to send an extraction request.
public struct ProviderConfiguration: Sendable, Hashable {
    public var provider: LLMProvider
    public var model: String
    public var apiKey: String?
    /// Only used by the OpenAI-compatible provider.
    public var baseURL: URL?

    public init(provider: LLMProvider, model: String, apiKey: String?, baseURL: URL? = nil) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public enum OutputMode: Sendable, Hashable {
    /// The provider's structured-output feature enforces `ExtractionSchema`.
    case structured
    /// Plain JSON; the schema is spelled out in the prompt (for endpoints that reject schemas).
    case jsonOnly
}

/// Builds the HTTP request for each provider's generation API.
public enum ExtractionRequestBuilder {
    static let maxOutputTokens = 16_000

    public static func request(
        _ configuration: ProviderConfiguration,
        prompt: ExtractionPrompt,
        images: [ImageAttachment],
        mode: OutputMode
    ) throws(ProviderError) -> URLRequest {
        let provider = configuration.provider
        let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.requiresAPIKey && key.isEmpty {
            throw .missingAPIKey
        }
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw .badRequest(nil)
        }
        guard let base = (provider.hasConfigurableBaseURL ? configuration.baseURL : nil) ?? provider.defaultBaseURL else {
            throw .unsupported
        }
        guard let scheme = base.scheme?.lowercased(), ["http", "https"].contains(scheme), base.host() != nil else {
            throw .invalidBaseURL
        }

        var request: URLRequest
        let body: JSONValue
        switch provider {
        case .anthropic:
            request = URLRequest(url: base.appending(path: "messages"))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(ModelCatalog.anthropicVersion, forHTTPHeaderField: "anthropic-version")
            body = anthropicBody(model: model, prompt: prompt, images: images, mode: mode)
        case .openAI, .openAICompatible:
            request = URLRequest(url: base.appending(path: "chat/completions"))
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            body = openAIBody(model: model, prompt: prompt, images: images, mode: mode)
        case .gemini:
            let name = model.hasPrefix("models/") ? String(model.dropFirst("models/".count)) : model
            request = URLRequest(url: base.appending(path: "models/\(name):generateContent"))
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = geminiBody(prompt: prompt, images: images, mode: mode)
        case .appleOnDevice, .mock:
            throw .unsupported
        }
        request.httpMethod = "POST"
        // Reasoning models can take a while on long schedules.
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.encoded()
        return request
    }

    // MARK: Bodies

    static func anthropicBody(model: String, prompt: ExtractionPrompt, images: [ImageAttachment], mode: OutputMode) -> JSONValue {
        var content: [JSONValue] = images.map { image in
            .object([
                "type": "image",
                "source": .object([
                    "type": "base64",
                    "media_type": .string(image.mimeType),
                    "data": .string(image.data.base64EncodedString()),
                ]),
            ])
        }
        content.append(.object(["type": "text", "text": .string(prompt.user)]))

        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .int(maxOutputTokens),
            "system": .string(prompt.system),
            "messages": .array([.object(["role": "user", "content": .array(content)])]),
        ]
        if mode == .structured {
            body["output_config"] = .object([
                "format": .object(["type": "json_schema", "schema": ExtractionSchema.jsonSchema]),
            ])
        }
        return .object(body)
    }

    static func openAIBody(model: String, prompt: ExtractionPrompt, images: [ImageAttachment], mode: OutputMode) -> JSONValue {
        let userContent: JSONValue
        if images.isEmpty {
            // Plain string content: the widest compatibility with local servers.
            userContent = .string(prompt.user)
        } else {
            var parts: [JSONValue] = [.object(["type": "text", "text": .string(prompt.user)])]
            parts += images.map { image in
                .object([
                    "type": "image_url",
                    "image_url": .object(["url": .string("data:\(image.mimeType);base64,\(image.data.base64EncodedString())")]),
                ])
            }
            userContent = .array(parts)
        }

        let responseFormat: JSONValue = switch mode {
        case .structured:
            .object([
                "type": "json_schema",
                "json_schema": .object([
                    "name": "calendar_events",
                    "strict": true,
                    "schema": ExtractionSchema.jsonSchema,
                ]),
            ])
        case .jsonOnly:
            .object(["type": "json_object"])
        }

        return .object([
            "model": .string(model),
            "messages": .array([
                .object(["role": "system", "content": .string(prompt.system)]),
                .object(["role": "user", "content": userContent]),
            ]),
            "response_format": responseFormat,
        ])
    }

    static func geminiBody(prompt: ExtractionPrompt, images: [ImageAttachment], mode: OutputMode) -> JSONValue {
        var parts: [JSONValue] = [.object(["text": .string(prompt.user)])]
        parts += images.map { image in
            .object([
                "inlineData": .object([
                    "mimeType": .string(image.mimeType),
                    "data": .string(image.data.base64EncodedString()),
                ]),
            ])
        }

        var generationConfig: [String: JSONValue] = ["responseMimeType": "application/json"]
        if mode == .structured {
            generationConfig["responseJsonSchema"] = ExtractionSchema.jsonSchema
        }

        return .object([
            "systemInstruction": .object(["parts": .array([.object(["text": .string(prompt.system)])])]),
            "contents": .array([.object(["role": "user", "parts": .array(parts)])]),
            "generationConfig": .object(generationConfig),
        ])
    }
}

/// Reads each provider's answer and turns it into `WireEvent`s.
public enum ExtractionResponseParser {
    /// Like `ModelCatalog.validate`, plus recognizing "this model can't read images".
    public static func validate(status: Int, body: Data, provider: LLMProvider, sentImages: Bool) throws(ProviderError) {
        do {
            try ModelCatalog.validate(status: status, body: body, provider: provider)
        } catch .badRequest(let message) where sentImages && mentionsUnsupportedImages(message) {
            throw .imagesNotSupported
        } catch .notFound where sentImages && mentionsUnsupportedImages(ModelCatalog.errorMessage(in: body)) {
            throw .imagesNotSupported
        }
    }

    /// Whether a 400 is about the output schema, so a retry without structured output may succeed.
    public static func isSchemaRejection(_ error: ProviderError) -> Bool {
        guard case .badRequest(let message) = error else { return false }
        let text = (message ?? "").lowercased()
        let markers = ["schema", "response_format", "json_schema", "output_config", "responsejsonschema", "structured", "format"]
        return markers.contains { text.contains($0) }
    }

    static func mentionsUnsupportedImages(_ message: String?) -> Bool {
        let text = (message ?? "").lowercased()
        let mentionsImages = ["image", "vision", "multimodal", "multi-modal", "inline_data", "inlinedata"].contains { text.contains($0) }
        let saysUnsupported = ["support", "not allowed", "invalid", "cannot", "can't", "unable", "does not", "doesn't", "only text", "not enabled"]
            .contains { text.contains($0) }
        return mentionsImages && saysUnsupported
    }

    /// The model's JSON text, or an error explaining why there is none.
    public static func outputText(from data: Data, provider: LLMProvider) throws(ProviderError) -> String {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw .invalidResponse
        }
        switch provider {
        case .anthropic:
            switch json["stop_reason"]?.stringValue {
            case "refusal": throw .refused(nil)
            case "max_tokens": throw .truncated
            default: break
            }
            let text = (json["content"]?.arrayValue ?? [])
                .filter { $0["type"]?.stringValue == "text" }
                .compactMap { $0["text"]?.stringValue }
                .joined()
            guard !text.isEmpty else { throw .malformedOutput }
            return text

        case .openAI, .openAICompatible:
            guard let choice = json["choices"]?[0] else { throw .invalidResponse }
            if let refusal = choice["message"]?["refusal"]?.stringValue {
                throw .refused(refusal)
            }
            switch choice["finish_reason"]?.stringValue {
            case "length": throw .truncated
            case "content_filter": throw .refused(nil)
            default: break
            }
            guard let text = choice["message"]?["content"]?.stringValue, !text.isEmpty else { throw .malformedOutput }
            return text

        case .gemini:
            if let reason = json["promptFeedback"]?["blockReason"]?.stringValue {
                throw .refused(reason)
            }
            guard let candidate = json["candidates"]?[0] else { throw .refused(nil) }
            switch candidate["finishReason"]?.stringValue {
            case "MAX_TOKENS": throw .truncated
            case "SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII": throw .refused(candidate["finishReason"]?.stringValue)
            default: break
            }
            let text = (candidate["content"]?["parts"]?.arrayValue ?? [])
                .filter { $0["thought"]?.boolValue != true }
                .compactMap { $0["text"]?.stringValue }
                .joined()
            guard !text.isEmpty else { throw .malformedOutput }
            return text

        case .appleOnDevice, .mock:
            throw .unsupported
        }
    }

    /// Decodes the events, tolerating code fences, surrounding prose and a bare array.
    public static func events(fromOutput text: String) throws(ProviderError) -> [WireEvent] {
        let candidates = [text, stripCodeFence(text), outermostJSON(in: text)].compactMap { $0 }
        for candidate in candidates {
            let data = Data(candidate.utf8)
            if let response = try? JSONDecoder().decode(ExtractionResponse.self, from: data) {
                return response.events
            }
            if let events = try? JSONDecoder().decode([WireEvent].self, from: data) {
                return events
            }
        }
        throw .malformedOutput
    }

    static func stripCodeFence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }
        var lines = trimmed.components(separatedBy: "\n")
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func outermostJSON(in text: String) -> String? {
        guard let open = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let close: Character = text[open] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: close), end > open else { return nil }
        return String(text[open...end])
    }
}

extension ImageAttachment {
    var mimeType: String {
        contentType.preferredMIMEType ?? "image/png"
    }
}
