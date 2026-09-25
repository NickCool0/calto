import Foundation

/// A service that turns text and screenshots into events.
public enum LLMProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic
    case openAI
    case gemini
    /// Any server speaking the OpenAI API: Ollama, LM Studio, osaurus, OpenRouter…
    case openAICompatible
    /// Apple's on-device model (Foundation Models): no key, nothing leaves the Mac.
    case appleOnDevice

    public var id: String { rawValue }

    /// Whether requests fail without a key. Local OpenAI-compatible servers usually need none.
    public var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openAI, .gemini: true
        case .openAICompatible, .appleOnDevice: false
        }
    }

    public var acceptsAPIKey: Bool {
        self != .appleOnDevice
    }

    /// Only the OpenAI-compatible endpoint is user-configurable.
    public var hasConfigurableBaseURL: Bool {
        self == .openAICompatible
    }

    public var usesModelSelection: Bool {
        self != .appleOnDevice
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1")
        case .openAI: URL(string: "https://api.openai.com/v1")
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta")
        case .openAICompatible: URL(string: "http://localhost:11434/v1")
        case .appleOnDevice: nil
        }
    }

    /// Suggested model before the user loads the provider's list; `nil` means "pick from the list".
    public var defaultModel: String? {
        switch self {
        case .anthropic: "claude-opus-5"
        case .openAI, .gemini, .openAICompatible, .appleOnDevice: nil
        }
    }

    /// Where to create an API key.
    public var apiKeyPageURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .openAICompatible, .appleOnDevice: nil
        }
    }
}
