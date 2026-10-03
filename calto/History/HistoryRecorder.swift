import AppKit
import CaltoKit
import Observation

/// Records every request in the history and keeps the list for the history window.
/// Changes are applied in memory first and written in order, so a quick "save, then undo" never
/// reaches the disk the wrong way round.
@MainActor
@Observable
final class HistoryRecorder {
    private(set) var entries: [HistoryEntry] = []

    let store: HistoryStore
    private let settings: AppSettings
    @ObservationIgnored private var writes: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = HistoryStore(directory: support.appending(path: "History", directoryHint: .isDirectory))
        let retention = settings.historyRetention
        enqueue { store in
            try? await store.prune(retention)
        }
        Task { await reload() }
    }

    var isEnabled: Bool {
        settings.historyRetention != .off
    }

    func reload() async {
        await writes?.value
        entries = await store.all()
    }

    /// Starts an entry for a request; returns its id, or `nil` when history is off.
    func begin(_ request: ExtractionRequest, mode: AddMode) -> UUID? {
        guard isEnabled else { return nil }
        let images = request.images
        let names = images.map { _ in "\(UUID().uuidString).jpg" }
        let entry = HistoryEntry(
            date: request.referenceDate,
            mode: mode,
            provider: settings.provider.shortName,
            model: settings.provider.usesModelSelection ? settings.currentModel : "",
            inputText: request.text,
            thumbnails: names,
            status: .notAdded
        )
        entries.insert(entry, at: 0)
        enqueue { store in
            for (image, name) in zip(images, names) {
                let data = image.data
                if let thumbnail = await Task.detached(priority: .utility, operation: { ImageNormalizer.thumbnail(data) }).value {
                    _ = try? await store.saveThumbnail(thumbnail, named: name)
                }
            }
            try? await store.save(entry)
        }
        return entry.id
    }

    /// Changes an entry and writes it.
    func update(_ id: UUID?, _ change: (inout HistoryEntry) -> Void) {
        guard let id, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        let entry = entries[index]
        enqueue { store in
            try? await store.save(entry)
        }
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        enqueue { store in
            try? await store.delete(id: id)
        }
    }

    func deleteAll() {
        entries = []
        enqueue { store in
            try? await store.deleteAll()
        }
    }

    /// Applies a new retention setting right away.
    func applyRetention() {
        let retention = settings.historyRetention
        enqueue { store in
            try? await store.prune(retention)
        }
        Task { await reload() }
    }

    func thumbnail(_ name: String) -> NSImage? {
        NSImage(contentsOf: store.thumbnailURL(name))
    }

    private func enqueue(_ operation: @escaping @Sendable (HistoryStore) async -> Void) {
        let previous = writes
        let store = store
        writes = Task {
            await previous?.value
            await operation(store)
        }
    }
}
