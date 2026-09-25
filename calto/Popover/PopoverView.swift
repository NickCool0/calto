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
            case .recognizing:
                RecognizingSection(model: model)
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

    @FocusState private var textFocused: Bool

    private var settings: AppSettings { model.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners

            TextField("Text", text: $input.content.text, prompt: Text("Paste text or a screenshot, or drop an image…"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(3...12)
                .focused($textFocused)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if !input.content.images.isEmpty || input.isProcessing {
                ThumbnailStrip(input: input)
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                TextField(
                    "Instruction",
                    text: $input.instruction,
                    prompt: Text("Instruction (optional): “only meetings with Anna”, “remind me an hour before”"),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let notice = input.notice {
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
        .onAppear { textFocused = true }
        .onChange(of: input.focusToken) { _, _ in
            textFocused = true
        }
    }

    @ViewBuilder
    private var banners: some View {
        if calendarAccess.status != .fullAccess {
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

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                if !input.pasteImages() {
                    input.add(PasteboardReader.read())
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help(Text("Paste from the clipboard (⌘V)"))

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

            if !input.content.isEmpty || !input.instruction.isEmpty {
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

            Button("Recognize") {
                model.recognize()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(input.content.isEmpty || input.isProcessing)
            .help(Text("Recognize events (⌘↩)"))
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

// MARK: - Recognizing

struct RecognizingSection: View {
    let model: PopoverModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Recognizing events with \(model.settings.provider.shortName)…")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) {
                model.cancelRecognition()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 420)
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
