import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Lectures in the phone's own search (Spotlight): title, class, date and topics, so "LR parsing" on the home screen
/// finds the lecture, and a tap opens it here.
enum SpotlightIndex {
    static let domain = "app.studystash.lectures"

    static func index(_ lectures: [LectureSummary]) {
        let items = lectures.map { l -> CSSearchableItem in
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = l.displayTitle
            a.contentDescription = [l.class, Format.lectureMeta(l.date, l.seconds), l.summary.isEmpty ? nil : l.summary]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            a.keywords = l.topics + [l.class].compactMap { $0 }
            a.contentCreationDate = Format.parse(l.date)
            return CSSearchableItem(uniqueIdentifier: l.id, domainIdentifier: domain, attributeSet: a)
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
