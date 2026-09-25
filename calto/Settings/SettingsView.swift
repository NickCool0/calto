import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case model
    case prompt
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .model: String(localized: "Model")
        case .prompt: String(localized: "Prompt")
        case .general: String(localized: "General")
        }
    }

    var systemImage: String {
        switch self {
        case .model: "sparkles"
        case .prompt: "text.quote"
        case .general: "gearshape"
        }
    }
}

/// Lets code outside the view (the popup, the menu) open a specific tab.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    var selectedTab: SettingsTab? = .model

    private init() {}
}

struct SettingsView: View {
    let context: AppContext
    @State private var navigation = SettingsNavigation.shared

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $navigation.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
                Text(verbatim: versionString)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospaced()
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle((navigation.selectedTab ?? .model).title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedTab ?? .model {
        case .model:
            ModelSettingsPane(settings: context.settings)
        case .prompt:
            PromptSettingsPane(settings: context.settings)
        case .general:
            GeneralSettingsPane(context: context)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "calto \(version) (\(build))"
    }
}

extension View {
    /// Shared look for every settings pane (grouped form over the window's glass).
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
