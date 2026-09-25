import CaltoKit
import SwiftUI

/// The popup under the menu bar icon: one large field for text, screenshots below it,
/// an optional instruction and a footer with shortcuts, the current model and settings.
struct InputView: View {
    struct Actions {
        let openSettings: (SettingsTab?) -> Void
        let openCalendarPrivacy: () -> Void
        let close: () -> Void
    }

    @Bindable var model: InputModel
    let settings: AppSettings
    let calendarAccess: CalendarAccess
    let actions: Actions

    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            banners
            textEditor
            if !model.content.images.isEmpty || model.isProcessing {
                thumbnails
            }
            Divider()
            instructionField
            if let notice = model.notice {
                noticeRow(notice)
            }
            Divider()
            footer
        }
        .frame(width: InputPanelController.size.width, height: InputPanelController.size.height)
        .overlay {
            RoundedRectangle(cornerRadius: InputPanelController.cornerRadius)
                .strokeBorder(.separator)
        }
        .clipShape(.rect(cornerRadius: InputPanelController.cornerRadius))
        .dropDestination(for: DroppedInput.self, isEnabled: true) { items, _ in
            model.addDropped(items)
        }
        .onChange(of: model.focusToken) { _, _ in
            textFocused = true
        }
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if calendarAccess.status != .fullAccess {
            banner(systemImage: "calendar.badge.exclamationmark", text: calendarBannerText) {
                if calendarAccess.status == .notDetermined {
                    Button("Allow") {
                        Task { await calendarAccess.requestAccess() }
                    }
                } else {
                    Button("Open Settings", action: actions.openCalendarPrivacy)
                }
            }
        }
        if !settings.isProviderReady {
            banner(systemImage: "key.fill", text: String(localized: "Add an API key and choose a model in Settings to recognize events.")) {
                Button("Settings…") { actions.openSettings(.model) }
            }
        }
    }

    private var calendarBannerText: String {
        switch calendarAccess.status {
        case .notDetermined: String(localized: "calto needs access to your calendars to add events.")
        case .writeOnly: String(localized: "calto can only add events. Allow full access to check for conflicts and duplicates.")
        case .denied, .fullAccess: String(localized: "Calendar access is off. Allow it in System Settings → Privacy & Security → Calendars.")
        }
    }

    private func banner<Action: View>(systemImage: String, text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Color.orange.opacity(0.1)
        }
    }

    // MARK: Content

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if model.content.text.isEmpty {
                Text("Paste text or a screenshot, or drop an image…")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 21)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.content.text)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .focused($textFocused)
        }
        .frame(maxHeight: .infinity)
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.content.images) { image in
                    thumbnail(image)
                }
                if model.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .frame(height: 88)
    }

    private func thumbnail(_ image: ImageAttachment) -> some View {
        Group {
            if let nsImage = model.thumbnails[image.id] {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(width: 104, height: 76)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                model.removeImage(image.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove image")
        }
        .help(Text(verbatim: "\(image.pixelWidth) × \(image.pixelHeight)"))
    }

    private var instructionField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
            TextField(
                "Instruction",
                text: $model.instruction,
                prompt: Text("Instruction (optional): “only meetings with Anna”, “remind me an hour before”"),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...3)
            .onSubmit { model.recognize(settings: settings) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func noticeRow(_ notice: InputModel.Notice) -> some View {
        Label(notice.message, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.callout)
            .foregroundStyle(notice.isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("⌘V paste · ⌘↩ recognize · Esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                actions.openSettings(.model)
            } label: {
                Text(verbatim: modelLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 170)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(Text("Change the model"))

            if !model.content.isEmpty || !model.instruction.isEmpty {
                Button {
                    model.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Text("Clear"))
            }

            Button {
                actions.openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(Text("Settings (⌘,)"))

            Button("Recognize") {
                model.recognize(settings: settings)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(model.content.isEmpty || model.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modelLabel: String {
        let provider = settings.provider
        guard provider.usesModelSelection else { return provider.shortName }
        let model = settings.currentModel
        return model.isEmpty ? provider.shortName : "\(provider.shortName) · \(model)"
    }
}
