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
        static let providersWithKeys = "providersWithKeys"
        static let addMode = "addMode"
        static let historyRetention = "historyRetention"
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

    /// Review every result first, or add clear ones right away.
    var addMode: AddMode {
        didSet { defaults.set(addMode.rawValue, forKey: Key.addMode) }
    }

    var historyRetention: HistoryRetention {
        didSet { defaults.set(historyRetention.rawValue, forKey: Key.historyRetention) }
    }

    /// Providers with a stored key. Kept in the defaults (it isn't secret), so the Keychain isn't touched
    /// at launch.
    private(set) var providersWithKeys: Set<LLMProvider> {
        didSet { defaults.set(providersWithKeys.map(\.rawValue).sorted(), forKey: Key.providersWithKeys) }
    }

    /// All keys, read from the Keychain once per launch. Reading can make macOS ask for the Keychain
    /// password (once after every update of an ad-hoc signed app).
    @ObservationIgnored private var loadedKeys: [String: String]?
    /// The read in progress: concurrent callers wait for it instead of each asking for the password.
    @ObservationIgnored private var keysLoad: Task<[String: String], any Error>?

    /// Suggested standing instructions for new users, in the interface language.
    static var defaultCustomPrompt: String {
        String(localized: "Start each event title with the one emoji that best captures what this particular event is about, not its general category. Avoid generic 💻 📅 📝 💼 ✅ when a more specific one exists, and give different events different emoji. Examples: 🗑️ Delete the database, 🦷 Dentist, ✈️ Flight to Berlin, 🎂 Anna’s birthday, 🍝 Dinner with friends, 🏋️ Gym, 🚬 Smoke break, 🛒 Groceries, 📞 Call with the bank.")
    }

    /// Earlier default prompts, replaced by the current one unless the user wrote their own.
    private static let legacyDefaultPrompts: Set<String> = [
        "Start each event title with one emoji that fits its meaning, for example: 🚬 Smoke break, 🛒 Groceries, 💼 Meeting.",
        "Начинай название каждого события с одного подходящего по смыслу эмодзи, например: 🚬 Покурить, 🛒 Магазин, 💼 Встреча.",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedProvider = defaults.string(forKey: Key.provider).flatMap(LLMProvider.init(rawValue:))
        provider = storedProvider.flatMap { LLMProvider.selectable.contains($0) ? $0 : nil } ?? .anthropic
        compatibleBaseURL = defaults.string(forKey: Key.compatibleBaseURL)
            ?? LLMProvider.openAICompatible.defaultBaseURL?.absoluteString ?? ""
        let storedPrompt = defaults.string(forKey: Key.customPrompt)
        customPrompt = storedPrompt.flatMap { Self.legacyDefaultPrompts.contains($0) ? nil : $0 } ?? Self.defaultCustomPrompt
        modelsByProvider = defaults.dictionary(forKey: Key.models) as? [String: String] ?? [:]
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendarID)
        let reminder = defaults.object(forKey: Key.defaultReminder) as? Int ?? 15
        defaultReminderMinutes = reminder == Self.noReminder ? nil : reminder
        defaultDurationMinutes = defaults.object(forKey: Key.defaultDuration) as? Int ?? 60
        alwaysRecognizeTextOnDevice = defaults.bool(forKey: Key.alwaysRecognizeOnDevice)
        addMode = defaults.string(forKey: Key.addMode).flatMap(AddMode.init(rawValue:)) ?? .review
        historyRetention = defaults.string(forKey: Key.historyRetention).flatMap(HistoryRetention.init(rawValue:)) ?? .month
        if let stored = defaults.stringArray(forKey: Key.providersWithKeys) {
            providersWithKeys = Set(stored.compactMap(LLMProvider.init(rawValue:)))
        } else {
            // First launch of this version: find the keys saved by an older one (attributes only).
            providersWithKeys = Set(LLMProvider.allCases.filter {
                $0.acceptsAPIKey && (KeychainStore.contains(account: $0.rawValue) || KeychainStore.contains(account: KeychainStore.allKeysAccount))
            })
            defaults.set(providersWithKeys.map(\.rawValue).sorted(), forKey: Key.providersWithKeys)
        }
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
        hasAPIKey(for: provider) && loadedKeys == nil
    }

    /// The provider's key, from memory after the first read of the launch.
    func apiKey(for provider: LLMProvider) async throws -> String? {
        guard hasAPIKey(for: provider) else { return nil }
        return try await allKeys()[provider.rawValue]
    }

    /// Saves the key, or removes it when `key` is blank.
    func setAPIKey(_ key: String, for provider: LLMProvider) async throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys = providersWithKeys.isEmpty ? (loadedKeys ?? [:]) : try await allKeys()
        keys[provider.rawValue] = key.isEmpty ? nil : key
        let updated = keys
        try await Task.detached(priority: .userInitiated) {
            try KeychainStore.saveAllKeys(updated)
        }.value
        loadedKeys = updated
        if key.isEmpty {
            providersWithKeys.remove(provider)
        } else {
            providersWithKeys.insert(provider)
        }
    }

    /// Reads all keys once, off the main thread (the UI stays responsive while macOS shows its prompt).
    private func allKeys() async throws -> [String: String] {
        if let loadedKeys {
            return loadedKeys
        }
        if let keysLoad {
            return try await keysLoad.value
        }
        let legacy = LLMProvider.allCases.filter(\.acceptsAPIKey).map(\.rawValue)
        let load = Task.detached(priority: .userInitiated) {
            try KeychainStore.loadAllKeys(legacyAccounts: legacy)
        }
        keysLoad = load
        defer { keysLoad = nil }
        let keys = try await load.value
        loadedKeys = keys
        return keys
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
