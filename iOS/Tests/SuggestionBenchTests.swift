import XCTest
import UIKit

/// The suggestion benchmark's Vikey side (Tools/suggest/README.md): each case through the real keyboard in English,
/// a fresh keyboard opening on the case's text, its letters tapped, the bar printed as
/// `VIKEY\t{"id", "cells": [[text, highlighted]...]}`. Runs only with CASES set (xcodebuild: TEST_RUNNER_CASES=<file>);
/// MODE=vi types the same English in Vietnamese mode (auto switch on).
final class SuggestionBenchTests: XCTestCase {
    override func setUp() { super.setUp(); SuggestLM.warmUpNow() }   // as once the keyboard is up
    func testSuggestionBar() throws {
        guard let path = ProcessInfo.processInfo.environment["CASES"] else { throw XCTSkip("CASES not set") }
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String]])
        let sender = KeyboardView()
        let mode = ProcessInfo.processInfo.environment["MODE"] == "vi" ? 1 : 0
        var times: [Double] = [], slow: [(Double, String)] = []
        for c in cases {
            let p = CursorProxy()
            p.text = c[1]; p.cursor = c[1].count
            let vc = KeyboardViewController()
            vc.proxy = p
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            vc.view.layoutIfNeeded()
            vc.viewWillAppear(false)
            vc.setLanguageForTests(mode)
            for ch in c[2] { vc.keyboard(sender, didTap: .char(String(ch))) }
            let t0 = CACurrentMediaTime()
            vc.updateSuggestions()
            times.append((CACurrentMediaTime() - t0) * 1000)
            slow.append((times.last!, c[0]))
            let cells = vc.keyboardViewForTests.suggestions.map { [$0.text, $0.highlighted] as [Any] }
            let line = try JSONSerialization.data(withJSONObject: ["id": c[0], "cells": cells, "typed": p.text.dropFirst(c[1].count)])
            print("VIKEY\t" + String(decoding: line, as: UTF8.self))
        }
        print("VIKEY-TIME slowest \(slow.sorted { $0.0 > $1.0 }.prefix(6).map { "\($0.1) \(String(format: "%.0f", $0.0))" })")
        print("VIKEY-TIME first \(times.prefix(5).map { String(format: "%.1f", $0) })")
        times.sort()
        if !times.isEmpty { print(String(format: "VIKEY-TIME median %.2f ms, p95 %.2f ms, max %.2f ms", times[times.count / 2], times[times.count * 95 / 100], times.last!)) }
    }
}
