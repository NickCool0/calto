import AppKit

/// The interface language. Stored as `AppleLanguages` in calto's own defaults, the same setting
/// System Settings ▸ General ▸ Language & Region ▸ Applications writes; it applies after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    private static let key = "AppleLanguages"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "Same as System")
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// The choice stored for calto (not the system-wide list the defaults would fall back to).
    static var selected: AppLanguage {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
            guard let code = (domain?[key] as? [String])?.first else { return .system }
            return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: key)
            }
        }
    }

    /// The language this running copy of calto shows (resolved by the bundle at launch).
    static var running: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// The choice in effect for this running copy, recorded at launch (see `AppDelegate`); Settings
    /// offers a relaunch while the stored choice differs from it.
    static let launchSelection = selected

    /// The user's region and formats with the interface language, so the model writes its notes about
    /// ambiguities in the language calto is shown in.
    static var requestLocale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: running)
        return Locale(components: components)
    }

    /// Starts a new copy of calto and quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
