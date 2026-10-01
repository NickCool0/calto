import Foundation
import Testing
@testable import CaltoKit

struct EventDraftTests {
    private func draft(notes: String?, url: String?) -> EventDraft {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return EventDraft(title: "X", start: start, end: start.addingTimeInterval(3600), url: url.flatMap(URL.init(string:)), notes: notes)
    }

    @Test("The link is added to the notes, since Exchange and Google drop the URL field")
    func linkAppended() {
        let event = draft(notes: "Есть БД mesh-sch-pgsql-cl1, нужно сделать таску на удаление", url: "https://t.me/c/4323376323/670")
        #expect(event.notesForSaving == "Есть БД mesh-sch-pgsql-cl1, нужно сделать таску на удаление\n\nhttps://t.me/c/4323376323/670")
    }

    @Test("Without notes the link alone becomes the notes")
    func linkOnly() {
        #expect(draft(notes: "  ", url: "https://zoom.us/j/1").notesForSaving == "https://zoom.us/j/1")
    }

    @Test("A link already in the notes isn't repeated, even written without the scheme", arguments: [
        "Join: https://zoom.us/j/1",
        "Join: zoom.us/j/1",
        "Join: HTTPS://ZOOM.US/j/1",
    ])
    func noDuplicate(notes: String) {
        #expect(draft(notes: notes, url: "https://zoom.us/j/1/").notesForSaving == notes)
    }

    @Test("No link: notes as they are, blank notes become nil")
    func noLink() {
        #expect(draft(notes: " Bring the passport \n", url: nil).notesForSaving == "Bring the passport")
        #expect(draft(notes: nil, url: nil).notesForSaving == nil)
    }
}
