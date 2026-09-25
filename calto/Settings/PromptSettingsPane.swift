import SwiftUI

struct PromptSettingsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.customPrompt)
                    .font(.body)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Your instructions")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Added to every request, together with what you type in the popup.")
                    Text("For example: “Put work meetings in the Work calendar. Title events in Russian. My time zone is Moscow unless stated otherwise.”")
                        .foregroundStyle(.tertiary)
                    if settings.customPrompt != AppSettings.defaultCustomPrompt {
                        Button("Restore Default") {
                            settings.customPrompt = AppSettings.defaultCustomPrompt
                        }
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .settingsPaneStyle()
    }
}
