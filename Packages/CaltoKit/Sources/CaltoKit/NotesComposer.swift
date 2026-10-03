import Foundation

/// Section titles of the composed notes, in the interface language (the app passes localized ones).
public struct NotesHeadings: Sendable, Hashable {
    public var links: String
    public var context: String

    public init(links: String, context: String) {
        self.links = links
        self.context = context
    }

    public static let english = NotesHeadings(links: "🔗 Links:", context: "💬 Context:")
}

/// Builds the event notes from the model's answer: the details, then every link (one per line, with
/// its label), then key quotes. Links are collected from everywhere the model may have put them, and
/// links found in the user's sources that the model didn't attach to any event are added to all of
/// them — so a link is never lost, whatever the model does.
public enum NotesComposer {
    public static func compose(_ events: [WireEvent], extraLinks: [String] = [], headings: NotesHeadings = .english) -> [String?] {
        let eventLinks = events.map(links(of:))
        let assigned = Set(eventLinks.flatMap { $0.map { LinkDetector.key(for: $0.url) } })
        var missing: [WireLink] = []
        var seen = assigned
        for link in extraLinks {
            guard let url = EventResolver.link(from: link)?.absoluteString, seen.insert(LinkDetector.key(for: url)).inserted else { continue }
            missing.append(WireLink(url: url))
        }
        return zip(events, eventLinks).map { event, links in
            notes(body: event.notes, links: links + missing, quotes: event.quotes, headings: headings)
        }
    }

    /// The event's links from `links`, `url` and URLs written inside `notes`, absolute and without duplicates.
    static func links(of event: WireEvent) -> [WireLink] {
        let candidates = event.links
            + [event.url].compactMap { $0 }.map { WireLink(url: $0) }
            + LinkDetector.links(in: event.notes ?? "").map { WireLink(url: $0) }
        var seen = Set<String>()
        var result: [WireLink] = []
        for candidate in candidates {
            guard let url = EventResolver.link(from: candidate.url)?.absoluteString,
                  seen.insert(LinkDetector.key(for: url)).inserted
            else { continue }
            let label = candidate.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(WireLink(url: url, label: label?.isEmpty == false ? label : nil))
        }
        return result
    }

    static func notes(body: String?, links: [WireLink], quotes: [String], headings: NotesHeadings) -> String? {
        var sections: [String] = []
        if let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            sections.append(body)
        }
        if !links.isEmpty {
            let lines = links.map { link in
                link.label.map { "• \($0) — \(link.url)" } ?? "• \(link.url)"
            }
            sections.append(([headings.links] + lines).joined(separator: "\n"))
        }
        let quotes = quotes
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»„' ").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        if !quotes.isEmpty {
            sections.append(([headings.context] + quotes.map { "“\($0)”" }).joined(separator: "\n"))
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }
}
