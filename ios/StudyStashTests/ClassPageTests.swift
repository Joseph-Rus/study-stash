import Foundation
import Testing
@testable import StudyStash

// What a class's page says about when it meets and what's due: the words a student reads to plan the week.

@Suite struct ClassPageWordsTests {
    /// Friday 16 October 2026, 8:00 AM here.
    let now = Format.parse("2026-10-16T08:00:00")!

    func event(_ title: String, _ start: String, minutes: Double = 50, place: String? = nil) -> UpcomingEvent {
        let s = Format.parse(start)!
        let iso = ISO8601DateFormatter()
        return UpcomingEvent(id: start, title: title, start: iso.string(from: s), end: iso.string(from: s.addingTimeInterval(minutes * 60)),
                             allDay: false, location: place, class: "Calculus II")
    }

    @Test func aClassMeetsOnItsWeekdaysMondayFirstAtItsOneTime() {
        let week = [event("Calculus II", "2026-10-16T09:30:00"), event("Calculus II", "2026-10-19T09:30:00"),
                    event("Calculus II", "2026-10-21T09:30:00")]
        #expect(ClassWords.meets(name: "Calculus II", events: week, asClass: true, now: now)
            == "Meets Monday, Wednesday and Friday at 9:30 AM")
        #expect(ClassWords.lede(name: "Calculus II", group: "", code: "MATH 162", noun: "lecture", count: 4, events: week, now: now)
            == "MATH 162 on Canvas. Meets Monday, Wednesday and Friday at 9:30 AM.")
    }

    @Test func aLabWithANameOfItsOwnDoesntCountBesideTheRegularMeetings() {
        let week = [event("Calculus II", "2026-10-19T09:30:00"), event("Calculus II Exam Review", "2026-10-20T18:00:00")]
        #expect(ClassWords.meets(name: "Calculus II", events: week, asClass: true, now: now) == "Meets Monday at 9:30 AM")
    }

    @Test func differentTimesLeaveTheTimeOut() {
        let week = [event("Calculus II", "2026-10-19T09:30:00"), event("Calculus II", "2026-10-21T13:00:00")]
        #expect(ClassWords.meets(name: "Calculus II", events: week, asClass: true, now: now) == "Meets Monday and Wednesday")
    }

    @Test func aClubSaysItsMeetingsAndWithNoCalendarItsCount() {
        let week = [event("ACM", "2026-10-22T18:00:00")]
        #expect(ClassWords.lede(name: "ACM", group: "Clubs", code: "", noun: "meeting", count: 5, events: week, now: now)
            == "Club meetings, Thursdays at 6:00 PM.")
        #expect(ClassWords.lede(name: "ACM", group: "Clubs", code: "", noun: "meeting", count: 5, events: [], now: now)
            == "5 meetings so far.")
        #expect(ClassWords.lede(name: "ACM", group: "Clubs", code: "", noun: "meeting", count: 0, events: [], now: now)
            == "No meetings yet.")
    }

    @Test func theNextClassSaysWhenWhereAndWhetherItsOnNow() {
        let tomorrow = [event("Calculus II", "2026-10-17T09:00:00", place: "Science Hall 204")]
        #expect(ClassWords.next(tomorrow, name: "Calculus II", now: now)?.words == "Tomorrow at 9:00 AM in Science Hall 204")
        let lab = [event("Calculus II Lab", "2026-10-20T13:00:00")]
        #expect(ClassWords.next(lab, name: "Calculus II", now: now)?.words == "Tuesday at 1:00 PM, Calculus II Lab")
        let on = [event("Calculus II", "2026-10-16T07:30:00", minutes: 50)]
        #expect(ClassWords.next(on, name: "Calculus II", now: now)?.words == "On now, until 8:20 AM")
        #expect(ClassWords.next(on, name: "Calculus II", now: now)?.on == true)
        #expect(ClassWords.next([], name: "Calculus II", now: now) == nil)
    }

    @Test func dueIsMissingFirstThenSoonestOnlyThisClassThreeAtMost() {
        func item(_ id: Int, _ cls: String, _ due: String, missing: Bool = false) -> DueItem {
            DueItem(class: cls, id: id, name: "A\(id)", kind: "assignment", due: due, points: nil, status: "open", label: "To do",
                    scoreText: "", late: missing, missing: missing, excused: false, submitted: nil, url: "")
        }
        let list = DueList(synced: nil, toHandIn: 5, groups: [
            .init(key: "overdue", label: "Missing", items: [item(1, "Calculus II", "2026-10-12T23:59", missing: true)]),
            .init(key: "week", label: "This week", items: [item(3, "Calculus II", "2026-10-21T23:59"), item(2, "Calculus II", "2026-10-18T23:59"),
                                                            item(9, "Organic Chemistry", "2026-10-17T23:59")]),
            .init(key: "later", label: "Later", items: [item(4, "Calculus II", "2026-11-20T23:59")]),
            .init(key: "handed_in", label: "Handed in", items: [item(5, "Calculus II", "2026-10-17T23:59")]),
        ])
        let rows = ClassWords.due(list, in: "Calculus II", now: now)
        #expect(rows.map(\.item.id) == [1, 2, 3])
        #expect(rows.map(\.when) == ["Was due Mon 12 Oct", "Sun 18 Oct, in 2 days", "Wed 21 Oct, in 5 days"])
        #expect(rows.map(\.late) == [true, false, false])
        #expect(rows.map(\.soon) == [false, true, true])
    }
}
