import XCTest

/// Reads Apple's suggestion bar for every case (Tools/suggest/README.md): the app puts the case's text before
/// the cursor, this test taps the case's letters on the keyboard (key centres, like a perfect typist) and
/// prints the bar as `SUGGEST\t{"id", "cells": [[label, selected]...]}`, cells left to right.
/// Environment (xcodebuild passes TEST_RUNNER_<name>): CASES = the cases file (a host path).
final class AppleRefUITests: XCTestCase {
    func testSuggestionBar() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CASES"] = ProcessInfo.processInfo.environment["CASES"]
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let intro = app.buttons["Continue"]   // the first keyboard's slide-to-type introduction
        if intro.waitForExistence(timeout: 2) { intro.tap() }
        // key centres, once: lowercase letters (a capital is the same key)
        var keys: [Character: CGPoint] = [:]
        for k in app.keyboards.firstMatch.keys.allElementsBoundByIndex where k.label.count == 1 && k.label.first!.isLetter {
            keys[Character(k.label.lowercased())] = CGPoint(x: k.frame.midX, y: k.frame.midY)
        }
        XCTAssertEqual(keys.count, 26, "\(keys.keys.sorted())")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let bar = app.otherElements["Typing Predictions"]
        let label = app.staticTexts["letters"]
        func cells() -> [[Any]] {
            bar.descendants(matching: .other).allElementsBoundByIndex
                .filter { !$0.label.isEmpty && $0.frame.height > 0 }
                .sorted { $0.frame.minX < $1.frame.minX }
                .map { [$0.label, $0.isSelected] }
        }
        func same(_ a: [[Any]], _ b: [[Any]]) -> Bool { a.map { "\($0)" } == b.map { "\($0)" } }
        while true {
            app.buttons["appleref.next"].tap()
            let parts = label.label.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "done" || parts.count < 2 { break }
            let before = cells()
            for ch in parts[1] { if let p = keys[ch] { origin.withOffset(CGVector(dx: p.x, dy: p.y)).tap() } }
            // the bar settles a moment after the last key: wait for a change (when letters were typed), then two equal reads
            var now = cells(), last: [[Any]] = []
            let end = Date().addingTimeInterval(2)
            while Date() < end {
                if !(parts[1].isEmpty == false && same(now, before)) && same(now, last) { break }
                last = now; usleep(120_000); now = cells()
            }
            let line = try JSONSerialization.data(withJSONObject: ["id": parts[0], "cells": now])
            print("SUGGEST\t" + String(decoding: line, as: UTF8.self))
        }
    }

    /// Which key a tap lands on: TAPS = a file of [id, text before, x, y] (points, the app's coordinates). For each,
    /// the app puts the text before the cursor, the test taps (x, y) once and prints what the field gained as
    /// `TAP\t{"id", "got"}` ("" when nothing, "⌫" when the text got shorter).
    func testTapMap() throws {
        guard let path = ProcessInfo.processInfo.environment["TAPS"] else { throw XCTSkip("TAPS not set") }
        let taps = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[Any]])
        let app = XCUIApplication()
        app.launchEnvironment["CASES"] = path   // the same rows: [id, text before, ...]
        app.launch()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)   // a third-party keyboard isn't listed: no assert
        let intro = app.buttons["Continue"]
        if intro.waitForExistence(timeout: 2) { intro.tap() }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let field = app.textViews["text"]
        for t in taps {
            app.buttons["appleref.next"].tap()
            let before = t[1] as! String   // what the app put there
            origin.withOffset(CGVector(dx: t[2] as! Double, dy: t[3] as! Double)).tap()
            let after = (field.value as? String) ?? ""
            let got = after.count < before.count ? "⌫" : String(after.dropFirst(before.count))
            let line = try JSONSerialization.data(withJSONObject: ["id": t[0], "got": got])
            print("TAP\t" + String(decoding: line, as: UTF8.self))
        }
    }

    /// Whole words typed by taps: WORDS = a file of [id, text before, [[x, y], ...]] (the word's taps, then a tap
    /// on space). Prints what the field gained, the keyboard's corrections included: `WORD\t{"id", "got"}`.
    func testWordTaps() throws {
        guard let path = ProcessInfo.processInfo.environment["WORDS"] else { throw XCTSkip("WORDS not set") }
        let words = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[Any]])
        let app = XCUIApplication()
        app.launchEnvironment["CASES"] = path
        app.launch()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)   // a third-party keyboard isn't listed: no assert
        let intro = app.buttons["Continue"]
        if intro.waitForExistence(timeout: 2) { intro.tap() }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let field = app.textViews["text"]
        for w in words {
            app.buttons["appleref.next"].tap()
            // with a third-party keyboard the app can take a moment to show the case's text: wait for it, or the
            // taps land on the previous case's
            let end = Date().addingTimeInterval(3)
            while ((field.value as? String) ?? "") != (w[1] as! String), Date() < end { usleep(100_000) }
            for p in w[2] as! [[Double]] { origin.withOffset(CGVector(dx: p[0], dy: p[1])).tap() }
            let after = (field.value as? String) ?? ""
            let before = w[1] as! String
            let got = after.hasPrefix(before) ? String(after.dropFirst(before.count)) : "?" + after
            let line = try JSONSerialization.data(withJSONObject: ["id": w[0], "got": got])
            print("WORD\t" + String(decoding: line, as: UTF8.self))
        }
    }
}
