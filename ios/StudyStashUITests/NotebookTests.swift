import XCTest

/// Writing by hand: a new notebook from Attach, its paper chosen, then changed, and a page added, with real taps on
/// the demo library. The same on an iPhone (Paper and Add a page are in the bar's More) and an iPad (in the bar).
@MainActor
final class NotebookTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNewNotebookThenItsPaperChangedAndAPageAdded() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-quiet"]
        app.launch()
        tap(app.buttons["Attach"], "Home's Attach")
        let write = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Write notes")).firstMatch
        // An iPad opens with its sidebar over Home: the first tap only puts it away.
        if !write.waitForExistence(timeout: 3) { app.buttons["Attach"].tap() }
        tap(write, "Attach's Write notes")

        // Its paper is chosen first, shown as small pages.
        expect(page(app, "newNotebook"), "New notebook")
        tap(app.buttons["paper.grid"], "Grid paper")
        XCTAssertTrue(app.buttons["paper.grid"].isSelected, "Grid chosen")
        tap(app.buttons["notebook.create"], "Create notebook")
        expect(page(app, "notebook"), "the notebook, open over the whole screen")
        expect(text(app, containing: "page 1 of 1"), "page 1 of 1 under the title")

        // This page on Cornell notes.
        if app.buttons["notebook.paper"].waitForExistence(timeout: 2) {
            app.buttons["notebook.paper"].tap()
        } else {
            tap(app.buttons["notebook.more"], "the bar's More")
            tap(app.buttons["Paper"], "More's Paper")
        }
        expect(page(app, "paper"), "the paper picker")
        tap(app.buttons["paper.cornell"], "Cornell notes")
        tap(app.buttons["paper.apply.page"], "Apply to page 1")
        XCTAssertTrue(page(app, "paper").waitForNonExistence(timeout: 4), "the paper picker closes")

        // A page after it, on the same paper.
        if app.buttons["notebook.addPage"].waitForExistence(timeout: 2) {
            app.buttons["notebook.addPage"].tap()
        } else {
            tap(app.buttons["notebook.more"], "the bar's More")
            tap(app.buttons["Add a page after this one"], "More's Add a page after this one")
        }
        expect(text(app, containing: "page 2 of 2"), "page 2 of 2 under the title")

        // The pages, each on Cornell notes.
        tap(app.buttons["notebook.pages"], "Pages")
        expect(element(app, "Page 1, Cornell notes"), "page 1 on Cornell notes in the pages")
        expect(element(app, "Page 2, Cornell notes, showing"), "page 2, showing, on Cornell notes")
    }

    // MARK: helpers

    private func page(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "page.\(name)").firstMatch
    }

    private func text(_ app: XCUIApplication, containing words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", words)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func expect(_ e: XCUIElement, _ what: String, timeout: Double = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Didn't reach \(what)", file: file, line: line)
    }

    private func tap(_ e: XCUIElement, _ what: String, timeout: Double = 8, file: StaticString = #filePath, line: UInt = #line) {
        expect(e, what, timeout: timeout, file: file, line: line)
        e.tap()
    }
}
