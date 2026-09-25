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
        static let defaultCalendarID = "defaultCalendarID"
        static let defaultReminder = "defaultReminderMinutes"
        static let defaultDuration = "defaultDurationMinutes"
        static let alwaysRecognizeOnDevice = "alwaysRecognizeTextOnDevice"
    }

    /// Stored in place of "no reminder" (UserDefaults can't hold nil in an Int).
    private static let noReminder = -1

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

    /// Calendar for new events; `nil` uses Calendar.app's default calendar.
    var defaultCalendarID: String? {
        didSet { defaults.set(defaultCalendarID, forKey: Key.defaultCalendarID) }
    }

    /// Reminder added when the source mentions none; `nil` means no reminder.
    var defaultReminderMinutes: Int? {
        didSet { defaults.set(defaultReminderMinutes ?? Self.noReminder, forKey: Key.defaultReminder) }
    }

    /// Duration of events whose end isn't stated.
    var defaultDurationMinutes: Int {
        didSet { defaults.set(defaultDurationMinutes, forKey: Key.defaultDuration) }
    }

    /// Read text on images with Vision and send only the text, never the images.
    var alwaysRecognizeTextOnDevice: Bool {
        didSet { defaults.set(alwaysRecognizeTextOnDevice, forKey: Key.alwaysRecognizeOnDevice) }
    }

    private var modelsByProvider: [String: String] {
        didSet { defaults.set(modelsByProvider, forKey: Key.models) }
    }

    /// Providers with a stored key, known without reading (and decrypting) the key itself.
    private(set) var providersWithKeys: Set<LLMProvider>

    /// Keys already read from the Keychain in this run. Reading a key can make macOS ask for the
    /// Keychain password (once after every update of an ad-hoc signed app), so it happens once per launch.
    @ObservationIgnored private var cachedKeys: [LLMProvider: String] = [:]

    /// Suggested standing instructions for new users, in the interface language.
    static var defaultCustomPrompt: String {
        String(localized: "Start each event title with one emoji that fits its meaning, for example: 🚬 Smoke break, 🛒 Groceries, 💼 Meeting.")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedProvider = defaults.string(forKey: Key.provider).flatMap(LLMProvider.init(rawValue:))
        provider = storedProvider.flatMap { LLMProvider.selectable.contains($0) ? $0 : nil } ?? .anthropic
        compatibleBaseURL = defaults.string(forKey: Key.compatibleBaseURL)
            ?? LLMProvider.openAICompatible.defaultBaseURL?.absoluteString ?? ""
        customPrompt = defaults.string(forKey: Key.customPrompt) ?? Self.defaultCustomPrompt
        modelsByProvider = defaults.dictionary(forKey: Key.models) as? [String: String] ?? [:]
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendarID)
        let reminder = defaults.object(forKey: Key.defaultReminder) as? Int ?? 15
        defaultReminderMinutes = reminder == Self.noReminder ? nil : reminder
        defaultDurationMinutes = defaults.object(forKey: Key.defaultDuration) as? Int ?? 60
        alwaysRecognizeTextOnDevice = defaults.bool(forKey: Key.alwaysRecognizeOnDevice)
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

    /// Whether using the provider's key may show the Keychain password prompt.
    func mayPromptForAPIKey(_ provider: LLMProvider) -> Bool {
        hasAPIKey(for: provider) && cachedKeys[provider] == nil
    }

    /// The provider's key: from memory, or read from the Keychain once per launch. The read runs off
    /// the main thread, so the UI stays responsive while macOS shows its password prompt.
    func apiKey(for provider: LLMProvider) async throws -> String? {
        if let cached = cachedKeys[provider] {
            return cached
        }
        guard hasAPIKey(for: provider) else { return nil }
        let account = provider.rawValue
        let key = try await Task.detached(priority: .userInitiated) {
            try KeychainStore.read(account: account)
        }.value
        cachedKeys[provider] = key
        return key
    }

    /// Saves the key, or removes it when `key` is blank.
    func setAPIKey(_ key: String, for provider: LLMProvider) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            try KeychainStore.delete(account: provider.rawValue)
            providersWithKeys.remove(provider)
            cachedKeys[provider] = nil
        } else {
            try KeychainStore.save(key, account: provider.rawValue)
            providersWithKeys.insert(provider)
            cachedKeys[provider] = key
        }
    }

    // MARK: Readiness

    /// Whether the selected provider has what it needs to recognize events.
    var isProviderReady: Bool {
        if provider == .appleOnDevice {
            return AppleModelAvailability.isAvailable
        }
        if provider == .mock {
            return true
        }
        return (!provider.requiresAPIKey || hasAPIKey(for: provider))
            && (!provider.usesModelSelection || !currentModel.isEmpty)
    }

    var defaultAlarms: [EventAlarm] {
        defaultReminderMinutes.map { [EventAlarm(minutesBefore: $0)] } ?? []
    }
}

extension LLMProvider {
    /// Providers offered in Settings; the mock provider only in Debug builds.
    static var selectable: [LLMProvider] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0 != .mock }
        #endif
    }
}
