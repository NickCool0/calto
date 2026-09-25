import CaltoKit
import SwiftUI

/// The review screen: one editable card per recognized event, nothing is saved until "Add".
struct ReviewSection: View {
    @Bindable var model: PopoverModel
    let calendarAccess: CalendarAccess

    @State private var contentHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left") {
                    model.backToInput()
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Found: \(model.items.count)")
                    .font(.headline)
                Spacer()
                // Balances the back button so the title stays centered.
                Color.clear.frame(width: 60, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($model.items) { $item in
                        ReviewCard(item: $item, model: model, calendarAccess: calendarAccess)
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    contentHeight = height
                }
            }
            .frame(height: min(max(contentHeight, 120), maxListHeight))

            if let error = model.reviewError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Text("Nothing is saved until you add the events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(addTitle) {
                    model.save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 460)
    }

    private var addTitle: String {
        String(localized: "Add to Calendar (\(model.includedCount))")
    }
}

struct ReviewCard: View {
    @Binding var item: ReviewItem
    let model: PopoverModel
    let calendarAccess: CalendarAccess

    @State private var showDetails = false

    private var eventZone: TimeZone { item.draft.timeZone ?? .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("Include", isOn: $item.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                TextField("Title", text: $item.draft.title, prompt: Text("Title"))
                    .textFieldStyle(.plain)
                    .font(.headline)
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    rowIcon("clock")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            DatePicker("Start", selection: startBinding, displayedComponents: dateComponents)
                                .labelsHidden()
                                .fieldBackground()
                            Text(verbatim: "–")
                                .foregroundStyle(.secondary)
                            DatePicker("End", selection: endBinding, in: item.draft.start..., displayedComponents: dateComponents)
                                .labelsHidden()
                                .fieldBackground()
                        }
                        // The bordered field style draws a bezel that blurs on the popover's glass; the
                        // compact style has none (a click opens a calendar), so the edge is ours and crisp.
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, eventZone)
                        HStack(spacing: 12) {
                            Toggle("All day", isOn: allDayBinding)
                                .toggleStyle(.checkbox)
                            if let zone = item.draft.timeZone, zone != .current {
                                Label(zone.localizedName(for: .shortGeneric, locale: .current) ?? zone.identifier, systemImage: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                GridRow {
                    rowIcon("calendar")
                    CalendarPicker(selection: $item.calendarID, accounts: calendarAccess.accounts)
                }
                GridRow {
                    rowIcon("bell")
                    AlarmEditor(alarms: $item.draft.alarms)
                }
                if let recurrence = item.draft.recurrence {
                    GridRow {
                        rowIcon("repeat")
                        HStack {
                            Text(RecurrenceText.describe(recurrence))
                                .font(.callout)
                            Button {
                                item.draft.recurrence = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(Text("Don’t repeat"))
                        }
                    }
                }
            }

            DisclosureGroup("Location, link and notes", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Location", text: optionalText(\.location), prompt: Text("Location"))
                        .fieldBackground()
                    TextField("Link", text: linkText, prompt: Text("Link"))
                        .fieldBackground()
                    TextField("Notes", text: optionalText(\.notes), prompt: Text("Notes"), axis: .vertical)
                        .lineLimit(1...5)
                        .fieldBackground()
                }
                .textFieldStyle(.plain)
                .padding(.top, 4)
            }
            .font(.callout)

            WarningList(warnings: warnings)
        }
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 10))
        .opacity(item.isIncluded ? 1 : 0.55)
        .onAppear {
            showDetails = item.draft.location != nil || item.draft.url != nil || item.draft.notes != nil
        }
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .gridColumnAlignment(.center)
    }

    private var dateComponents: DatePickerComponents {
        item.draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    // MARK: Bindings

    /// Moving the start keeps the duration.
    private var startBinding: Binding<Date> {
        Binding(
            get: { item.draft.start },
            set: { newStart in
                let duration = item.draft.end.timeIntervalSince(item.draft.start)
                item.draft.start = newStart
                item.draft.end = newStart.addingTimeInterval(max(duration, 0))
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { item.draft.end },
            set: { item.draft.end = max($0, item.draft.start) }
        )
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { item.draft.isAllDay },
            set: { allDay in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = eventZone
                let day = calendar.startOfDay(for: item.draft.start)
                if allDay {
                    item.draft.start = day
                    item.draft.end = max(calendar.startOfDay(for: item.draft.end), day)
                } else {
                    let nine = calendar.date(byAdding: .hour, value: 9, to: day) ?? day
                    item.draft.start = nine
                    item.draft.end = nine.addingTimeInterval(TimeInterval(model.settings.defaultDurationMinutes * 60))
                }
                item.draft.isAllDay = allDay
            }
        )
    }

    private func optionalText(_ keyPath: WritableKeyPath<EventDraft, String?>) -> Binding<String> {
        Binding(
            get: { item.draft[keyPath: keyPath] ?? "" },
            set: { item.draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var linkText: Binding<String> {
        Binding(
            get: { item.draft.url?.absoluteString ?? "" },
            set: { item.draft.url = EventResolver.link(from: $0) }
        )
    }

    // MARK: Warnings

    private var warnings: [Warning] {
        var result: [Warning] = item.draft.ambiguities.map { Warning(text: $0, systemImage: "questionmark.circle") }
        result += item.draft.issues.map { Warning(text: $0.message, systemImage: "exclamationmark.triangle") }
        if item.draft.title.trimmed.isEmpty {
            result.append(Warning(text: String(localized: "Add a title."), systemImage: "exclamationmark.triangle"))
        }
        for event in model.duplicates(for: item) {
            result.append(Warning(
                text: String(localized: "Probably already in your calendar: “\(event.title)”, \(event.start.formatted(date: .abbreviated, time: .shortened))"),
                systemImage: "doc.on.doc"
            ))
        }
        for event in model.conflicts(for: item) {
            result.append(Warning(
                text: String(localized: "Overlaps with “\(event.title)”, \(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"),
                systemImage: "calendar.badge.exclamationmark"
            ))
        }
        if let limit = model.alarmLimit(for: item), let kept = limit.kept.first {
            result.append(Warning(
                text: String(localized: "This calendar keeps only one reminder: “\(AlarmText.describe(kept))” will be saved."),
                systemImage: "bell.slash"
            ))
        }
        return result
    }
}

struct Warning: Hashable {
    let text: String
    let systemImage: String
}

struct WarningList: View {
    let warnings: [Warning]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning.text, systemImage: warning.systemImage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct CalendarPicker: View {
    @Binding var selection: String?
    let accounts: [CalendarAccount]

    var body: some View {
        Picker("Calendar", selection: $selection) {
            if selection == nil {
                Text("Choose a calendar").tag(String?.none)
            }
            ForEach(accounts) { account in
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
        .labelsHidden()
        .fixedSize()
    }
}

struct AlarmEditor: View {
    @Binding var alarms: [EventAlarm]

    private static let presets = [0, 5, 10, 15, 30, 60, 120, 1440, 2880]

    var body: some View {
        HStack(spacing: 6) {
            if alarms.isEmpty {
                Text("No reminder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(alarms, id: \.self) { alarm in
                Button {
                    alarms.removeAll { $0 == alarm }
                } label: {
                    HStack(spacing: 3) {
                        Text(AlarmText.describe(alarm))
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Text("Remove reminder"))
            }
            Menu {
                ForEach(Self.presets.filter { minutes in !alarms.contains { $0.minutesBefore == minutes } }, id: \.self) { minutes in
                    Button(AlarmText.describe(EventAlarm(minutesBefore: minutes))) {
                        alarms = (alarms + [EventAlarm(minutesBefore: minutes)]).sorted()
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Add a reminder"))
        }
    }
}

enum AlarmText {
    static func describe(_ alarm: EventAlarm) -> String {
        guard alarm.minutesBefore > 0 else { return String(localized: "At start time") }
        let duration = Duration.seconds(Int64(alarm.minutesBefore) * 60)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        return String(localized: "\(duration) before")
    }
}

enum RecurrenceText {
    static func describe(_ recurrence: Recurrence) -> String {
        let frequency = switch recurrence.frequency {
        case .daily: String(localized: "Every day")
        case .weekly: String(localized: "Every week")
        case .monthly: String(localized: "Every month")
        case .yearly: String(localized: "Every year")
        }
        var parts = [frequency]
        if recurrence.interval > 1 {
            parts.append(String(localized: "interval: \(recurrence.interval)"))
        }
        if !recurrence.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            parts.append(recurrence.weekdays.map { symbols[$0.rawValue - 1] }.joined(separator: ", "))
        }
        if let count = recurrence.count {
            parts.append(String(localized: "occurrences: \(count)"))
        }
        if let until = recurrence.until {
            parts.append(String(localized: "until \(until.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

extension ResolutionIssue {
    var message: String {
        switch self {
        case .invalidStart(let value):
            String(localized: "Couldn’t read the date “\(value)”. Check the time.")
        case .invalidEnd(let value):
            String(localized: "Couldn’t read the end “\(value)”; the default duration is used.")
        case .endBeforeStart:
            String(localized: "The end was before the start; the default duration is used.")
        case .unknownTimeZone(let value):
            String(localized: "Unknown time zone “\(value)”; your time zone is used.")
        case .unsupportedRecurrence(let value):
            String(localized: "Repeat rule “\(value)” isn’t supported and was dropped.")
        case .missingTitle:
            String(localized: "The event has no title.")
        }
    }
}

extension View {
    /// A field's backdrop drawn by SwiftUI, sharp on the popover's glass (AppKit bezels blur there).
    func fieldBackground() -> some View {
        padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }
}

/// Colored dots for calendar menus; SF Symbols in menus are drawn as templates and lose their color.
enum CalendarSwatch {
    static func image(for color: NSColor) -> NSImage {
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let (red, green, blue) = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { @Sendable rect in
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
