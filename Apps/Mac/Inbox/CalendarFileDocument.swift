// An event proposal's iCalendar text as a file the owner saves and adds to a calendar themselves; Lisa never writes
// to a calendar.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The `.ics` file of one event proposal, for the save panel (EVENT-01).
struct CalendarFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.calendarEvent] }

    /// The iCalendar text from the host.
    let text: String

    /// A file with `text`.
    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
