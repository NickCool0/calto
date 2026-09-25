import Foundation

/// A fake provider for developing and testing the app without an API key or network.
/// It answers in the same JSON the real providers return, so the whole pipeline runs.
public enum MockExtractor {
    /// Deterministic answer: every non-empty line of text becomes an event on consecutive days
    /// at 10:00; with no text (images only) there is one sample event tomorrow.
    public static func output(for request: ExtractionRequest) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = request.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = request.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let lines = (request.text ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let titles = lines.isEmpty ? ["Demo event"] : Array(lines.prefix(5))

        let events = titles.enumerated().map { index, title in
            let day = calendar.date(byAdding: .day, value: index + 1, to: request.referenceDate) ?? request.referenceDate
            let date = formatter.string(from: day)
            return WireEvent(
                title: String(title.prefix(80)),
                start: "\(date)T10:00",
                end: "\(date)T11:00",
                notes: "Created by the mock provider.",
                ambiguities: index == 0 ? ["Mock provider: dates are placeholders."] : []
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(ExtractionResponse(events: events))) ?? Data(#"{"events":[]}"#.utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
