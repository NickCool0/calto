import CaltoKit
import Foundation
import FoundationModels

extension LLMProvider {
    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .openAICompatible: String(localized: "OpenAI-compatible (Ollama, LM Studio, OpenRouter…)")
        case .appleOnDevice: String(localized: "Apple Intelligence (on device)")
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: "Claude"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .openAICompatible: String(localized: "Local / compatible")
        case .appleOnDevice: String(localized: "On device")
        }
    }
}

extension ProviderError {
    var message: String {
        switch self {
        case .missingAPIKey:
            String(localized: "Enter an API key first.")
        case .invalidBaseURL:
            String(localized: "The server address is not valid. It should look like http://localhost:11434/v1.")
        case .invalidAPIKey:
            String(localized: "The API key was rejected. Check that it was copied completely.")
        case .forbidden:
            String(localized: "This key has no access to the API. Check its permissions or your region.")
        case .notFound:
            String(localized: "There is no model list at this address. Check the server address.")
        case .rateLimited:
            String(localized: "Too many requests. Try again in a minute.")
        case .serverError(let status):
            String(localized: "The provider’s server returned an error (\(status)). Try again later.")
        case .unexpectedStatus(let status):
            String(localized: "Unexpected response from the server (HTTP \(status)).")
        case .offline:
            String(localized: "No internet connection.")
        case .timedOut:
            String(localized: "The server didn’t respond in time.")
        case .cannotConnect(let host?):
            String(localized: "Can’t connect to \(host). For a local model, make sure Ollama or LM Studio is running.")
        case .cannotConnect(nil):
            String(localized: "Can’t connect to the server.")
        case .insecureConnection:
            String(localized: "Secure connection failed. Use https:// for remote servers.")
        case .invalidResponse:
            String(localized: "The server’s response is not a model list. Check the server address.")
        case .unsupported:
            String(localized: "This provider doesn’t offer a model list.")
        }
    }
}

/// Fetches the provider's model list; succeeding also proves the key works.
enum ModelCatalogClient {
    private static let session = URLSession(configuration: .ephemeral)

    static func fetchModels(provider: LLMProvider, apiKey: String?, baseURL: URL?) async throws(ProviderError) -> [ModelInfo] {
        let request = try ModelCatalog.request(for: provider, apiKey: apiKey, baseURL: baseURL)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ModelCatalog.error(from: error, url: request.url)
        } catch {
            throw .cannotConnect(host: request.url?.host())
        }
        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse
        }
        try ModelCatalog.validate(status: http.statusCode, body: data, provider: provider)
        return try ModelCatalog.parse(data, provider: provider)
    }
}

/// Whether Apple's on-device model can be used on this Mac.
enum AppleModelAvailability {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    static var description: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            String(localized: "Available on this Mac. Nothing leaves your computer.")
        case .unavailable(.deviceNotEligible):
            String(localized: "This Mac doesn’t support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "Turn on Apple Intelligence in System Settings to use this option.")
        case .unavailable(.modelNotReady):
            String(localized: "The model is still downloading. Try again later.")
        case .unavailable:
            String(localized: "Not available on this Mac.")
        }
    }
}
