import CaltoKit
import SwiftUI

/// Root of the popover. Each phase has its own natural size; the popover animates between them.
struct PopoverView: View {
    let model: PopoverModel
    let calendarAccess: CalendarAccess
    let openSettings: (SettingsTab?) -> Void

    var body: some View {
        Group {
            switch model.phase {
            case .input:
                InputSection(model: model, input: model.input, calendarAccess: calendarAccess, openSettings: openSettings)
            case .review:
                ReviewSection(model: model, calendarAccess: calendarAccess)
            case .saved(let count, _):
                SavedSection(model: model, count: count)
            }
        }
        .dropDestination(for: DroppedInput.self, isEnabled: true) { items, _ in
            if case .input = model.phase {
                model.input.addDropped(items)
            }
        }
    }
}

// MARK: - Input

struct InputSection: View {
    let model: PopoverModel
    @Bindable var input: InputModel
    let calendarAccess: CalendarAccess
    let openSettings: (SettingsTab?) -> Void

    private var settings: AppSettings { model.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners

            // Screenshots sit above the text they belong to.
            if !input.content.images.isEmpty || input.isProcessing {
                ThumbnailStrip(input: input)
                    .padding(.top, 12)
            }

            ComposerTextView(
                text: $input.content.text,
                isEditable: !model.isRecognizing,
                focusToken: input.focusToken,
                onPaste: { input.add($0) },
                onSubmit: { model.recognize() }
            )
            .overlay(alignment: .topLeading) {
                if input.content.text.isEmpty {
                    Text("Paste a screenshot or text, drop an image, or type: “Lunch with Anna tomorrow at 1 pm, remind me 15 and 30 minutes before”")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if let stage = model.stage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(stageText(stage))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity)
            } else if let notice = input.notice {
                Label(notice.message, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(notice.isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider()

            footer
        }
        .frame(width: 420)
        .animation(.default, value: model.stage)
    }

    @ViewBuilder
    private var banners: some View {
        if calendarAccess.status != .fullAccess && !calendarAccess.isRequesting {
            Banner(systemImage: "calendar.badge.exclamationmark", text: calendarBannerText) {
                if calendarAccess.status == .notDetermined {
                    Button("Allow") {
                        Task { await calendarAccess.requestAccess() }
                    }
                } else {
                    Button("Open Settings") {
                        openSettings(.general)
                    }
                }
            }
        }
        if !settings.isProviderReady {
            Banner(systemImage: "key.fill", text: String(localized: "Add an API key and choose a model in Settings to recognize events.")) {
                Button("Settings…") { openSettings(.model) }
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

    private func stageText(_ stage: RecognitionStage) -> String {
        switch stage {
        case .unlockingKey:
            String(localized: "Reading the API key… If macOS asks for the Keychain password, choose “Always Allow”.")
        case .readingText:
            String(localized: "Reading text on the images…")
        case .waitingForModel:
            String(localized: "Processing with \(settings.provider.shortName)…")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // The system Paste button: a user paste, so the clipboard is read without a privacy prompt.
            PasteButton(payloadType: DroppedInput.self) { @Sendable [input] items in
                Task { @MainActor in
                    input.addDropped(items)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(model.isRecognizing)
            .help(Text("Paste from the clipboard (⌘V)"))

            if calendarAccess.status == .fullAccess {
                DefaultCalendarMenu(settings: settings, calendarAccess: calendarAccess)
            }

            Button {
                openSettings(.model)
            } label: {
                Text(verbatim: modelLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(Text("Change the model"))

            Spacer(minLength: 8)

            if !input.content.isEmpty && !model.isRecognizing {
                Button {
                    input.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(Text("Clear"))
            }

            Button {
                openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(Text("Settings (⌘,)"))

            if model.isRecognizing {
                Button {
                    model.cancelRecognition()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .help(Text("Stop"))
                .accessibilityLabel(Text("Stop"))
            } else {
                Button {
                    model.recognize()
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(input.content.isEmpty || input.isProcessing)
                .help(Text("Create events (⌘↩)"))
                .accessibilityLabel(Text("Create events"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var modelLabel: String {
        let provider = settings.provider
        guard provider.usesModelSelection else { return provider.shortName }
        let model = settings.currentModel
        return model.isEmpty ? provider.shortName : "\(provider.shortName) · \(model)"
    }
}

/// Where new events go, right in the popover: the same setting as in Settings ▸ General.
struct DefaultCalendarMenu: View {
    @Bindable var settings: AppSettings
    let calendarAccess: CalendarAccess

    private var current: CalendarSummary? {
        calendarAccess.calendar(withID: calendarAccess.resolvedCalendarID(preferred: settings.defaultCalendarID))
    }

    var body: some View {
        Menu {
            Picker("Calendar for new events", selection: $settings.defaultCalendarID) {
                Text("Calendar app’s default").tag(String?.none)
                ForEach(calendarAccess.accounts) { account in
                    Section(account.title) {
                        ForEach(account.calendars) { calendar in
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Image(nsImage: CalendarSwatch.image(for: calendar.color))
                            }
                            .tag(String?.some(calendar.id))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                if let current {
                    Image(nsImage: CalendarSwatch.image(for: current.color))
                    Text(verbatim: current.title)
                        .lineLimit(1)
                } else {
                    Text("No calendar")
                }
            }
            .font(.caption)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .frame(maxWidth: 150, alignment: .leading)
        .help(Text("Calendar for new events"))
    }
}

struct Banner<Action: View>: View {
    let systemImage: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
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
}

struct ThumbnailStrip: View {
    let input: InputModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(input.content.images) { image in
                    thumbnail(image)
                }
                if input.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private func thumbnail(_ image: ImageAttachment) -> some View {
        Group {
            if let nsImage = input.thumbnails[image.id] {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(width: 96, height: 72)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                input.removeImage(image.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("Remove image")
        }
        .help(Text(verbatim: "\(image.pixelWidth) × \(image.pixelHeight)"))
    }
}

// MARK: - Saved

struct SavedSection: View {
    let model: PopoverModel
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("Events added: \(count)")
                .font(.headline)
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    model.undo()
                }
                Button("Open Calendar", systemImage: "calendar") {
                    model.openCalendarApp()
                }
                Button("New", systemImage: "plus") {
                    model.startOver()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
