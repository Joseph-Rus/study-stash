import XCTest

/// Ask with real taps on the demo library, on what could really break for a student: the bar empties when a question
/// is sent (by Send or by Return), Stop stops the answer and keeps what came, a past chat opens from Chats to carry
/// on, and Undo brings back a deleted one. (A source opening its lecture at the moment is in JourneyTests.)
/// `-ask-pace slow` writes the demo's answer a word at a time, so there's time to stop it.
@MainActor
final class AskTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testTheBarEmptiesWhenSentAndStopStops() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-quiet", "-ask-new", "-ask-pace", "slow"]
        app.launch()
        tap(app.tabBars.buttons["Ask"], "the Ask tab")

        let field = app.descendants(matching: .any).matching(identifier: "ask.field").firstMatch
        tap(field, "the Ask bar")
        field.typeText("How do I choose u?")
        tap(app.buttons["ask.send"], "Send")
        expect(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "You asked: How do I choose u?")).firstMatch,
               "the question in the thread")
        XCTAssertFalse(text(of: field).contains("choose u"), "the bar is empty once it's sent (it said \(text(of: field)))")

        // While it's written, Send is Stop; stopped, what came stays and says so, and Send is back.
        tap(app.buttons["ask.stop"], "Stop", timeout: 10)
        expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Stopped")).firstMatch, "the answer said to be stopped")
        expect(app.buttons["ask.send"], "Send again after Stop")
        XCTAssertFalse(app.buttons["ask.stop"].exists, "no Stop once it's stopped")

        // Return sends too, and empties the bar the same way.
        tap(field, "the Ask bar")
        field.typeText("Quiz me on it\n")
        expect(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "You asked: Quiz me on it")).firstMatch,
               "the follow-up sent by Return")
        XCTAssertFalse(text(of: field).contains("Quiz me"), "the bar is empty after Return (it said \(text(of: field)))")
    }

    /// A past chat opens from Chats; New chat empties the page; a chat deleted with a swipe comes back with Undo.
    func testAPastChatOpensFromChatsAndNewChatStartsAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-quiet", "-ask-new"]
        app.launch()
        tap(app.tabBars.buttons["Ask"], "the Ask tab")
        tap(app.buttons["ask.chats"], "Chats")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "What's the difference between SN1 and SN2?")).firstMatch,
            "a past chat in Chats")
        expect(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "You asked: What's the difference between SN1 and SN2?")).firstMatch,
               "the chat's question in the thread")
        expect(app.buttons["ask.source"].firstMatch, "its answer's source")
        tap(app.buttons["ask.new"], "New chat")
        expect(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "What do you want to know")).firstMatch,
               "the empty page after New chat")

        tap(app.buttons["ask.chats"], "Chats again")
        let memory = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Which lectures talk about memory?")).firstMatch
        expect(memory, "a chat to delete")
        memory.swipeLeft()
        tap(app.buttons["Delete"], "the swipe's Delete")
        XCTAssertTrue(memory.waitForNonExistence(timeout: 5), "the chat out of the list")
        tap(app.buttons["chats.undo"], "Undo")
        expect(memory, "the chat back after Undo")
    }

    /// What's in a text field (its placeholder when it's empty).
    private func text(of field: XCUIElement) -> String { field.value as? String ?? "" }

    private func expect(_ e: XCUIElement, _ what: String, timeout: Double = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Didn't reach \(what)", file: file, line: line)
    }

    private func tap(_ e: XCUIElement, _ what: String, timeout: Double = 8, file: StaticString = #filePath, line: UInt = #line) {
        expect(e, what, timeout: timeout, file: file, line: line)
        e.tap()
    }
}
