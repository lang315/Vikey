import XCTest
import UIKit

/// Frequently Used (D68): Apple's rule, checked against Apple's own code, and kept where a keyboard without Full Access
/// can write.
final class EmojiUsageTests: XCTestCase {
    private var d: UserDefaults!
    override func setUp() { super.setUp(); d = UserDefaults(suiteName: "emoji-usage-test-\(UUID().uuidString)")! }

    private static let pool = "😂 ❤️ 😍 🥰 😭 👍 🙏 😊 🔥 😘 🤣 🥺 😅 🎉 💕 😁 🙂 😉 🤔 👏 😎 💪 ✨ 😢 🙌 💯 😆 🤗 😴 👌 💖 🐎 🍜 ☕ 🌸 🎂 😡 🤦 🙄 😳 🐶 🍕 🎁 💔 😤 🤩 😇 🥲 🫶 👀 💀 🌚 🤡 💩 🌈 ⚽ 🚗 📷 🎶 🍀"
        .split(separator: " ").map(String.init)

    /// Picks from `pool[range]`, the same as the script that fed Apple's code. Skewed: the min of two draws, so the
    /// first emoji of the range come up most, as favorites do.
    private func picks(seed: UInt64, _ n: Int, _ range: Range<Int>, skewed: Bool = true) -> [String] {
        var x = seed
        func next() -> Int { x = x &* 6364136223846793005 &+ 1442695040888963407; return Int((x >> 33) % UInt64(range.count)) }
        return (0..<n).map { _ in
            var i = next()
            if skewed { i = min(i, next()) }
            return Self.pool[range.lowerBound + i]
        }
    }

    private func list(after seq: [String], count n: Int) -> String {
        for e in seq { EmojiUsage.record(e, in: d) }
        return EmojiUsage.frequent(in: d, count: n).joined(separator: " ")
    }

    // The expected lists are what Apple's EmojiFoundation (iOS 26.5 simulator, EMFEmojiPreferences didUseEmoji: then
    // recentEmojis) gave for the same picks; Tools/emoji/apple_frequent.py prints them again. Apple spells ☕ and ⚽ with
    // U+FE0F; that is left out here.

    func testSameListAsApple() {
        XCTAssertEqual(list(after: picks(seed: 1, 900, 0..<40), count: 30),
                       "🙏 🤣 😘 😍 😭 😉 🥰 🤔 🥺 👍 🎉 🤗 😊 💪 ✨ 👏 😎 🙂 😅 😂 😆 🎂 😁 🔥 😢 💯 😴 ❤️ 💕 ☕")
    }

    func testSameListAsAppleWithManyEmoji() {
        XCTAssertEqual(list(after: picks(seed: 2, 900, 0..<60, skewed: false), count: 30),
                       "👏 😆 🔥 🌈 💪 🎁 😅 ❤️ 🫶 🙏 🤔 🙂 💀 😇 🚗 💩 😳 😭 🤗 😂 💯 😴 🌚 ⚽ 😁 😤 🥺 ☕ ✨ 💕")
    }

    /// New favorites: the old ones stay at the end for a while; the list grows past 30 (only 30 show), like Apple's.
    func testSameListAsAppleWhenFavoritesChange() {
        XCTAssertEqual(list(after: picks(seed: 3, 400, 0..<30) + picks(seed: 4, 300, 30..<60), count: 33),
                       "🍜 💖 ☕ 😡 🐶 😳 🌸 🎁 🫶 🎂 💔 😇 🐎 🥲 🤩 🍕 🌈 🙄 🤡 ⚽ 👀 🤦 🌚 😤 💀 📷 🚗 🍀 😍 🎉 🤣 🥺 🥰")
    }

    /// 2,500 picks: past 1,000 only the last 500 count. Without that, Apple's list would differ (50 entries, not 49).
    func testSameListAsAppleAfterThousandsOfPicks() {
        XCTAssertEqual(list(after: picks(seed: 5, 1200, 0..<30) + picks(seed: 6, 1300, 20..<60), count: 49),
                       "😢 💪 ✨ 🌸 ☕ 🫶 🍜 😎 💯 🤩 👌 🤦 💖 😆 💔 🙌 🌚 😡 🐶 😇 🎁 🐎 🤗 😳 😴 🎂 🙄 🌈 🥲 🍕 👀 🤡 💀 🎶 😤 ⚽ 💩 📷 🚗 ❤️ 🥰 🔥 😭 😂 🙂 😍 👍 😊 💕")
    }

    /// Old picks fade slower than before: 30 × 💖, 60 × 😂, then 4 × 🐎 keeps 💖 above 🐎 (the old scores put 🐎 first).
    func testAFavoriteStaysUp() {
        let seq = Array(repeating: "💖", count: 30) + Array(repeating: "😂", count: 60) + Array(repeating: "🐎", count: 4)
        XCTAssertEqual(list(after: seq, count: 3), "😂 💖 🐎")
    }

    func testEmptyFillsWithStarters() {
        XCTAssertEqual(EmojiUsage.frequent(in: d, count: 30), EmojiUsage.starter)
        EmojiUsage.record("💖", in: d)
        XCTAssertEqual(EmojiUsage.frequent(in: d, count: 3), ["💖", "😂", "❤️"])
    }

    /// Picks saved with the old fading scores carry over in the same order, once.
    func testOldScoresCarryOver() {
        let old = UserDefaults(suiteName: "emoji-usage-old-\(UUID().uuidString)")!
        old.set(["💖": 9.4, "😂": 3.1, "🐎": 0.6], forKey: EmojiUsage.legacyKey)
        EmojiUsage.migrate(from: old, to: d)
        XCTAssertEqual(EmojiUsage.frequent(in: d, count: 3), ["💖", "😂", "🐎"])
        EmojiUsage.record("🍜", in: d)
        EmojiUsage.migrate(from: old, to: d)   // already moved: nothing happens
        XCTAssertEqual(EmojiUsage.frequent(in: d, count: 4), ["💖", "😂", "🍜", "🐎"])
    }

    /// The keyboard keeps picks and the skin tone in its own defaults, never in the app group: without Full Access the
    /// app group is read-only for a keyboard, and what it wrote there was gone when iOS restarted it.
    func testKeyboardSavesPicksInItsOwnDefaults() throws {
        let saved = EmojiKeyboardView.usage
        EmojiKeyboardView.usage = d
        defer { EmojiKeyboardView.usage = saved }
        let group = VKSettings.defaults
        let legacyBefore = group.object(forKey: EmojiUsage.legacyKey)   // old scores here would move over first
        group.removeObject(forKey: EmojiUsage.legacyKey)
        addTeardownBlock { group.set(legacyBefore, forKey: EmojiUsage.legacyKey) }
        let groupBefore = group.object(forKey: EmojiUsage.key) as? NSDictionary

        let vc = KeyboardViewController()
        vc.proxy = CursorProxy()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false))
        vc.viewWillAppear(false)
        vc.keyboard(KeyboardView(), didTap: .emoji)
        let ev = try XCTUnwrap(vc.view.subviews.compactMap { $0 as? EmojiKeyboardView }.first)
        let grid = try XCTUnwrap(ev.subviews.compactMap { $0 as? UICollectionView }.first)
        ev.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 1))   // the first smiley

        XCTAssertEqual(EmojiUsage.frequent(in: d, count: 1), ["😀"])
        XCTAssertEqual(group.object(forKey: EmojiUsage.key) as? NSDictionary, groupBefore, "nothing written to the app group")

        // the next keyboard (iOS restarted it) shows the pick first
        let next = EmojiKeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        next.load()
        let nextGrid = try XCTUnwrap(next.subviews.compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(next.collectionView(nextGrid, numberOfItemsInSection: 0), 30)
        let cell = try XCTUnwrap(next.collectionView(nextGrid, cellForItemAt: IndexPath(item: 0, section: 0)) as? EmojiCell)
        XCTAssertEqual(cell.label.text, "😀")
    }
}
