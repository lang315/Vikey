import XCTest
import UIKit

/// The keyboard's memory (Tony, 2026-11-18: never past 40 MB). iOS kills a keyboard that goes past its limit (~48 MB)
/// and shows its own keyboard instead, and it keeps one keyboard process for many openings, so memory that an
/// opening leaves behind adds up: in 1.0.4 (64) each opening kept its whole keyboard view (~0.5 MB), 17 MB after one
/// opening, 24 MB after 15, past the limit after ~70. A bundle of its own, so its process holds nothing from other
/// tests.
///
/// The budget: a fresh Vikey keyboard process is ~17 MB in the simulator (`footprint`), iOS's part of it included.
/// The test runner already holds that part (UIKit), so what these tests add on top of the runner must stay under
/// 40 − 17 = 23 MB, which leaves room.
final class KeyboardMemoryTests: XCTestCase {
    static let limitMB = 40.0, freshKeyboardMB = 17.0
    static var budgetMB: Double { limitMB - freshKeyboardMB }

    // ~60 English words and ~60 Vietnamese ones (in Telex), typed as letters and spaces
    static let english = "thank you so much for the update i will take a look at the report tonight and get back to you tomorrow morning about the new design the team really liked it but we should check the numbers again before the meeting on friday please send me the latest version when you can and let me know if anything changes"
    static let vietnamese = "cajm own banj nhieeuf nhes minhf sex gooij laji cho banj vaof toois nay sau khi ddoc xong baos caos cuar nhoms tuaanf sau chungs ta seex hojp veef thieets keees mowis vaf kieemr tra laji soos lieeuj trwowcs khi gwir cho khachs hangf nhows nhawcs anh chij trong nhoms ddeeaf chuaanr bij nhes"

    /// The runner alone, before any test of this bundle touches the keyboard: what the keyboard adds is measured from
    /// it, whichever test built the models and caches first.
    private static var runner: (now: Double, peak: Double)?
    override class func setUp() { super.setUp(); runner = Footprint.read() }

    private let sender = KeyboardView()

    /// A closed keyboard's views go with it: the keys, the strip, the emoji keyboard. iOS keeps the root view of
    /// every opening (the test runner does the same), so what's in it must not stay.
    func testAClosedKeyboardLeavesNothingBehind() {
        weak var keys: KeyboardView?, emojiView: EmojiKeyboardView?, controller: KeyboardViewController?
        var root: UIView?   // held here as iOS holds it: only the controller's cleanup may free what's in it
        autoreleasepool {
            let vc = open()
            root = vc.view
            type("thank you ", language: 0, into: vc)
            emojiView = emoji(vc)
            type("cajm own ", language: 1, into: vc)
            close(vc)
            keys = vc.keyboardViewForTests; controller = vc
        }
        settle()
        withExtendedLifetime(root) {
            XCTAssertNil(controller, "the controller stayed")
            XCTAssertNil(keys, "the keyboard view stayed after its keyboard closed")
            XCTAssertNil(emojiView, "the emoji keyboard stayed after its keyboard closed")
        }
    }

    /// Opening the keyboard again and again (each app, each field) costs nothing that stays.
    func testOpeningAgainAndAgainDoesNotGrow() {
        func round(_ n: Int) {
            autoreleasepool {
                let vc = open()
                type("thank you ", language: 0, into: vc)
                if n % 3 == 0 { _ = emoji(vc) }
                close(vc)
            }
            settle()
        }
        for n in 0..<3 { round(n) }   // the models, the emoji index and the caches: built once
        guard let start = read()?.now else { return }
        for n in 3..<33 { round(n) }
        guard let end = read()?.now else { return }
        let grew = end - start
        print(String(format: "MEMORY 30 more openings: %+.2f MB", grew))
        XCTAssertLessThan(grew, 1.5, String(format: "30 openings kept %.1f MB", grew))
    }

    /// A long session: the keyboard opens and its models load (both languages), English and Vietnamese words are
    /// typed key by key through the touch path (strip, next-letter odds, corrections), the emoji keyboard opens and
    /// searches, and the keyboard closes and opens again. A sampler reads the footprint every 2 ms.
    func testALongSessionStaysUnder40MB() throws {
        let (runner, runnerPeak) = try XCTUnwrap(Self.runner, "couldn't read the runner's footprint")
        let startPeak = try XCTUnwrap(read()).peak
        // A high set since the bundle began is the keyboard's (an earlier test's): past the budget, it fails. One from
        // before it is the runner's own. Either way, a high at or past the budget could hide a session spike between
        // two samples (the high-water mark wouldn't rise), so a runner's high there leaves the test inconclusive.
        if startPeak > runnerPeak {
            XCTAssertLessThan(startPeak - runner, Self.budgetMB, String(format: "the keyboard was already %.1f MB past the runner before the session", startPeak - runner))
        } else if startPeak - runner >= Self.budgetMB {
            throw XCTSkip(String(format: "inconclusive: the runner itself peaked %.1f MB above its footprint before the tests", startPeak - runner))
        }
        let sampler = Sampler()
        sampler.start()
        for _ in 0..<3 {
            autoreleasepool {
                let vc = open()
                type(Self.english, language: 0, into: vc)
                type(Self.vietnamese, language: 1, into: vc)
                _ = emoji(vc)
                type(Self.english, language: 0, into: vc)
                close(vc)
            }
            settle()
        }
        sampler.stop()
        XCTAssertFalse(sampler.failed, "a footprint read failed during the session")
        let end = try XCTUnwrap(read())
        // The process's own high-water mark: when it rose during the session, it's the session's peak, a spike
        // between two samples included. Otherwise the session stayed under an earlier high, and the samples are it.
        let high = end.peak > startPeak ? end.peak : max(sampler.peak, end.now)
        let added = high - runner
        print(String(format: "MEMORY long session: %.1f MB on top of the runner's %.1f MB; as a keyboard ~%.1f MB (limit %.0f)",
                     added, runner, Self.freshKeyboardMB + added, Self.limitMB))
        XCTAssertLessThan(added, Self.budgetMB, String(format: "the keyboard added %.1f MB: ~%.0f MB as a keyboard", added, Self.freshKeyboardMB + added))
    }

    // MARK: the keyboard, as iOS and a person use it

    /// Load, appear, shown; then both languages' models (SuggestLM.warmUp, after appearing).
    private func open() -> KeyboardViewController {
        let vc = KeyboardViewController()
        vc.proxy = MemoryProxy()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.viewDidAppear(false)
        let end = Date().addingTimeInterval(30)
        while !(SuggestLM.readyEN && SuggestLM.readyVI), Date() < end { CFRunLoopRunInMode(.defaultMode, 0.01, true) }
        XCTAssertTrue(SuggestLM.readyEN && SuggestLM.readyVI, "the models didn't load")
        return vc
    }

    private func close(_ vc: KeyboardViewController) {
        vc.viewWillDisappear(false)
        vc.viewDidDisappear(false)
        drain()
    }

    /// Each letter as a touch at its key's centre (KeyboardView.key(at:), a finger's path), the time between keys
    /// given to the main queue (the strip, the next letter's odds), a space after each word.
    private func type(_ text: String, language: Int, into vc: KeyboardViewController) {
        vc.setLanguageForTests(language)
        let kv = vc.keyboardViewForTests
        for ch in text {
            if ch == " " { vc.keyboard(sender, didTap: .space); drain(); continue }
            guard let k = kv.keyRects.first(where: { $0.letter == CChar(ch.asciiValue ?? 0) }) else { continue }
            let at = CGPoint(x: CGFloat(k.x + k.w / 2), y: CGFloat(k.y + k.h / 2))
            guard let kind = kv.key(at: at)?.kind else { continue }
            kv.lastTapPoint = at
            vc.keyboard(sender, didTap: kind)
            drain()
        }
    }

    /// The emoji keyboard: open, search, insert one, back to the letters.
    private func emoji(_ vc: KeyboardViewController) -> EmojiKeyboardView? {
        vc.keyboard(sender, didTap: .emoji)
        drain()
        guard let ev = vc.view.subviews.compactMap({ $0 as? EmojiKeyboardView }).first else { XCTFail("no emoji keyboard"); return nil }
        vc.emojiKeyboardStartSearch(ev)
        for ch in "heart" { vc.keyboard(sender, didTap: .char(String(ch))); drain() }
        vc.emojiKeyboard(ev, insert: "❤️")
        vc.keyboard(sender, didTap: .returnKey)
        vc.emojiKeyboardBack(ev)
        drain()
        return ev
    }

    /// The footprint, or a failed test when iOS doesn't answer (never a zero that would pass).
    private func read() -> (now: Double, peak: Double)? {
        let f = Footprint.read()
        if f == nil { XCTFail("couldn't read the footprint") }
        return f
    }

    private func drain() {
        var drained = false
        DispatchQueue.main.async { drained = true }
        while !drained { CFRunLoopRunInMode(.defaultMode, 0, true) }
    }

    /// What's queued after a close (the nudge's timer, the strip) runs, then the released objects go.
    private func settle() {
        let end = Date().addingTimeInterval(1)
        while Date() < end { CFRunLoopRunInMode(.defaultMode, 0.05, true) }
    }

    /// The highest footprint seen, read every 2 ms on its own queue.
    final class Sampler {
        private let queue = DispatchQueue(label: "memory.sampler")
        private var timer: DispatchSourceTimer?
        private var top = 0.0, failures = 0
        var peak: Double { queue.sync { top } }
        var failed: Bool { queue.sync { failures > 0 } }

        func start() {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(2))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                if let f = Footprint.read() { top = max(top, f.now) } else { failures += 1 }
            }
            t.resume()
            timer = t
        }
        func stop() { timer?.cancel(); timer = nil }
    }
}

/// A text field: what the keyboard inserts and deletes, the text before the cursor.
final class MemoryProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var documentContextBeforeInput: String? { String(text.suffix(400)) }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { !text.isEmpty }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
    func insertText(_ s: String) { text += s }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}
