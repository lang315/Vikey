import XCTest
import UIKit

/// The English suggestion model (SuggestLM, SuggestEN.bin) and what the bar does with it.
final class SuggestLMTests: XCTestCase {
    override func setUp() { super.setUp(); SuggestLM.warmUpNow() }   // as once the keyboard is up
    private let lm = SuggestLM.shared
    private let sender = KeyboardView()

    func testLoads() {   // a file this code can't read would silently leave the old suggestions
        XCTAssertGreaterThan(lm.wordCount, 50_000)
        XCTAssertNotNil(lm.nn)
    }

    func testNetworkReadsOnAndStartsOver() {
        let nn = lm.nn!
        func top(_ before: String) -> String? {
            guard let p = nn.next(after: before) else { return nil }
            let k = (4..<nn.V).max { p[$0] < p[$1] }!
            return (0..<lm.wordCount).first { nn.networkId($0) == k }.map(lm.form)
        }
        XCTAssertEqual(top("Thank "), "you")
        XCTAssertEqual(top("Thank you so "), "much")   // read on from "Thank "
        XCTAssertEqual(top("Thank you so "), "much")   // the same text: the same answer
        XCTAssertEqual(top("I am going to the "), top("I am going to the "))
        let p = nn.next(after: "See you ")!
        var sum: Float = 0
        for k in 0..<nn.V { sum += p[k] }
        XCTAssertEqual(sum, 1, accuracy: 0.001)
    }

    func testCompletionsFollowTheContext() {
        XCTAssertEqual(lm.completions("peop", before: "For a lot of ", limit: 1), ["people"])
        XCTAssertEqual(lm.completions("o", before: "it depends ", limit: 1), ["on"])
        XCTAssertEqual(lm.completions("o", before: "I'm tired ", limit: 1), ["of"])
    }

    func testDisplayForms() {
        XCTAssertEqual(lm.completions("youtu", before: "on ", limit: 1), ["YouTube"])
        XCTAssertTrue(lm.completions("don", before: "I ", limit: 3).contains("don't"))
    }

    func testNextWords() {
        let next = lm.nextWords(before: "I ", limit: 3).map { $0.lowercased() }
        XCTAssertTrue(next.contains("have") || next.contains("don't"), "\(next)")
        XCTAssertEqual(lm.nextWords(before: "thank ", limit: 1), ["you"])
    }

    func testAWordOnItsWayIsNotATypo() {
        XCTAssertTrue(lm.prefersFinishing("resi", over: "res", before: "I want to "))
        XCTAssertTrue(lm.prefersFinishing("helpi", over: "help", before: "I'm happy "))
        XCTAssertFalse(lm.prefersFinishing("teh", over: "the", before: "I saw "))
    }

    // the bar (Tony's screenshot: "Resi" showed "Res" and "Reis", and space would have made it "Res")
    private func bar(after text: String, typing: String) -> [Suggestion] {
        let p = CursorProxy()
        p.text = text; p.cursor = text.count
        let vc = KeyboardViewController()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(0)
        for ch in typing { vc.keyboard(sender, didTap: .char(String(ch))) }
        vc.updateSuggestions()
        return vc.keyboardViewForTests.suggestions
    }

    func testResiFinishesTheWord() {
        let cells = bar(after: "", typing: "resi")
        XCTAssertEqual(cells.first?.text, "Resi")
        XCTAssertTrue(cells.dropFirst().allSatisfy { $0.text.hasPrefix("Resi") }, "\(cells.map(\.text))")
        XCTAssertFalse(cells.contains { $0.highlighted }, "space keeps what was typed")
    }

    func testCapitalIShows() {   // the system keyboard shows "I" for a typed "i", and space puts it in
        let cells = bar(after: "and then ", typing: "i")
        XCTAssertTrue(cells.contains { $0.text == "I" && $0.highlighted }, "\(cells.map(\.text))")
    }

    func testTypoStillFixed() {
        let cells = bar(after: "I saw ", typing: "teh")
        XCTAssertTrue(cells.contains { $0.text == "the" && $0.highlighted }, "\(cells.map(\.text))")
    }

    // autocorrect reads slips onto neighbouring keys with the sentence (D63)
    private func typeTaps(_ taps: [(letter: Character, toward: Character?, share: CGFloat)], after text: String, mode: Int = 0) -> String {
        let p = CursorProxy()
        p.text = text; p.cursor = text.count
        let vc = KeyboardViewController()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(mode)
        let kv = vc.keyboardViewForTests, rects = kv.keyRects
        func center(_ c: Character) -> CGPoint {
            let k = rects.first { $0.letter == CChar(c.asciiValue!) }!
            return CGPoint(x: CGFloat(k.x + k.w / 2), y: CGFloat(k.y + k.h / 2))
        }
        for t in taps {   // the key typed is `letter`; the tap sits `share` of the way toward `toward`
            var at = center(t.letter)
            if let o = t.toward { let c = center(o); at.x += (c.x - at.x) * t.share; at.y += (c.y - at.y) * t.share }
            kv.lastTapPoint = at
            vc.keyboard(sender, didTap: .char(String(t.letter)))
        }
        vc.keyboard(sender, didTap: .space)
        return String(p.text.dropFirst(text.count))
    }

    func testTwoKeySlipIsFixed() {   // "rhonk", the r and o tapped near t and i: think
        let got = typeTaps([("r", "t", 0.35), ("h", nil, 0), ("o", "i", 0.35), ("n", nil, 0), ("k", nil, 0)], after: "I ")
        XCTAssertEqual(got, "think ")
    }

    func testRealWordsAndShortWordsStay() {   // Decision 26's limits hold for slips too
        XCTAssertEqual(typeTaps([("h", "j", 0.3), ("i", nil, 0), ("t", nil, 0)], after: "It is very "), "hit ")   // a real word
        XCTAssertEqual(typeTaps([("y", "t", 0.4), ("o", nil, 0)], after: "I want "), "yo ")                       // under 3 letters
    }

    // Opening the keyboard doesn't touch the models: reading them then made it slow to come up, and iOS showed its
    // own keyboard instead (Tony, builds 57-59). They're paged in once it's up, and the strip uses them from then on.
    func testModelsWaitUntilTheKeyboardIsUp() {
        SuggestLM.coolDown()
        defer { SuggestLM.warmUpNow() }
        let p = CursorProxy()
        p.text = "I said "; p.cursor = 7
        let vc = KeyboardViewController()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(0)
        for c in "resi" { vc.keyboard(sender, didTap: .char(String(c))) }
        vc.updateSuggestions()   // the engine's strip until then
        XCTAssertFalse(SuggestLM.readyEN || SuggestLM.readyVI)
        vc.viewDidAppear(false)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in SuggestLM.readyEN && SuggestLM.readyVI }, object: nil)
        wait(for: [ready], timeout: 10)
        vc.updateSuggestions()
        let cells = vc.keyboardViewForTests.suggestions.map(\.text)
        XCTAssertTrue(cells.dropFirst().allSatisfy { $0.hasPrefix("resi") } && cells.count == 3, "\(cells)")   // the model's ways to finish it
    }

    func testWarmUpTellsEveryCallerAndForgetsAPassFromBeforeTheKeyboardWentAway() {
        SuggestLM.coolDown()
        defer { SuggestLM.warmUpNow() }
        // a pass the keyboard went away during marks nothing ready
        SuggestLM.warmUp(vietnameseFirst: false) {}
        SuggestLM.coolDown()
        let until = Date().addingTimeInterval(1)
        while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertFalse(SuggestLM.readyEN || SuggestLM.readyVI)
        // a second keyboard joining a pass under way is told too
        var first = 0, second = 0
        SuggestLM.warmUp(vietnameseFirst: true) { first += 1 }
        SuggestLM.warmUp(vietnameseFirst: false) { second += 1 }
        let end = Date().addingTimeInterval(10)
        while !(SuggestLM.readyEN && SuggestLM.readyVI) && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(SuggestLM.readyEN && SuggestLM.readyVI)
        XCTAssertEqual(first, 2); XCTAssertEqual(second, 2)   // once per language
    }

    func testNextLetters() throws {
        let lm = SuggestLM.shared
        let letters = Array("abcdefghijklmnopqrstuvwxyz") + ["·"]
        func top(_ prefix: String, _ before: String) throws -> Character {
            let d = try XCTUnwrap(lm.nextLetters(prefix, before: before))
            XCTAssertEqual(d.count, 27); XCTAssertEqual(d.reduce(0, +), 1, accuracy: 1e-6)
            return letters[d.indices.max { d[$0] < d[$1] }!]
        }
        XCTAssertEqual(try top("yo", "Thank "), "u")
        XCTAssertEqual(try top("q", "I have a "), "u")
        XCTAssertEqual(try top("th", "I said that in "), "e")   // the
        XCTAssertEqual(try top("th", "I want to "), "i")         // think
        let start = try XCTUnwrap(lm.nextLetters("", before: "I want to "))
        XCTAssertGreaterThan(start[1], start[23])   // b (be, buy) over x
        let t0 = CACurrentMediaTime()
        for _ in 0..<20 { _ = lm.nextLetters("", before: "in the ") }
        print("nextLetters at a word start after \"in the \": \((CACurrentMediaTime() - t0) / 20 * 1e6) us")
    }

    func testTelexSpellings() {
        func spell(_ w: String) -> [String] { SuggestLM.telexSpellings(w).map { String(decoding: $0.0, as: UTF8.self) + ($0.1 == 0 ? "" : "+" + String(UnicodeScalar($0.1))) } }
        XCTAssertEqual(spell("người"), ["nguwowi+f", "nguowi+f"])
        XCTAssertEqual(spell("đường"), ["dduwowng+f", "dduowng+f"])
        XCTAssertEqual(spell("ăn"), ["awn"])
        XCTAssertEqual(spell("ấy"), ["aay+s"])
        XCTAssertEqual(spell("Việt"), ["vieet+j"])
        XCTAssertEqual(spell("ok"), ["ok"])
        XCTAssertEqual(spell("e-mail"), [])
    }

    // the next Telex key follows the sentence (D66)
    func testNextKeysFollowTheSentence() throws {
        let vi = SuggestLM.vietnamese
        let keys = Array("abcdefghijklmnopqrstuvwxyz") + ["·"]
        func top(_ typed: String, _ before: String) throws -> Character {
            let d = try XCTUnwrap(vi.nextKeys(typed, before: before))
            XCTAssertEqual(d.reduce(0, +), 1, accuracy: 1e-6)
            return keys[d.indices.max { d[$0] < d[$1] }!]
        }
        XCTAssertEqual(try top("na", "hôm "), "y")      // hôm nay
        XCTAssertEqual(try top("o", "cảm "), "w")       // cảm ơn
        XCTAssertEqual(try top("dduwow", "con "), "n")  // con đường
        XCTAssertEqual(try top("nhieeu", "bao "), "·")  // bao nhiêu: it ends here
        let d = try XCTUnwrap(vi.nextKeys("nhieeu", before: "rất "))   // rất nhiều: the tone comes next
        XCTAssertGreaterThan(d[5], d[26])
        XCTAssertNil(vi.nextKeys("qzx", before: ""))
        XCTAssertNil(vi.nextKeys("bass", before: ""))   // s twice: no tone, no Telex any more
        let ng = try XCTUnwrap(vi.nextKeys("ng", before: "những "))   // no vowel yet: no tone can come next
        for t in "sfrxj" { XCTAssertEqual(ng[Int(t.asciiValue! - 97)], 0, "\(t)") }
        var worst = 0.0, total = 0.0, n = 0
        var before = ""
        for word in ["hoom", "nay", "tooi", "ddi", "hocj", "vaf", "nguwowif", "ta", "noi", "ddeen", "nhieeuf", "chuyeenj"] {
            for i in 1..<word.count {
                let t0 = CACurrentMediaTime()
                _ = vi.nextKeys(String(word.prefix(i)), before: before)
                let t = (CACurrentMediaTime() - t0) * 1e6; worst = max(worst, t); total += t; n += 1
            }
            before += word + " "
        }
        print(String(format: "nextKeys: mean %.0f us, worst %.0f us", total / Double(n), worst))
    }
}
