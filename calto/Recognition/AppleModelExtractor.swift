import CaltoKit
import Foundation
import FoundationModels

/// Extraction with Apple's on-device model. Guided generation fills these types directly, so no
/// JSON parsing is involved; the result is mapped to the same `ExtractionResponse` the cloud providers
/// return. Properties are generated in order, so the facts from each source come first.
@Generable
nonisolated struct AppleExtraction {
    @Guide(description: "Every fact, name, identifier, number and instruction in the text the user typed.")
    var typedTextFacts: [String]
    @Guide(description: "Every fact relevant to the events from the text read from images; empty without images.")
    var imageFacts: [String]
    @Guide(description: "Every URL in the typed text and the images, exactly as written.")
    var links: [String]
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
    @Guide(description: "The event's main link: online meeting, ticket, chat message or event page.")
    var url: String?
    @Guide(description: "Every fact from the typed text and the images not in the other fields, verbatim. Never drop facts from the typed text.")
    var notes: String?
    @Guide(description: "Every URL that belongs to this event.")
    var links: [String]
    @Guide(description: "Up to 3 key quotes from the chat or message, verbatim.")
    var quotes: [String]
    @Guide(description: "Reminder offsets in minutes, only if reminders are explicitly requested.")
    var reminderMinutesBefore: [Int]?
    @Guide(description: "Short notes, in the user's language, about anything guessed or unclear.")
    var ambiguities: [String]
}

enum AppleModelExtractor {
    static func extract(prompt: ExtractionPrompt) async throws -> ExtractionResponse {
        guard AppleModelAvailability.isAvailable else {
            throw RecognitionError.appleModelUnavailable(AppleModelAvailability.description)
        }
        let session = LanguageModelSession(instructions: prompt.system)
        let content = try await session.respond(to: prompt.user, generating: AppleExtraction.self).content
        let events = content.events.map { event in
            WireEvent(
                title: event.title,
                start: event.start,
                end: event.end,
                allDay: event.allDay,
                timeZone: event.timeZone,
                location: event.location,
                url: event.url,
                notes: event.notes,
                links: event.links.map { WireLink(url: $0) },
                quotes: event.quotes,
                reminderMinutesBefore: event.reminderMinutesBefore,
                ambiguities: event.ambiguities
            )
        }
        let analysis = WireAnalysis(typedTextFacts: content.typedTextFacts, imageFacts: content.imageFacts, links: content.links)
        return ExtractionResponse(analysis: analysis, events: events)
    }
}
