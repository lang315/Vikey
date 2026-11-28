import XCTest
import UIKit

/// Performance lock for the keyboard (Tony: "tests that guarantee performance").
/// What made build 2 laggy was cross-process work per key, not the engine, so these tests count it:
/// at most one read of the text field per key, no shared-settings reads while typing, shadows with a
/// fixed path, and a time budget per key.
class CountingProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var reads = 0, deletes = 0, inserts = 0
    var documentContextBeforeInput: String? { reads += 1; return text }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { !text.isEmpty }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
    func insertText(_ t: String) { inserts += 1; text += t }
    func deleteBackward() { deletes += 1; if !text.isEmpty { text.removeLast() } }
}

final class KeyboardPerformanceTests: XCTestCase {
    override func setUp() { super.setUp(); SuggestLM.warmUpNow() }   // as once the keyboard is up
    // mixed Vietnamese/English, typed in Telex, ~2,000 keys
    static let sample = String(repeating: "tooi ddi hocj sorry em i love phowr order traf suwax nhes booking phongf chuaw meeting lucs ba giowf nhes mixx verr ", count: 18)

    private func makeKeyboard() -> (KeyboardViewController, CountingProxy) {
        let vc = KeyboardViewController()
        let p = CountingProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)   // lays the keys out (auto-correct needs them)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(1)
        return (vc, p)
    }

    private let sender = KeyboardView()
    private func type(_ s: String, into vc: KeyboardViewController) {
        for ch in s {
            if ch == " " { vc.keyboard(sender, didTap: .space) }
            else { vc.keyboard(sender, didTap: .char(String(ch))) }
        }
    }

    /// The letter keys of the 402 pt layout (same geometry as KeyboardView).
    static func letterRects() -> [VKKeyRect] {
        let W: Float = 402, side: Float = 6.67, gap: Float = 6, key = (W - 2 * side - 9 * gap) / 10
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"], x0: [Float] = [side, side + (key + gap) / 2, side + (key + gap) * 1.5]
        var r: [VKKeyRect] = []
        for (i, row) in rows.enumerated() {
            for (j, ch) in row.enumerated() {
                r.append(VKKeyRect(letter: CChar(ch.asciiValue!), x: x0[i] + Float(j) * (key + gap), y: Float(i) * 54, w: key, h: 43))
            }
        }
        return r
    }

    func testFatFingerPicksLikelyLetterAtBorder() {
        let keys = Self.letterRects()
        func pick(_ prefix: String, _ vn: Bool, between a: Character, _ b: Character) -> Character {
            let ka = keys.first { $0.letter == CChar(a.asciiValue!) }!, kb = keys.first { $0.letter == CChar(b.asciiValue!) }!
            let x = ((ka.x + ka.w / 2) + (kb.x + kb.w / 2)) / 2, y = ka.y + ka.h / 2
            let c = prefix.withCString { VKPickLetter(x, y, $0, vn ? 1 : 0, keys, Int32(keys.count)) }
            return Character(UnicodeScalar(UInt8(bitPattern: c)))
        }
        XCTAssertEqual(pick("kh", true, between: "o", "p"), "o")      // "kho…", never "khp"
        XCTAssertEqual(pick("th", false, between: "e", "r"), "e")     // "the"
        XCTAssertEqual(pick("ng", true, between: "u", "y"), "u")      // "ngu…"
        // a clear tap in the middle of a key always types that key, however unlikely
        let p = keys.first { $0.letter == CChar(Character("p").asciiValue!) }!
        let c = "kh".withCString { VKPickLetter(p.x + p.w / 2, p.y + p.h / 2, $0, 1, keys, Int32(keys.count)) }
        XCTAssertEqual(Character(UnicodeScalar(UInt8(bitPattern: c))), "p")
    }

    /// English mid-word (D65, TapModel): a touch near a border goes to the letter the sentence makes likely, as on
    /// Apple's keyboard; the middle of a key always types it; Vietnamese mode and word starts keep the engine's pick.
    func testEnglishMidWordTouchFollowsTheSentence() {
        func keyAt(after text: String, typing word: String, mode: Int, between a: Character, _ b: Character, share: CGFloat = 0.5, dy: CGFloat = 0) -> String {
            let p = CursorProxy()
            p.text = text; p.cursor = text.count
            let vc = KeyboardViewController()
            vc.proxy = p
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            vc.view.layoutIfNeeded()
            vc.viewWillAppear(false)
            vc.setLanguageForTests(mode)
            for c in word { vc.keyboard(sender, didTap: .char(String(c))) }
            drainMainQueue()   // the time before the next touch: the strip and the next letter's chances
            let rects = vc.keyboardViewForTests.keyRects
            let ka = rects.first { $0.letter == CChar(a.asciiValue!) }!, kb = rects.first { $0.letter == CChar(b.asciiValue!) }!
            let at = CGPoint(x: CGFloat(ka.x + ka.w / 2) + CGFloat((kb.x + kb.w / 2) - (ka.x + ka.w / 2)) * share, y: CGFloat(ka.y + ka.h / 2) + dy)
            if case .char(let l)? = vc.keyboardViewForTests.key(at: at)?.kind { return l }
            return "?"
        }
        // a third of the way from u to i, low on the key, after "I want to th": the sentence says "think" and Apple types
        // i there (measured); the engine, which sees only "th", typed u
        XCTAssertEqual(keyAt(after: "I want to ", typing: "th", mode: 0, between: "u", "i", share: 0.33, dy: 14), "i")
        KeyboardView.tapModelOn = false
        XCTAssertEqual(keyAt(after: "I want to ", typing: "th", mode: 0, between: "u", "i", share: 0.33, dy: 14), "u")
        KeyboardView.tapModelOn = true
        // the middle of a key types it, however unlikely
        XCTAssertEqual(keyAt(after: "I want to ", typing: "th", mode: 0, between: "u", "i", share: 0), "u")
        // Vietnamese mode: the engine's pick, unchanged
        XCTAssertEqual(keyAt(after: "Thank ", typing: "yo", mode: 1, between: "y", "u", share: 0.45),
                       { KeyboardView.tapModelOn = false; defer { KeyboardView.tapModelOn = true }
                         return keyAt(after: "Thank ", typing: "yo", mode: 1, between: "y", "u", share: 0.45) }())
    }

    /// A touch between the bottom letters and the space bar after a finished word types space (Tony: "thank you" came
    /// out "thanknyou"), in both modes; while the word can go on with that letter, the letter.
    func testSpaceAfterAFinishedWord() {
        func touchBelow(_ letter: Character, after typed: String, mode: Int, tapModel: Bool = true, field: String = "") -> String {
            KeyboardView.tapModelOn = tapModel
            defer { KeyboardView.tapModelOn = true }
            let p = CursorProxy()
            p.text = field; p.cursor = field.count
            let vc = KeyboardViewController()
            vc.proxy = p
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            vc.view.layoutIfNeeded()
            vc.viewWillAppear(false)
            vc.setLanguageForTests(mode)
            for c in typed { vc.keyboard(sender, didTap: .char(String(c))) }
            let k = vc.keyboardViewForTests.keyRects.first { $0.letter == CChar(letter.asciiValue!) }!
            switch vc.keyboardViewForTests.key(at: CGPoint(x: CGFloat(k.x + k.w / 2), y: CGFloat(k.y + k.h) + 3))?.kind {   // 3 pt under the key
            case .space?: return " "
            case .char(let l)?: return l
            default: return "?"
            }
        }
        XCTAssertEqual(touchBelow("n", after: "thank", mode: 0), " ")
        XCTAssertEqual(touchBelow("n", after: "thank", mode: 0, tapModel: false), " ")
        XCTAssertEqual(touchBelow("n", after: "thank", mode: 1), " ")
        XCTAssertEqual(touchBelow("n", after: "tha", mode: 0), "n")    // "than": the word goes on with n
        XCTAssertEqual(touchBelow("n", after: "tha", mode: 1), "n")
        XCTAssertEqual(touchBelow("x", after: "ma", mode: 1), "x")     // Telex: the tone
        // "than" already in the field when the keyboard opened, then k: the whole word counts ("thank")
        XCTAssertEqual(touchBelow("n", after: "k", mode: 0, tapModel: false, field: "than"), " ")
    }

    /// Vietnamese mid-word (D66, TapModel with SuggestLM.nextKeys): halfway between u and i after "th", the sentence
    /// decides: "mùa th" goes on with u (mùa thu), "kỳ th" with i (kỳ thi). The engine alone typed u for both.
    func testVietnameseMidWordTouchFollowsTheSentence() {
        func midUI(after before: String, model: Bool) -> String {
            KeyboardViewController.viTapModelOn = model
            defer { KeyboardViewController.viTapModelOn = true }
            let p = CursorProxy()
            p.text = before; p.cursor = before.count
            let vc = KeyboardViewController()
            vc.proxy = p
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            vc.view.layoutIfNeeded()
            vc.viewWillAppear(false)
            vc.setLanguageForTests(1)
            for c in "th" { vc.keyboard(sender, didTap: .char(String(c))) }
            drainMainQueue()
            let rects = vc.keyboardViewForTests.keyRects
            let u = rects.first { $0.letter == CChar(UInt8(ascii: "u")) }!, i = rects.first { $0.letter == CChar(UInt8(ascii: "i")) }!
            let at = CGPoint(x: CGFloat((u.x + u.w / 2 + i.x + i.w / 2) / 2), y: CGFloat(u.y + u.h / 2))
            if case .char(let l)? = vc.keyboardViewForTests.key(at: at)?.kind { return l }
            return "?"
        }
        XCTAssertEqual(midUI(after: "mùa ", model: true), "u")
        XCTAssertEqual(midUI(after: "kỳ ", model: true), "i")
        XCTAssertEqual(midUI(after: "kỳ ", model: false), "u")
    }

    func testTypesCorrectly() {
        let (vc, p) = makeKeyboard()
        type("tooi ddi hocj sorry em ", into: vc)
        XCTAssertEqual(p.text, "Tôi đi học sorry em ")
    }

    func testAutoCorrectAtSpaceAndBackspaceUndo() {
        let (vc, p) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("i love teh ", into: vc)
        XCTAssertTrue(p.text.hasSuffix("the "), "auto-correct: \(p.text)")
        vc.keyboard(sender, didTap: .backspace)          // right after: put back what was typed
        XCTAssertTrue(p.text.hasSuffix("teh"), "undo: \(p.text)")
        vc.keyboard(sender, didTap: .space)              // and keep it this time
        XCTAssertTrue(p.text.hasSuffix("teh "), "kept: \(p.text)")
    }

    func testContractions() {
        let (vc, p) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("i dont know youre ill. ", into: vc)       // "ill" is a word: stays
        XCTAssertEqual(p.text, "I don't know you're ill. ")
        type("Ill be there, cant", into: vc)              // capital I: "I'll"
        vc.keyboard(sender, didTap: .char("!"))
        XCTAssertTrue(p.text.hasSuffix("I'll be there, can't!"), p.text)
        vc.keyboard(sender, didTap: .backspace)           // right after: undo the fix
        XCTAssertTrue(p.text.hasSuffix("I'll be there, cant"), p.text)
        // Vietnamese mode: a real word stays, an English contraction still gets fixed
        p.text = ""; vc.setLanguageForTests(1)
        type(" im lawngj ", into: vc)
        XCTAssertTrue(p.text.hasSuffix(" im lặng "), p.text)
        type("thats ", into: vc)
        XCTAssertTrue(p.text.hasSuffix("that's "), p.text)
    }

    func testAutoCorrectLeavesRealWordsAndShorthand() {
        let (vc, p) = makeKeyboard()
        // clean mixed typing must come out exactly as typed: no correction of real words / VN shorthand
        type("tooi ddi hocj sorry em ", into: vc)
        XCTAssertEqual(p.text, "Tôi đi học sorry em ")
    }

    private func waitFor(_ done: () -> Bool, timeout: TimeInterval = 5) {
        let end = Date().addingTimeInterval(timeout)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while !done() && Date() < end
    }

    // MARK: opening the keyboard
    // iOS shows its own keyboard instead when Vikey is slow to come up (Tony, builds 57-59: the suggestion models were
    // read while it opened, slow when they weren't in memory). Opening must read none of the bundle's model files,
    // and stay within a time budget.

    /// Every model file in the keyboard's bundle (*.bin), present and future.
    private func modelFiles() -> [URL] {
        var seen = Set<String>(), out: [URL] = []
        for b in [Bundle.main, Bundle(for: SuggestLM.self)] {
            for u in b.urls(forResourcesWithExtension: "bin", subdirectory: nil) ?? [] where seen.insert(u.lastPathComponent).inserted { out.append(u) }
        }
        return out
    }

    /// The share of a file's pages in memory (mincore); `evict` drops them first (msync MS_INVALIDATE).
    private func resident(_ url: URL, evict: Bool = false) -> Double {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return -1 }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0, let m = mmap(nil, Int(st.st_size), PROT_READ, MAP_SHARED, fd, 0), m != MAP_FAILED else { return -1 }
        defer { munmap(m, Int(st.st_size)) }
        if evict { msync(m, Int(st.st_size), MS_INVALIDATE) }
        let page = Int(getpagesize()), pages = (Int(st.st_size) + page - 1) / page
        var vec = [CChar](repeating: 0, count: pages)
        guard mincore(m, Int(st.st_size), &vec) == 0 else { return -1 }
        return Double(vec.filter { $0 & 1 != 0 }.count) / Double(pages)
    }

    /// Opens the keyboard as iOS does, up to just before it shows: load, appear, the field's text, what that queues
    /// on the main thread (in order), and the strip for the text before the cursor.
    private func openKeyboard(text: String) -> KeyboardViewController {
        let vc = KeyboardViewController()
        let p = CountingProxy()
        p.text = text
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.textDidChange(nil)
        var drained = false
        DispatchQueue.main.async { drained = true }   // after everything queued before it
        while !drained { CFRunLoopRunInMode(.defaultMode, 0, true) }
        vc.updateSuggestions()   // next words for the text before the cursor
        return vc
    }

    func testOpeningReadsNoModelFiles() throws {
        let files = modelFiles()
        XCTAssertGreaterThanOrEqual(files.count, 4, "the suggestion models: \(files.map(\.lastPathComponent))")
        SuggestLM.coolDown()
        let savedLanguage = UserDefaults.standard.object(forKey: "Language")
        defer { SuggestLM.warmUpNow(); UserDefaults.standard.set(savedLanguage, forKey: "Language") }
        for lang in [0, 1] {
            for f in files { _ = resident(f, evict: true) }
            let dropped = files.map { resident($0) }
            guard dropped.allSatisfy({ $0 >= 0 && $0 < 0.05 }) else { throw XCTSkip("can't drop the files from memory here: \(dropped)") }
            UserDefaults.standard.set(lang, forKey: "Language")   // the language it opens in (viewDidLoad reads it)
            let vc = openKeyboard(text: lang == 1 ? "Hôm nay tôi đi " : "I said that we ")
            for (f, r) in zip(files, files.map { resident($0) }) {
                XCTAssertLessThan(r, 0.05, "\(f.lastPathComponent): \(Int(r * 100))% read while the keyboard opened (language \(lang))")
            }
            XCTAssertFalse(SuggestLM.readyEN || SuggestLM.readyVI)
            // once it shows, they're paged in off the main thread and the strip uses them
            vc.viewDidAppear(false)
            waitFor({ SuggestLM.readyEN && SuggestLM.readyVI }, timeout: 10)
            XCTAssertTrue(SuggestLM.readyEN && SuggestLM.readyVI, "the models never became ready")
            XCTAssertTrue(files.allSatisfy { resident($0) > 0.9 }, "\(files.map { resident($0) })")
            vc.viewWillDisappear(false)
        }
    }

    func testOpeningTime() {
        for f in modelFiles() { _ = resident(f, evict: true) }
        SuggestLM.coolDown()
        defer { SuggestLM.warmUpNow() }
        _ = openKeyboard(text: "")   // the first opening sets up shared state (layout tables, the engine)
        let ms = bestOf(5) {
            for f in modelFiles() { _ = resident(f, evict: true) }
            let t0 = CACurrentMediaTime()
            let vc = openKeyboard(text: "I said that we ")
            let t = (CACurrentMediaTime() - t0) * 1000
            vc.viewWillDisappear(false)
            return t
        }
        print("opening the keyboard: \(String(format: "%.1f", ms)) ms")
        // debug build: ~6-8 ms now, ~36 ms with build 59's model reads; a busy Mac adds up to ~10 ms. The exact guard
        // is testOpeningReadsNoModelFiles; this one catches any other slow work added to opening.
        XCTAssertLessThan(ms, 30, "opening the keyboard took \(ms) ms (debug build)")
    }

    func testSuggestionStrip() {
        let (vc, _) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("helo", into: vc)
        // the strip updates right after the key (on the next main-queue turn; CI machines can take a while)
        waitFor { !vc.keyboardViewForTests.suggestions.isEmpty }
        let cells = vc.keyboardViewForTests.suggestions.map(\.text)
        XCTAssertEqual(cells.first, "Helo")                         // start of the field: capital
        XCTAssertTrue(cells.contains("Hello"), "suggestions: \(cells)")
        type(" ", into: vc)
        waitFor { !vc.keyboardViewForTests.suggestions.contains { $0.kind == .word } }
        XCTAssertFalse(vc.keyboardViewForTests.suggestions.contains { $0.kind == .word }, "after a space: next words only")
    }

    func testAtMostOneTextReadPerKey() {
        let (vc, p) = makeKeyboard()
        let readsBefore = p.reads
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let perKey = Double(p.reads - readsBefore) / Double(keys)
        XCTAssertLessThanOrEqual(perKey, 1.0, "text field reads per key: \(perKey) (each one is a cross-process call on device)")
    }

    func testNoSettingsReadsWhileTyping() {
        let (vc, _) = makeKeyboard()
        let before = VKSettings.reads
        type(Self.sample, into: vc)
        XCTAssertEqual(VKSettings.reads, before, "shared settings were read while typing")
    }

    func testFewEditsPerKey() {
        let (vc, p) = makeKeyboard()
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let calls = Double(p.deletes + p.inserts) / Double(keys)
        print("keyboard: \(String(format: "%.2f", calls)) text edits per key")
        XCTAssertLessThan(calls, 1.6, "\(calls) delete/insert calls per key: send only the characters that change")
    }

    /// Shared CI machines differ a lot in speed (the same code measured 297 to 2782 µs per key there, and 973 at
    /// best of 5): the best of a few runs drops noise (it only ever adds time), and on CI the limit only catches a
    /// gross slowdown. The real lock is the local limit, run on the dev Mac before every ship.
    private static let onCI = ProcessInfo.processInfo.environment["VIKEY_CI"] != nil
    private static func limit(_ us: Double) -> Double { onCI ? us * 10 : us }
    private func bestOf(_ runs: Int, _ measure: () -> Double) -> Double { (0..<runs).map { _ in measure() }.min()! }

    func testTimePerKey() {
        let keys = Self.sample.count
        let perKeyUs = bestOf(5) {
            let (vc, _) = makeKeyboard()
            let start = CFAbsoluteTimeGetCurrent()
            type(Self.sample, into: vc)
            return (CFAbsoluteTimeGetCurrent() - start) / Double(keys) * 1e6
        }
        print("keyboard: \(Int(perKeyUs)) µs per key (best of 5)")
        XCTAssertLessThan(perKeyUs, Self.limit(300), "keyboard logic takes \(Int(perKeyUs)) µs per key")
    }

    func testSuggestionTimePerKey() {
        // the strip runs after each key's text is sent; it still has to keep up with fast typing
        let us = bestOf(3) {
            let (vc, _) = makeKeyboard()
            var total = 0.0, n = 0
            for ch in Self.sample.prefix(600) {
                if ch == " " { vc.keyboard(sender, didTap: .space) } else { vc.keyboard(sender, didTap: .char(String(ch))) }
                let t = CFAbsoluteTimeGetCurrent(); vc.updateSuggestions(); total += CFAbsoluteTimeGetCurrent() - t; n += 1
            }
            return total / Double(n) * 1e6
        }
        print("keyboard: suggestions \(Int(us)) µs per key (best of 3)")
        XCTAssertLessThan(us, Self.limit(2000), "suggestion strip takes \(Int(us)) µs per key")
    }

    // English mode: the strip ranks with SuggestLM (word counts + the next-word network)
    static let englishSample = String(repeating: "hey are you free tomorrow i was thinking we could grab lunch near the office and talk about the trip next month let me know what works ", count: 4)

    func testTimePerKeyEnglish() {
        let keys = Self.englishSample.count
        let perKeyUs = bestOf(5) {
            let (vc, _) = makeKeyboard(); vc.setLanguageForTests(0)
            let start = CFAbsoluteTimeGetCurrent()
            type(Self.englishSample, into: vc)
            return (CFAbsoluteTimeGetCurrent() - start) / Double(keys) * 1e6
        }
        print("keyboard (English): \(Int(perKeyUs)) µs per key (best of 5)")
        XCTAssertLessThan(perKeyUs, Self.limit(300), "keyboard logic takes \(Int(perKeyUs)) µs per key")
    }

    func testSuggestionTimePerKeyEnglish() {
        var worst = 0.0
        let us = bestOf(3) {
            let (vc, _) = makeKeyboard(); vc.setLanguageForTests(0)
            var total = 0.0, n = 0
            for ch in Self.englishSample {
                if ch == " " { vc.keyboard(sender, didTap: .space) } else { vc.keyboard(sender, didTap: .char(String(ch))) }
                let t = CFAbsoluteTimeGetCurrent(); vc.updateSuggestions(); let d = CFAbsoluteTimeGetCurrent() - t
                total += d; n += 1; worst = max(worst, d)
            }
            return total / Double(n) * 1e6
        }
        print("keyboard (English): suggestions \(Int(us)) µs per key (best of 3), slowest key \(Int(worst * 1e6)) µs")
        XCTAssertLessThan(us, Self.limit(2000), "suggestion strip takes \(Int(us)) µs per key")
    }

    private func drainMainQueue() {
        var drained = false
        DispatchQueue.main.async { drained = true }
        while !drained { CFRunLoopRunInMode(.defaultMode, 0, true) }
    }

    /// English mid-word, a touch goes by TapModel, which needs the next letter's chances (SuggestLM.nextLetters, read
    /// once per keystroke): the touch itself must stay quick.
    func testTouchTimeEnglish() {
        let (vc, _) = makeKeyboard()
        vc.setLanguageForTests(0)
        let kv = vc.keyboardViewForTests
        let rects = kv.keyRects
        func center(_ c: Character) -> CGPoint {
            let k = rects.first { $0.letter == CChar(c.asciiValue!) }!
            return CGPoint(x: CGFloat(k.x + k.w * 0.95), y: CGFloat(k.y + k.h / 2))   // near the right border: the model decides
        }
        var worst = 0.0, total = 0.0, n = 0
        for word in "the meeting is about the schedule for next week and i think we should prepare the slides tomorrow".split(separator: " ") {
            for c in word {
                let reads = KeyboardViewController.oddsReads
                let t0 = CACurrentMediaTime()
                let k = kv.key(at: center(c))
                let t = (CACurrentMediaTime() - t0) * 1e6
                XCTAssertEqual(KeyboardViewController.oddsReads, reads, "the odds for \(word) were read at the touch")
                worst = max(worst, t); total += t; n += 1
                vc.keyboard(sender, didTap: k?.kind ?? .char(String(c)))
                drainMainQueue()   // the time between keys: the strip and the next letter's chances
            }
            vc.keyboard(sender, didTap: .space)
            drainMainQueue()
        }
        print(String(format: "touch (English): mean %.0f us, worst %.0f us", total / Double(n), worst))
        XCTAssertLessThan(total / Double(n), 150, "mean touch time (debug build)")
        XCTAssertLessThan(worst, 1500, "slowest touch (debug build)")
    }

    /// Vietnamese mid-word, a touch goes by TapModel with the next Telex key's chances (SuggestLM.nextKeys, read
    /// between keys): the touch itself must stay quick, and so must the reading.
    func testTouchTimeVietnamese() {
        let (vc, _) = makeKeyboard()   // Vietnamese mode
        let kv = vc.keyboardViewForTests
        let rects = kv.keyRects
        func near(_ c: Character) -> CGPoint {
            let k = rects.first { $0.letter == CChar(c.asciiValue!) }!
            return CGPoint(x: CGFloat(k.x + k.w * 0.95), y: CGFloat(k.y + k.h / 2))
        }
        var worst = 0.0, total = 0.0, n = 0, between = 0.0, times: [Double] = []
        for (w, word) in "hoom nay tooi ddi hocj vaf nguwowif ta noi ddeen nhieeuf chuyeenj cuar cuoocj soongs".split(separator: " ").enumerated() {
            for c in word {
                let reads = KeyboardViewController.oddsReads
                let t0 = CACurrentMediaTime()
                let k = kv.key(at: near(c))
                let t = (CACurrentMediaTime() - t0) * 1e6
                if w > 0 { XCTAssertEqual(KeyboardViewController.oddsReads, reads, "the odds for \(word) were read at the touch") }
                if w > 0 { worst = max(worst, t); total += t; n += 1; times.append(t) }   // the first word sets things up once
                vc.keyboard(sender, didTap: k?.kind ?? .char(String(c)))
                let t1 = CACurrentMediaTime()
                drainMainQueue()
                between = max(between, (CACurrentMediaTime() - t1) * 1e6)
            }
            vc.keyboard(sender, didTap: .space)
            drainMainQueue()
        }
        times.sort()
        print(String(format: "touch (Vietnamese): mean %.0f us, p90 %.0f us, worst %.0f us; strip + next key's chances, worst %.0f us", total / Double(n), times[times.count * 9 / 10], worst, between))
        XCTAssertLessThan(total / Double(n), 150, "mean touch time (debug build)")
        XCTAssertLessThan(worst, 1500, "slowest touch (debug build)")
    }

    /// Two thumbs overlapping: the previous key is finished inside the new touch, before anything runs between keys.
    /// The touch must not read the next letter's chances itself (D65, D66): it keeps the engine's pick.
    func testOverlappingTouchesDontReadTheOdds() {
        for mode in [0, 1] {
            let (vc, _) = makeKeyboard()
            vc.setLanguageForTests(mode)
            let kv = vc.keyboardViewForTests
            let rects = kv.keyRects
            vc.keyboard(sender, didTap: .char("t")); drainMainQueue()
            vc.keyboard(sender, didTap: .char("h"))   // finished inside the next touch: nothing ran in between
            let reads = KeyboardViewController.oddsReads
            let e = rects.first { $0.letter == CChar(UInt8(ascii: "e")) }!
            XCTAssertNotNil(kv.key(at: CGPoint(x: CGFloat(e.x + e.w * 0.95), y: CGFloat(e.y + e.h / 2))))
            XCTAssertEqual(KeyboardViewController.oddsReads, reads, "mode \(mode)")
        }
    }

    func testGapsBetweenKeysReceiveTouches() {
        // iOS drops touches on fully transparent parts of a keyboard: the view must never be clear
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: 265))
        var a: CGFloat = 0
        kb.backgroundColor?.getWhite(nil, alpha: &a)
        XCTAssertGreaterThan(a, 0, "keyboard background is fully transparent: taps between keys are lost")
    }

    func testRenderPopups() {
        // renders key popups (top row and second row) to an image for a visual check
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        let pop1 = KeyPopup(); kb.addSubview(pop1); pop1.show(over: caps[4], in: kb)     // t
        let pop2 = KeyPopup(); kb.addSubview(pop2); pop2.show(over: caps[17], in: kb)    // k
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
        try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/popup_test.png"))
        XCTAssertGreaterThanOrEqual(pop1.frame.minY, 0)
    }

    func testRenderSuggestionStrip() {
        KeyboardView.barOn = true
        for dark in [false, true] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
            kb.dark = dark
            kb.suggestions = [Suggestion(text: "teh", quoted: true), Suggestion(text: "the", highlighted: true), Suggestion(text: "tech")]
            kb.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
            try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/strip_\(dark ? "dark" : "light").png"))
        }
        XCTAssertGreaterThan(KeyboardView.keyboardHeight(compactHeight: false), 250)
    }

    func testKeyShadowsHaveFixedPaths() {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        XCTAssertGreaterThan(caps.count, 30)
        for c in caps { c.layoutIfNeeded(); XCTAssertNotNil(c.layer.shadowPath, "a key shadow without a path is re-rendered offscreen every frame") }
    }
}
