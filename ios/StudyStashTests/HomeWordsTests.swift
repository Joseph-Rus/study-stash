import Foundation
import Testing
@testable import StudyStash

// MARK: - Home's sentence

/// What Home's sentence says on a Friday morning (16 October 2026, 9:30 AM here), as a student would read it.
@Suite struct HomeWordsTests {
    let now = Format.calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9, minute: 30))!
    let words = Words(school: true, work: false)

    func event(_ title: String, _ start: String, minutes: Int = 50, cls: String? = nil) -> UpcomingEvent {
        let s = Format.parse(start)!
        return UpcomingEvent(id: title + start, title: title, start: start,
                             end: Format.words(s.addingTimeInterval(Double(minutes) * 60), "yyyy-MM-dd'T'HH:mm:ss"),
                             allDay: false, location: nil, class: cls ?? title)
    }

    func item(_ name: String, _ due: String, kind: String = "assignment") -> DueItem {
        DueItem(class: "Calculus II", id: name.count, name: name, kind: kind, due: due, points: 10, status: "open", label: "To do",
                scoreText: "", late: false, missing: false, excused: false, submitted: nil, url: "")
    }

    func due(week: [DueItem] = [], overdue: [DueItem] = []) -> DueList {
        DueList(synced: "2026-10-16T09:00:00", toHandIn: week.count + overdue.count,
                groups: [DueList.Group(key: "overdue", label: "Missing", items: overdue), DueList.Group(key: "week", label: "This week", items: week)])
    }

    func lede(_ events: [UpcomingEvent]?, _ due: DueList?, notes: Int = 4, unsent: Int = 0) -> String {
        let overview = LibraryOverview(name: "Library", version: "1", classes: [ClassInfo(name: "Calculus II", lectures: notes, color: 0)],
                                       unsorted: 0, writing: 0, ask: true)
        return HomeWords.lede(events: events, due: due, overview: overview, unsent: unsent, className: { $0.class },
                              noun: { $0 == nil ? Nouns.recording : Nouns.lecture }, words: words, now: now)
    }

    @Test func aClassAboutToStartComesFirstThenWhatsDueTonight() {
        #expect(lede([event("Calculus II", "2026-10-16T09:41:00")], due(week: [item("Problem Set 6", "2026-10-16T23:59")]))
            == "Calculus II starts in 11 minutes. Problem Set 6 is due tonight.")
    }

    @Test func workDueOnSundayCountsOnAFridayAndMissingWorkIsSaid() {
        // The desktop's week ends on Saturday; the phone looks seven days ahead, so Sunday's work isn't left out.
        #expect(lede([event("Calculus II", "2026-10-17T09:00:00")],
                     due(week: [item("Problem Set 6", "2026-10-18T23:59")], overdue: [item("Lab Report 3", "2026-10-12T23:59")]))
            == "Problem Set 6 is due Sunday, and Lab Report 3 is still missing. Your next class is Calculus II, tomorrow at 9:00 AM.")
    }

    @Test func twoThingsDueTheSameDayAreCounted() {
        #expect(lede(nil, due(week: [item("Quiz 4", "2026-10-20T10:00", kind: "quiz"), item("Quiz 5", "2026-10-20T23:59", kind: "quiz")]))
            == "Two quizzes due Tuesday.")
    }

    @Test func nothingPressingSaysSoAndWhenTheNextClassIs() {
        #expect(lede([event("Calculus II", "2026-10-17T09:00:00")], due(week: [item("Essay", "2026-10-28T23:59")]))
            == "Nothing due this week. Your next class is Calculus II, tomorrow at 9:00 AM.")
    }

    @Test func aRecordingStuckOnThePhoneIsSaidBeforeWhatsDue() {
        #expect(lede(nil, due(week: [item("Problem Set 6", "2026-10-16T14:00")]), unsent: 1)
            == "A recording on this phone hasn't reached your library. Problem Set 6 is due today at 2:00 PM.")
    }

    @Test func anEmptyLibrarySaysWhereNotesWillBe() {
        #expect(lede(nil, nil, notes: 0) == "Your notes will be here. Record your first class with the Record button below, or on your computer.")
    }

    @Test func upNextKeepsTheRestOfTodayAndTomorrowOnly() {
        let events = [event("Organic Chemistry Lab", "2026-10-18T13:00:00", cls: "Organic Chemistry"),
                      event("Calculus II", "2026-10-17T09:00:00"), event("Done already", "2026-10-16T08:00:00", minutes: 50),
                      event("Intro to Psychology", "2026-10-16T09:00:00", minutes: 75)]
        #expect(HomeWords.coming(events, now: now).map(\.title) == ["Intro to Psychology", "Calculus II"])
    }
}
