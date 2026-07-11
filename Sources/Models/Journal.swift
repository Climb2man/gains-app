import Foundation

/// One journal note: a timestamp and the user's free text, verbatim.
struct JournalNote: Codable, Equatable, Identifiable, Sendable {
    var id: String
    /// ISO 8601 timestamp (with fractional seconds) of when the note was written.
    var date: String
    /// The note's text, exactly as the user wrote it.
    var text: String

    init(id: String = UUID().uuidString, date: String, text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}
