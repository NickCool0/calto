import CaltoKit
import SwiftUI

struct ModelSettingsPane: View {
    @Bindable var settings: AppSettings

    private enum CheckState: Equatable {
        case idle
        case checking
        case succeeded(modelCount: Int)
        case failed(String)
    }

    /// Typed key that hasn't been saved yet. The stored key is never read back just for display.
    @State private var keyDraft = ""
    @State private var keyError: String?
    @State private var models: [ModelInfo] = []
    @State private var checkState = CheckState.idle

    private var provider: LLMProvider { settings.provider }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            } footer: {
                Text(providerFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if provider == .appleOnDevice {
                Section("Status") {
                    Label(AppleModelAvailability.description, systemImage: AppleModelAvailability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(AppleModelAvailability.isAvailable ? Color.green : Color.orange)
                }
            } else {
                connectionSection
                modelSection
            }
        }
        .settingsPaneStyle()
        .onChange(of: settings.provider) { _, _ in
            keyDraft = ""
            keyError = nil
            models = []
            checkState = .idle
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section("Connection") {
            if provider.hasConfigurableBaseURL {
                TextField("Server address", text: $settings.compatibleBaseURL, prompt: Text(verbatim: "http://localhost:11434/v1"))
                Text(verbatim: "Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1 · OpenRouter: https://openrouter.ai/api/v1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent(provider.requiresAPIKey ? String(localized: "API key") : String(localized: "API key (optional)")) {
                HStack {
                    SecureField(
                        "API key",
                        text: $keyDraft,
                        prompt: Text(settings.hasAPIKey(for: provider) ? String(localized: "Saved in Keychain") : String(localized: "Paste your key"))
                    )
                    .labelsHidden()
                    .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if settings.hasAPIKey(for: provider) {
                        Button("Remove", role: .destructive, action: removeKey)
                    }
                }
            }
            if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let url = provider.apiKeyPageURL {
                Link(destination: url) {
                    Label("Get an API key", systemImage: "arrow.up.right.square")
                }
                .font(.callout)
            }
        }
    }

    private var modelSection: some View {
        Section {
            LabeledContent("Model") {
                HStack {
                    TextField("Model", text: modelBinding, prompt: Text("Model ID"))
                        .labelsHidden()
                        .monospaced()
                    Menu {
                        ForEach(models) { model in
                            Button {
                                settings.setModel(model.id, for: provider)
                            } label: {
                                if let name = model.displayName, name != model.id {
                                    Text(verbatim: "\(name) — \(model.id)")
                                } else {
                                    Text(verbatim: model.id)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(models.isEmpty)
                    .help(Text("Choose from the loaded models"))
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await checkConnection() }
                } label: {
                    Text("Check Key and Load Models")
                }
                .disabled(checkState == .checking)

                switch checkState {
                case .idle:
                    EmptyView()
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                case .succeeded(let count):
                    Label(String(localized: "Connected. Models available: \(count)."), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)
        } header: {
            Text("Model")
        } footer: {
            Text("The model must understand images to read screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.model(for: provider) },
            set: { settings.setModel($0, for: provider) }
        )
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try settings.setAPIKey(key, for: provider)
            keyDraft = ""
            keyError = nil
            checkState = .idle
        } catch {
            keyError = String(localized: "Couldn’t save the key to the Keychain: \(error.localizedDescription)")
        }
    }

    private func removeKey() {
        do {
            try settings.setAPIKey("", for: provider)
            keyError = nil
            checkState = .idle
            models = []
        } catch {
            keyError = String(localized: "Couldn’t remove the key from the Keychain: \(error.localizedDescription)")
        }
    }

    private func checkConnection() async {
        if !keyDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            saveKey()
        }
        let provider = self.provider
        checkState = .checking
        do {
            let key = try settings.apiKey(for: provider)
            let loaded = try await ModelCatalogClient.fetchModels(
                provider: provider,
                apiKey: key,
                baseURL: settings.compatibleBaseURLValue
            )
            guard provider == settings.provider else { return }
            models = loaded
            checkState = .succeeded(modelCount: loaded.count)
            if settings.model(for: provider).isEmpty, let first = loaded.first {
                settings.setModel(first.id, for: provider)
            }
        } catch let error as ProviderError {
            checkState = .failed(error.message)
        } catch {
            checkState = .failed(String(localized: "Couldn’t read the key from the Keychain: \(error.localizedDescription)"))
        }
    }

    private var providerFooter: String {
        switch provider {
        case .anthropic, .openAI, .gemini:
            String(localized: "Your text and screenshots are sent only to this provider, using your own key.")
        case .openAICompatible:
            String(localized: "Any server with an OpenAI-compatible API: a local model (Ollama, LM Studio, osaurus) or an aggregator like OpenRouter.")
        case .appleOnDevice:
            String(localized: "Apple’s on-device model: free, private, works offline. Screenshots are read with on-device text recognition.")
        }
    }
}
