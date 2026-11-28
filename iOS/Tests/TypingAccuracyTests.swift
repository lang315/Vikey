import XCTest
import UIKit

/// Whole words typed by taps, offline (Tools/suggest README: the simulator version types on Apple's keyboard too):
/// each letter is a tap at its key's centre plus finger scatter (Gaussian, seeded per case), the key it types as a
/// touch there would (KeyboardView.key(at:): the engine's fat-finger pick, or TapModel in English mid-word; a touch
/// can land on space or delete too), the tap recorded for auto-correct, then space. Prints `TYPED\t{"id", "got"}`
/// per case. Runs only with TYPE_CASES set (a file of [id, text before, word] or [id, text before, word, its keys]:
/// Vietnamese words come with their Telex keys); TYPE_MODE=vi types in Vietnamese mode; TYPE_SX / TYPE_SY: scatter in points (9.9, 7.3: σ 0.25 key widths and 0.17 key heights, fitted to the
/// Google TSI and How-We-Type tap data); TYPE_TAPMODEL=0 turns TapModel off.
final class TypingAccuracyTests: XCTestCase {
    override func setUp() { super.setUp(); SuggestLM.warmUpNow() }   // as once the keyboard is up
    struct Gauss: RandomNumberGenerator {   // SplitMix64, so a case's taps are the same on every run
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func normal() -> Double {
            let u1 = max(Double.random(in: 0..<1, using: &self), 1e-12), u2 = Double.random(in: 0..<1, using: &self)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    func testTypedWords() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["TYPE_CASES"] else { throw XCTSkip("TYPE_CASES not set") }
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String]])
        let mode = env["TYPE_MODE"] == "vi" ? 1 : 0
        let sx = Double(env["TYPE_SX"] ?? "") ?? 9.9, sy = Double(env["TYPE_SY"] ?? "") ?? 7.3
        if let m = Double(env["TYPE_MARGIN"] ?? "") { KeyboardViewController.slipMargin = m }
        if env["TYPE_STRICT"] == "0" { KeyboardViewController.slipStrict = false }
        if let m = Double(env["TYPE_MARGIN_WORD"] ?? "") { KeyboardViewController.slipMarginWord = m }
        KeyboardView.tapModelOn = env["TYPE_TAPMODEL"] != "0"
        KeyboardViewController.viTapModelOn = env["TYPE_VITAPMODEL"] != "0"
        // tuning: TYPE_TM_VI="weight,sigmaX,sigmaY,sure,offsetY,toneNow"
        let savedVI = TapModel.vietnamese, savedTone = KeyboardViewController.viToneNow
        defer { TapModel.vietnamese = savedVI; KeyboardViewController.viToneNow = savedTone; KeyboardViewController.viTapModelOn = true }
        if let t = env["TYPE_TM_VI"]?.split(separator: ",").compactMap({ Double($0) }), t.count == 6 {
            TapModel.vietnamese.weight = t[0]; TapModel.vietnamese.sigmaX = t[1]; TapModel.vietnamese.sigmaY = t[2]
            TapModel.vietnamese.sure = t[3]; TapModel.vietnamese.offsetY = t[4]; KeyboardViewController.viToneNow = t[5]
        }
        defer { KeyboardView.tapModelOn = true }
        let sender = KeyboardView()
        var spaceMs: [Double] = []
        for (n, c) in cases.enumerated() {
            let p = CursorProxy()
            p.text = c[1]; p.cursor = c[1].count
            let vc = KeyboardViewController()
            vc.proxy = p
            vc.loadViewIfNeeded()
            vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
            vc.view.layoutIfNeeded()
            vc.viewWillAppear(false)
            vc.setLanguageForTests(mode)
            let kv = vc.keyboardViewForTests
            let rects = kv.keyRects
            var rng = Gauss(state: UInt64(n) &* 7919 &+ 17)
            var prefix = ""
            for ch in (c.count > 3 ? c[3] : c[2]).lowercased() {
                guard let k = rects.first(where: { $0.letter == CChar(ch.asciiValue ?? 0) }) else { continue }
                let x = Float(Double(k.x + k.w / 2) + rng.normal() * sx), y = Float(Double(k.y + k.h / 2) + rng.normal() * sy)
                let at = CGPoint(x: CGFloat(x), y: CGFloat(y))
                guard let kind = kv.key(at: at)?.kind else { continue }   // the globe, the strip: the keyboard drops these touches
                if case .char(let l) = kind { prefix += l } else { prefix += kind == .space ? " " : kind == .backspace ? "<" : "^" }
                kv.lastTapPoint = at
                vc.keyboard(sender, didTap: kind)
                var drained = false   // the time between keys: the strip and the next letter's chances (a touch only looks them up)
                DispatchQueue.main.async { drained = true }
                while !drained { CFRunLoopRunInMode(.defaultMode, 0, true) }
            }
            let t0 = CACurrentMediaTime()
            vc.keyboard(sender, didTap: .space)
            spaceMs.append((CACurrentMediaTime() - t0) * 1000)
            let got = String(p.text.dropFirst(c[1].count))
            let line = try JSONSerialization.data(withJSONObject: ["id": c[0], "got": got, "keys": prefix])
            print("TYPED\t" + String(decoding: line, as: UTF8.self))
        }
        spaceMs.sort()
        if !spaceMs.isEmpty { print(String(format: "TYPED-TIME space (the word's correction): median %.2f ms, p95 %.2f ms, max %.2f ms", spaceMs[spaceMs.count / 2], spaceMs[spaceMs.count * 95 / 100], spaceMs.last!)) }
    }
}
