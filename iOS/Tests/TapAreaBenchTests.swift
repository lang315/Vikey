import XCTest
import UIKit

/// Which key a touch types, Vikey against Apple (Tools/suggest/tapsample.py + AppleRefUITests.testTapMap on Apple's
/// keyboard). Runs only with TAP_POINTS (the points: [id, text before the cursor, x, y] in the AppleRef window) and
/// TAP_APPLE (Apple's run: TAP lines). Prints `TAPAREA\t{"id", "vikey", "apple"}` per point, then the share where
/// they agree, per context and in all.
///
/// The text before the word goes in as the field's text; a word half typed ("I want to th") is typed key by key, as
/// a person would have. Vikey's keys line up with Apple's on screen (the same rows, iOS 26), so a window point maps to
/// the keyboard by one vertical shift: Vikey's top letter row centred at window y 612 reproduces the live keyboard
/// (testTapMap with Vikey on) at 99.2% of points.
final class TapAreaBenchTests: XCTestCase {
    private let sender = KeyboardView()

    func testTapAreasAgainstApple() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pointsPath = env["TAP_POINTS"], let applePath = env["TAP_APPLE"] else { throw XCTSkip("TAP_POINTS / TAP_APPLE not set") }
        SuggestLM.warmUpNow()
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: pointsPath))) as? [[Any]])
        var apple: [String: String] = [:]
        for path in applePath.split(separator: ",") {
            for line in try String(contentsOfFile: String(path), encoding: .utf8).split(separator: "\n") where line.hasPrefix("TAP\t") {
                guard let j = try JSONSerialization.jsonObject(with: Data(line.dropFirst(4).utf8)) as? [String: String],
                      let id = j["id"], let got = j["got"] else { continue }
                apple[id] = got == "⌫" ? "⌫" : String(got.prefix(1)).lowercased()   // its field also takes an inline prediction
            }
        }
        var byContext: [String: [(id: String, x: CGFloat, y: CGFloat)]] = [:], order: [String] = []
        for r in rows {
            guard let id = r[0] as? String, let text = r[1] as? String, let x = r[2] as? Double, let y = r[3] as? Double else { continue }
            if byContext[text] == nil { order.append(text) }
            byContext[text, default: []].append((id, CGFloat(x), CGFloat(y)))
        }
        var same = 0, all = 0
        for text in order {
            let (vc, kv) = keyboard(after: text)
            let q = try XCTUnwrap(kv.keyRects.first { $0.letter == CChar(UInt8(ascii: "q")) })
            let shift = 612 - CGFloat(q.y + q.h / 2) + CGFloat(Double(env["TAP_DY"] ?? "") ?? 0)
            // for fitting a model offline (Tools/suggest/tapfit.py): the keys in window points, and the next letter's
            // chances from the English model
            let word = String(text.reversed().prefix { $0.isLetter }.reversed())
            let dist = SuggestLM.shared.nextLetters(word.lowercased(), before: String(text.dropLast(word.count))) ?? []
            let frames = kv.capFramesForTests.map { f -> [String: Any] in
                ["k": Self.name(f.kind) == "" ? "\(f.kind)" : Self.name(f.kind), "x": f.frame.minX, "y": f.frame.minY + shift, "w": f.frame.width, "h": f.frame.height]
            }
            let ctxLine = try JSONSerialization.data(withJSONObject: ["text": text, "word": word, "dist": dist, "keys": frames])
            print("TAPCTXDATA\t" + String(decoding: ctxLine, as: UTF8.self))
            var s = 0, n = 0
            for p in byContext[text]! {
                guard let a = apple[p.id] else { continue }
                let v = Self.name(kv.key(at: CGPoint(x: p.x, y: p.y - shift))?.kind)
                let line = try JSONSerialization.data(withJSONObject: ["id": p.id, "text": text, "x": p.x, "y": p.y, "vikey": v, "apple": a])
                print("TAPAREA\t" + String(decoding: line, as: UTF8.self))
                n += 1; if v == a { s += 1 }
            }
            _ = vc
            print(String(format: "TAPCTX\t%@\t%d\t%.1f", text, n, n > 0 ? 100 * Double(s) / Double(n) : 0))
            same += s; all += n
        }
        print(String(format: "TAPALL\t%d\t%.1f", all, all > 0 ? 100 * Double(same) / Double(all) : 0))
    }

    /// The letters layer in English after `text`: the text up to the word goes in as the field's, the word's letters are typed.
    private func keyboard(after text: String) -> (KeyboardViewController, KeyboardView) {
        let word = String(text.reversed().prefix { $0.isLetter }.reversed())
        let p = CursorProxy()
        p.text = String(text.dropLast(word.count)); p.cursor = p.text.count
        let vc = KeyboardViewController()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false))
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(0)
        vc.textDidChange(nil)
        for c in word { vc.keyboard(sender, didTap: .char(String(c).lowercased())) }
        var drained = false   // the time between keys: the next letter's chances are read then (a touch only looks them up)
        DispatchQueue.main.async { drained = true }
        while !drained { CFRunLoopRunInMode(.defaultMode, 0, true) }
        vc.view.layoutIfNeeded()
        return (vc, vc.keyboardViewForTests)
    }

    private static func name(_ k: KeyKind?) -> String {
        switch k {
        case .char(let c)?: return c.lowercased()
        case .backspace?: return "⌫"
        case .space?: return " "
        default: return ""   // shift, nothing: Apple's field gains nothing either
        }
    }
}
