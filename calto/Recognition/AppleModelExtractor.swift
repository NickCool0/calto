import CaltoKit
import Foundation
import FoundationModels

/// Extraction with Apple's on-device model. Guided generation fills these types directly, so no
/// JSON parsing is involved; the result is mapped to the same `WireEvent`s the cloud providers return.
@Generable
nonisolated struct AppleExtraction {
    @Guide(description: "Every distinct calendar event found; empty if there is none.")
    var events: [AppleEvent]
}

@Generable
nonisolated struct AppleEvent {
    @Guide(description: "Short, specific title in the language of the source.")
    var title: String
    @Guide(description: "Local start time YYYY-MM-DDTHH:MM, or YYYY-MM-DD for an all-day event.")
    var start: String
    @Guide(description: "Local end time in the same format, only if stated.")
    var end: String?
    @Guide(description: "True for all-day events.")
    var allDay: Bool
    @Guide(description: "IANA time zone, only if the source states one explicitly.")
    var timeZone: String?
    var location: String?
    @Guide(description: "Online meeting link or event page.")
    var url: String?
    var notes: String?
    @Guide(description: "Reminder offsets in minutes, only if reminders are explicitly requested.")
    var reminderMinutesBefore: [Int]?
    @Guide(description: "Short notes, in the user's language, about anything guessed or unclear.")
    var ambiguities: [String]
}

enum AppleModelExtractor {
    static func extract(prompt: ExtractionPrompt) async throws -> [WireEvent] {
        guard AppleModelAvailability.isAvailable else {
            throw RecognitionError.appleModelUnavailable(AppleModelAvailability.description)
        }
        let session = LanguageModelSession(instructions: prompt.system)
        let response = try await session.respond(to: prompt.user, generating: AppleExtraction.self)
        return response.content.events.map { event in
            WireEvent(
                title: event.title,
                start: event.start,
                end: event.end,
                allDay: event.allDay,
                timeZone: event.timeZone,
                location: event.location,
                url: event.url,
                notes: event.notes,
                reminderMinutesBefore: event.reminderMinutesBefore,
                ambiguities: event.ambiguities
            )
        }
    }
}
