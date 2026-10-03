import CaltoKit
import SwiftUI

/// Filters in the toolbar.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, created, notAdded, failed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .created: String(localized: "Added")
        case .notAdded: String(localized: "Not added")
        case .failed: String(localized: "Errors")
        }
    }

    func includes(_ entry: HistoryEntry) -> Bool {
        switch self {
        case .all: true
        case .created: entry.status == .created
        case .notAdded: entry.status == .notAdded || entry.status == .undone || entry.status == .noEvents
        case .failed: entry.status == .failed
        }
    }
}

/// The history window: requests grouped by day on the left, what was sent, recognized and saved on the right.
struct HistoryView: View {
    let context: AppContext

    @State private var selection: UUID?
    @State private var query = ""
    @State private var filter = HistoryFilter.all

    private var history: HistoryRecorder { context.history }

    private var filtered: [HistoryEntry] {
        history.entries.filter { filter.includes($0) && $0.matches(query) }
    }

    private var sections: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sections, id: \.day) { section in
                    Section(Self.dayTitle(section.day)) {
                        ForEach(section.entries) { entry in
                            HistoryRow(entry: entry)
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Delete from History", systemImage: "trash", role: .destructive) {
                                        history.delete(entry.id)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if filtered.isEmpty {
                    if history.entries.isEmpty {
                        ContentUnavailableView(
                            "No requests yet",
                            systemImage: "clock",
                            description: history.isEnabled ? Text("Requests you send from the popover appear here.") : Text("History is turned off in Settings.")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            if let id = selection, let entry = history.entries.first(where: { $0.id == id }) {
                HistoryDetail(entry: entry, context: context)
                    .id(entry.id)
            } else {
                ContentUnavailableView("Select a request", systemImage: "sidebar.left", description: Text("See what you sent, what was recognized and what you changed."))
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search requests and events"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(Text("Show"))
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear {
            selection = selection ?? history.entries.first?.id
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

/// A request in the sidebar.
struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.status.symbol)
                .foregroundStyle(entry.status.tint)
                .frame(width: 18)
                .accessibilityLabel(Text(entry.status.title))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if let title = entry.displayTitle { return title }
        if let text = entry.inputText?.split(separator: "\n").first { return String(text) }
        return entry.thumbnails.isEmpty ? String(localized: "Request") : String(localized: "Screenshot")
    }

    private var subtitle: String {
        var parts = [entry.date.formatted(date: .omitted, time: .shortened)]
        let count = entry.saved.count
        if count > 1 {
            parts.append(String(localized: "\(count) events"))
        }
        parts.append(entry.status.title)
        return parts.joined(separator: " · ")
    }
}

extension HistoryEntry.Status {
    var title: String {
        switch self {
        case .created: String(localized: "Added")
        case .notAdded: String(localized: "Not added")
        case .undone: String(localized: "Undone")
        case .noEvents: String(localized: "No events found")
        case .failed: String(localized: "Error")
        }
    }

    var symbol: String {
        switch self {
        case .created: "checkmark.circle.fill"
        case .notAdded: "minus.circle"
        case .undone: "arrow.uturn.backward.circle"
        case .noEvents: "questionmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .created: .green
        case .failed: .orange
        case .notAdded, .undone, .noEvents: .secondary
        }
    }
}

/// One request: what was sent, the events as recognized and as saved, with the user's changes marked.
struct HistoryDetail: View {
    let entry: HistoryEntry
    let context: AppContext

    @State private var eventToDelete: SavedEvent?

    private var history: HistoryRecorder { context.history }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                sentSection
                if let error = entry.errorMessage, entry.status == .failed {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                eventsSection
                technicalSection
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle(entry.displayTitle ?? String(localized: "Request"))
        .toolbar {
            ToolbarItemGroup {
                Button("Repeat Request", systemImage: "arrow.clockwise") {
                    repeatRequest()
                }
                .help(Text("Put the text and screenshots back into the popover"))
                Button("Delete from History", systemImage: "trash") {
                    history.delete(entry.id)
                }
                .help(Text("Delete from History"))
            }
        }
        .confirmationDialog(
            Text("Delete “\(eventToDelete?.draft.title ?? "")” from your calendar?"),
            isPresented: Binding(get: { eventToDelete != nil }, set: { if !$0 { eventToDelete = nil } }),
            presenting: eventToDelete
        ) { event in
            Button("Delete Event", role: .destructive) {
                deleteFromCalendar(event)
            }
        } message: { _ in
            Text("The event is removed from Calendar on all your devices. This can’t be undone.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date.formatted(date: .complete, time: .shortened))
                .font(.headline)
            HStack(spacing: 6) {
                Label(entry.status.title, systemImage: entry.status.symbol)
                    .foregroundStyle(entry.status.tint)
                Text(verbatim: "·")
                entry.mode == .automatic ? Text("Added automatically") : Text("Reviewed before adding")
                Text(verbatim: "·")
                Text(verbatim: entry.model.isEmpty ? entry.provider : "\(entry.provider) · \(entry.model)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var sentSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if !entry.thumbnails.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(entry.thumbnails, id: \.self) { name in
                                if let image = history.thumbnail(name) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 120)
                                        .clipShape(.rect(cornerRadius: 6))
                                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
                if let text = entry.inputText {
                    Text(verbatim: text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if entry.thumbnails.isEmpty {
                    Text("Nothing was typed.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Label("You sent", systemImage: "arrow.up.circle")
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !entry.recognized.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(entry.recognized.enumerated()), id: \.element.id) { index, recognized in
                        if index > 0 { Divider() }
                        HistoryEventView(
                            recognized: recognized,
                            saved: entry.saved.first { $0.draft.id == recognized.id },
                            wasSaved: entry.status == .created || entry.status == .undone,
                            openInCalendar: { context.calendarAccess.openInCalendar(eventIdentifier: $0.eventIdentifier) },
                            delete: { eventToDelete = $0 }
                        )
                    }
                }
                .padding(4)
            } label: {
                Label("Recognized → Saved", systemImage: "calendar.badge.checkmark")
            }
        }
    }

    @ViewBuilder
    private var technicalSection: some View {
        if let analysis = entry.analysis, !(analysis.typedTextFacts + analysis.imageFacts + analysis.links).isEmpty {
            DisclosureGroup("What the model read") {
                VStack(alignment: .leading, spacing: 8) {
                    factList("From your text", analysis.typedTextFacts)
                    factList("From the screenshots", analysis.imageFacts)
                    factList("Links", analysis.links)
                }
                .padding(.top, 6)
                .textSelection(.enabled)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func factList(_ title: LocalizedStringKey, _ facts: [String]) -> some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ForEach(facts, id: \.self) { fact in
                    Text(verbatim: "• \(fact)")
                }
            }
        }
    }

    // MARK: Actions

    private func repeatRequest() {
        let images = entry.thumbnails.compactMap { try? Data(contentsOf: history.store.thumbnailURL($0)) }
        // Close first: while the history window is open, the popover won't show.
        HistoryWindowController.close()
        context.repeatRequest?(entry.inputText, images)
    }

    private func deleteFromCalendar(_ event: SavedEvent) {
        guard let identifier = event.eventIdentifier else { return }
        do {
            try context.calendarAccess.removeEvents(withIdentifiers: [identifier])
            history.update(entry.id) { entry in
                for index in entry.saved.indices where entry.saved[index].eventIdentifier == identifier {
                    entry.saved[index].removed = true
                }
            }
        } catch {
            NSSound.beep()
        }
    }
}

/// One event: the saved values, with what the user changed shown as "before → after".
struct HistoryEventView: View {
    let recognized: EventDraft
    let saved: SavedEvent?
    let wasSaved: Bool
    let openInCalendar: (SavedEvent) -> Void
    let delete: (SavedEvent) -> Void

    private var shown: EventDraft { saved?.draft ?? recognized }
    private var changed: Set<HistoryDiff.Field> {
        saved.map { Set(HistoryDiff.changedFields(from: recognized, to: $0.draft)) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: shown.title.isEmpty ? String(localized: "Untitled") : shown.title)
                    .font(.headline)
                Spacer()
                status
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                row(.time, "clock", Self.timeText(recognized), Self.timeText(shown))
                if let saved {
                    GridRow {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                        Text(verbatim: saved.calendarTitle)
                    }
                }
                row(.reminders, "bell", Self.alarmsText(recognized), Self.alarmsText(shown))
                row(.location, "mappin.and.ellipse", recognized.location, shown.location)
                row(.link, "link", recognized.url?.absoluteString, shown.url?.absoluteString)
                row(.recurrence, "repeat", recognized.recurrence.map(RecurrenceText.describe), shown.recurrence.map(RecurrenceText.describe))
                row(.notes, "text.alignleft", recognized.notes, shown.notes)
            }
            if changed.contains(.title) {
                Label {
                    Text("Title was “\(recognized.title)”")
                } icon: {
                    Image(systemName: "pencil")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let saved, saved.eventIdentifier != nil, !saved.removed {
                HStack {
                    Button("Open in Calendar", systemImage: "calendar") { openInCalendar(saved) }
                    Button("Delete from Calendar…", systemImage: "trash", role: .destructive) { delete(saved) }
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let saved {
            if saved.removed {
                Label("Removed from Calendar", systemImage: "trash").foregroundStyle(.secondary)
            } else if !changed.isEmpty {
                Label("Edited before saving", systemImage: "pencil.circle").foregroundStyle(.tint)
            } else {
                Label("Saved as recognized", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
        } else if wasSaved {
            Label("Not added", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }

    /// A field row; when the user changed it, the recognized value is shown struck through above the saved one.
    @ViewBuilder
    private func row(_ field: HistoryDiff.Field, _ symbol: String, _ before: String?, _ after: String?) -> some View {
        if before?.isEmpty == false || after?.isEmpty == false {
            GridRow {
                Image(systemName: symbol).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if changed.contains(field), let before, !before.isEmpty {
                        Text(verbatim: before)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Was: \(before)"))
                    }
                    if let after, !after.isEmpty {
                        Text(verbatim: after)
                            .foregroundStyle(changed.contains(field) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .textSelection(.enabled)
                    } else if changed.contains(field) {
                        Text("Removed").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    static func timeText(_ draft: EventDraft) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: draft.isAllDay ? .omitted : .shortened)
        style.timeZone = draft.timeZone ?? .current
        let start = draft.start.formatted(style)
        guard draft.end > draft.start else { return start }
        let sameDay = Calendar.current.isDate(draft.start, inSameDayAs: draft.end)
        var endStyle = sameDay && !draft.isAllDay ? Date.FormatStyle(date: .omitted, time: .shortened) : style
        endStyle.timeZone = style.timeZone
        let end = draft.end.formatted(endStyle)
        return start == end ? start : "\(start) – \(end)"
    }

    static func alarmsText(_ draft: EventDraft) -> String? {
        draft.alarms.isEmpty ? nil : draft.alarms.map(AlarmText.describe).joined(separator: ", ")
    }
}
