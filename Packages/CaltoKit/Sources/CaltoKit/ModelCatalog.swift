import Foundation

public struct ModelInfo: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayName: String?

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }
}

/// Failures talking to a provider, phrased for people in the app.
public enum ProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidBaseURL
    case invalidAPIKey
    case forbidden
    case notFound
    case rateLimited
    case serverError(status: Int)
    case unexpectedStatus(Int)
    case offline
    case timedOut
    case cannotConnect(host: String?)
    case insecureConnection
    case invalidResponse
    case unsupported
    /// HTTP 400 with the provider's explanation (wrong model name, unsupported parameter…).
    case badRequest(String?)
    case imagesNotSupported
    /// The provider declined to answer (safety filters).
    case refused(String?)
    /// The answer was cut off by the output limit.
    case truncated
    /// The model answered, but not with the expected JSON.
    case malformedOutput
}

/// Lists the models a provider offers. Doubles as an API key check: a key that can list models works.
/// Requests are built and responses parsed here so they can be tested without the network.
public enum ModelCatalog {
    static let anthropicVersion = "2023-06-01"
    /// Model families the OpenAI API lists that can't read an invitation.
    static let nonChatMarkers = [
        "embed", "tts", "whisper", "dall-e", "gpt-image", "moderation", "realtime", "transcribe",
        "audio", "davinci", "babbage", "computer-use",
    ]

    public static func request(for provider: LLMProvider, apiKey: String?, baseURL: URL? = nil) throws(ProviderError) -> URLRequest {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.requiresAPIKey && key.isEmpty {
            throw .missingAPIKey
        }
        guard let base = (provider.hasConfigurableBaseURL ? baseURL : nil) ?? provider.defaultBaseURL else {
            throw .unsupported
        }
        guard let scheme = base.scheme?.lowercased(), ["http", "https"].contains(scheme), base.host() != nil else {
            throw .invalidBaseURL
        }

        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: base.appending(path: "models").appending(queryItems: [URLQueryItem(name: "limit", value: "1000")]))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        case .openAI, .openAICompatible:
            request = URLRequest(url: base.appending(path: "models"))
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .gemini:
            request = URLRequest(url: base.appending(path: "models").appending(queryItems: [URLQueryItem(name: "pageSize", value: "1000")]))
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .appleOnDevice, .mock:
            throw .unsupported
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Throws for non-2xx responses, mapping them to something the user can act on.
    public static func validate(status: Int, body: Data, provider: LLMProvider) throws(ProviderError) {
        switch status {
        case 200..<300:
            return
        case 400 where provider == .gemini && isGeminiKeyError(body):
            // Gemini reports a bad key as 400 INVALID_ARGUMENT, not 401.
            throw .invalidAPIKey
        case 400, 422:
            throw .badRequest(errorMessage(in: body))
        case 401:
            throw .invalidAPIKey
        case 403:
            throw .forbidden
        case 404:
            throw .notFound
        case 429:
            throw .rateLimited
        case 500..<600:
            throw .serverError(status: status)
        default:
            throw .unexpectedStatus(status)
        }
    }

    public static func parse(_ data: Data, provider: LLMProvider) throws(ProviderError) -> [ModelInfo] {
        do {
            switch provider {
            case .anthropic:
                let list = try JSONDecoder().decode(AnthropicList.self, from: data)
                return list.data.map { ModelInfo(id: $0.id, displayName: $0.display_name) }
            case .openAI, .openAICompatible:
                let list = try JSONDecoder().decode(OpenAIList.self, from: data)
                return list.data
                    .filter { model in !nonChatMarkers.contains { model.id.lowercased().contains($0) } }
                    .sorted { lhs, rhs in
                        // Newest first; the API returns them in no particular order.
                        let (l, r) = (lhs.created ?? 0, rhs.created ?? 0)
                        return l != r ? l > r : lhs.id < rhs.id
                    }
                    .map { ModelInfo(id: $0.id, displayName: $0.name) }
            case .gemini:
                let list = try JSONDecoder().decode(GeminiList.self, from: data)
                return list.models
                    .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
                    .map { model in
                        let id = model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name
                        return ModelInfo(id: id, displayName: model.displayName)
                    }
            case .appleOnDevice, .mock:
                throw ProviderError.unsupported
            }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw .invalidResponse
        }
    }

    public static func error(from urlError: URLError, url: URL?) -> ProviderError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .timedOut:
            .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .cannotConnect(host: url?.host())
        case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            .insecureConnection
        case .badURL, .unsupportedURL:
            .invalidBaseURL
        default:
            .cannotConnect(host: url?.host())
        }
    }

    /// The human-readable message in an error body: `{"error": {"message": …}}` (OpenAI, Anthropic,
    /// Gemini), `{"error": "…"}` (Ollama) or `{"message": …}`.
    public static func errorMessage(in body: Data) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: body) else {
            let text = String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return json["error"]?["message"]?.stringValue ?? json["error"]?.stringValue ?? json["message"]?.stringValue
    }

    static func isGeminiKeyError(_ body: Data) -> Bool {
        let text = String(decoding: body, as: UTF8.self)
        return text.contains("API_KEY_INVALID") || text.contains("API key not valid")
    }

    private struct AnthropicList: Decodable {
        struct Model: Decodable {
            let id: String
            let display_name: String?
        }
        let data: [Model]
    }

    private struct OpenAIList: Decodable {
        struct Model: Decodable {
            let id: String
            let created: Int?
            /// OpenRouter and some local servers add a human-readable name.
            let name: String?
        }
        let data: [Model]
    }

    private struct GeminiList: Decodable {
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]?
        }
        let models: [Model]
    }
}
