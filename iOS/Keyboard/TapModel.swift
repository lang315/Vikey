import UIKit

/// Which key a touch types in English mode while a word is under way, fitted to Apple's keyboard (D65,
/// Tools/suggest/tapfit.py on ~9,300 taps in 48 typing situations, Apple's keyboard in the simulator):
/// each nearby key scores how close the touch is (a Gaussian around the key; a wide key is a letter key with a longer
/// middle) plus how likely it is next (SuggestLM.nextLetters for letters, the word ending for space). Inside the middle
/// 70% of a key, that key wins outright, as on Apple's keyboard. Mid-word Apple agreement 88.5% -> 90.5% on
/// situations it wasn't fitted on (Apple agrees with itself 93.8% tapping the same points twice). Word starts keep
/// the engine's pick: the model did worse there (93.9% -> 92.6%).
enum TapModel {
    struct Params {
        var sigmaX = 0.3, sigmaY = 0.25   // spread, in letter-key widths / key heights
        var weight = 0.6                  // how much the next-letter chances count
        var floor = 0.001, spaceFloor = 0.001, delete = 0.03, shift = 0.001
        var sure = 0.7                    // inside this share of a key (from its centre), it wins outright
        var offsetY = -0.05               // touches count a little higher than they land, in key heights
    }
    static var english = Params()
    /// Vietnamese mode (D66): the next Telex key's chances from the Vietnamese model (SuggestLM.nextKeys); tuned on
    /// our own Vietnamese typing test, not Apple (Tony: Apple's Vietnamese keyboard is no yardstick).
    static var vietnamese = Params(weight: 0.8, sure: 0.5)

    /// The keys the model chooses between; a touch on any other key (123, return, emoji) types that key.
    static func competes(_ k: KeyKind) -> Bool {
        switch k {
        case .char(let c): return c.count == 1 && c.first!.isLetter
        case .space, .backspace, .shift: return true
        default: return false
        }
    }

    /// odds: 27 values (a…z, then the word ending). nil when no key qualifies.
    static func pick(_ p: CGPoint, keys: [(KeyKind, CGRect, KeyCap)], odds: [Double], _ m: Params) -> (cap: KeyCap, kind: KeyKind)? {
        let (sigmaX, sigmaY, weight, floor, spaceFloor, delete, shift, sure, offsetY) =
            (m.sigmaX, m.sigmaY, m.weight, m.floor, m.spaceFloor, m.delete, m.shift, m.sure, m.offsetY)
        let cands = keys.filter { competes($0.0) }
        guard let letterW = cands.first(where: { if case .char = $0.0 { return true }; return false })?.1.width, letterW > 0 else { return nil }
        // inside the middle of a key: that key
        for (k, f, v) in cands {
            let rx = abs(Double(p.x - f.midX)) / Double(f.width / 2), ry = abs(Double(p.y - f.midY)) / Double(f.height / 2)
            if max(rx, ry) <= sure { return (v, k) }
        }
        var best: (Double, KeyKind, KeyCap)?
        for (k, f, v) in cands {
            let halfExtra = Double(max(f.width - letterW, 0) / 2 / letterW)
            let dx = max(abs(Double(p.x - f.midX) / Double(letterW)) - halfExtra, 0) / sigmaX
            let dy = (Double(p.y - f.midY) / Double(f.height) + offsetY) / sigmaY
            let prior: Double
            switch k {
            case .char(let c): let i = Int(c.unicodeScalars.first!.value) - 97; prior = (0..<26).contains(i) ? (1 - floor) * odds[i] + floor / 26 : floor / 26
            case .space: prior = odds[26] + spaceFloor
            case .backspace: prior = delete
            default: prior = shift
            }
            let s = -0.5 * (dx * dx + dy * dy) + weight * log(prior)
            if best == nil || s > best!.0 { best = (s, k, v) }
        }
        return best.map { ($0.2, $0.1) }
    }
}
