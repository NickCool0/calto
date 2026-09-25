import CaltoKit
import Foundation
import Observation

/// User preferences. Everything except API keys is stored in `UserDefaults`; keys go to the Keychain.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let provider = "provider"
        static let models = "modelsByProvider"
        static let compatibleBaseURL = "compatibleBaseURL"
        static let customPrompt = "customPrompt"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var provider: LLMProvider {
        didSet { defaults.set(provider.rawValue, forKey: Key.provider) }
    }

    /// Address of the OpenAI-compatible server (Ollama, LM Studio, OpenRouter…).
    var compatibleBaseURL: String {
        didSet { defaults.set(compatibleBaseURL, forKey: Key.compatibleBaseURL) }
    }

    /// Standing instructions added to every recognition request.
    var customPrompt: String {
        didSet { defaults.set(customPrompt, forKey: Key.customPrompt) }
    }

    private var modelsByProvider: [String: String] {
        didSet { defaults.set(modelsByProvider, forKey: Key.models) }
    }

    /// Providers with a stored key, known without reading (and decrypting) the key itself.
    private(set) var providersWithKeys: Set<LLMProvider>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: Key.provider).flatMap(LLMProvider.init(rawValue:)) ?? .anthropic
        compatibleBaseURL = defaults.string(forKey: Key.compatibleBaseURL)
            ?? LLMProvider.openAICompatible.defaultBaseURL?.absoluteString ?? ""
        customPrompt = defaults.string(forKey: Key.customPrompt) ?? ""
        modelsByProvider = defaults.dictionary(forKey: Key.models) as? [String: String] ?? [:]
        providersWithKeys = Set(LLMProvider.allCases.filter { $0.acceptsAPIKey && KeychainStore.contains(account: $0.rawValue) })
    }

    // MARK: Models

    func model(for provider: LLMProvider) -> String {
        modelsByProvider[provider.rawValue] ?? provider.defaultModel ?? ""
    }

    func setModel(_ model: String, for provider: LLMProvider) {
        modelsByProvider[provider.rawValue] = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentModel: String {
        model(for: provider)
    }

    var compatibleBaseURLValue: URL? {
        URL(string: compatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: API keys

    func hasAPIKey(for provider: LLMProvider) -> Bool {
        providersWithKeys.contains(provider)
    }

    func apiKey(for provider: LLMProvider) throws -> String? {
        try KeychainStore.read(account: provider.rawValue)
    }

    /// Saves the key, or removes it when `key` is blank.
    func setAPIKey(_ key: String, for provider: LLMProvider) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            try KeychainStore.delete(account: provider.rawValue)
            providersWithKeys.remove(provider)
        } else {
            try KeychainStore.save(key, account: provider.rawValue)
            providersWithKeys.insert(provider)
        }
    }

    // MARK: Readiness

    /// Whether the selected provider has what it needs to recognize events.
    var isProviderReady: Bool {
        if provider == .appleOnDevice {
            return AppleModelAvailability.isAvailable
        }
        return (!provider.requiresAPIKey || hasAPIKey(for: provider))
            && (!provider.usesModelSelection || !currentModel.isEmpty)
    }
}
