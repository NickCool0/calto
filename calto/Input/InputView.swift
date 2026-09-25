import CaltoKit
import SwiftUI

struct InputView: View {
    @Bindable var model: InputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            imageZone
            textEditor
            TextField(
                "Instruction",
                text: $model.instruction,
                prompt: Text("Optional instruction, e.g. “only meetings with Anna”, “remind me an hour before”"),
                axis: .vertical
            )
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .labelsHidden()

            if let notice = model.notice {
                Label(notice.message, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(notice.isError ? Color.red : Color.secondary)
            }

            HStack {
                Button("Clear") {
                    model.clear()
                }
                .disabled(model.content.isEmpty && model.instruction.isEmpty)
                Spacer()
                Button("Recognize") {
                    model.recognize()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.content.isEmpty || model.isProcessing)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 420)
        .dropDestination(for: DroppedInput.self, isEnabled: true) { items, _ in
            model.addDropped(items)
        }
    }

    private var imageZone: some View {
        Group {
            if model.content.images.isEmpty && !model.isProcessing {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.largeTitle)
                    Text("Paste a screenshot (⌘V) or drop images here")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.content.images) { image in
                            thumbnail(image)
                        }
                        if model.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(height: 112)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
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
        .frame(width: 128, height: 92)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            Button {
                model.removeImage(image.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Remove image")
        }
        .help(Text(verbatim: "\(image.pixelWidth) × \(image.pixelHeight)"))
    }

    private var textEditor: some View {
        TextEditor(text: $model.content.text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .overlay(alignment: .topLeading) {
                if model.content.text.isEmpty {
                    Text("…or paste or type the text of an invitation, chat or schedule")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator)
            }
            .frame(minHeight: 120)
    }
}

#Preview {
    InputView(model: InputModel())
}
