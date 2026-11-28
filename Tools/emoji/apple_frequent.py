#!/usr/bin/env python3
"""The expected lists in iOS/Tests/EmojiUsageTests.swift (D68): feeds the same picks to Apple's own Frequently Used code
(EmojiFoundation's EMFEmojiPreferences, in a booted iOS simulator) and prints its list for each test.
The picks come from the same generator as the tests (`picks(seed:_:_:skewed:)`).
Run: python3 Tools/emoji/apple_frequent.py [simulator id]   (default: the first booted simulator)"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = ("😂 ❤️ 😍 🥰 😭 👍 🙏 😊 🔥 😘 🤣 🥺 😅 🎉 💕 😁 🙂 😉 🤔 👏 😎 💪 ✨ 😢 🙌 💯 😆 🤗 😴 👌 💖 🐎 🍜 ☕ 🌸 🎂 😡 🤦 🙄 😳 "
        "🐶 🍕 🎁 💔 😤 🤩 😇 🥲 🫶 👀 💀 🌚 🤡 💩 🌈 ⚽ 🚗 📷 🎶 🍀").split()

def picks(seed, n, lo, hi, skewed=True):
    x, out = seed, []
    def nxt():
        nonlocal x
        x = (x * 6364136223846793005 + 1442695040888963407) % 2**64
        return (x >> 33) % (hi - lo)
    for _ in range(n):
        i = nxt()
        if skewed: i = min(i, nxt())
        out.append(POOL[lo + i])
    return out

TESTS = {
    "testSameListAsApple": picks(1, 900, 0, 40),
    "testSameListAsAppleWithManyEmoji": picks(2, 900, 0, 60, skewed=False),
    "testSameListAsAppleWhenFavoritesChange": picks(3, 400, 0, 30) + picks(4, 300, 30, 60),
    "testSameListAsAppleAfterThousandsOfPicks": picks(5, 1200, 0, 30) + picks(6, 1300, 20, 60),
}

def main():
    sim = sys.argv[1] if len(sys.argv) > 1 else next(
        l.split("(")[1].split(")")[0] for l in subprocess.run(["xcrun", "simctl", "list", "devices", "booted"],
                                                               capture_output=True, text=True).stdout.splitlines() if "(Booted)" in l)
    with tempfile.TemporaryDirectory() as tmp:
        exe = os.path.join(tmp, "apple_frequent")
        subprocess.run(["xcrun", "-sdk", "iphonesimulator", "clang", "-arch", "arm64", "-mios-simulator-version-min=17.0",
                        "-fobjc-arc", "-framework", "Foundation", os.path.join(HERE, "apple_frequent.m"), "-o", exe], check=True)
        for name, seq in TESTS.items():
            f = os.path.join(tmp, name + ".txt")
            with open(f, "w", encoding="utf-8") as fh:
                fh.write("\n".join(seq) + "\n")
            # Apple's reset keeps the pick number, so start from no saved state at all
            subprocess.run(["xcrun", "simctl", "spawn", sim, "defaults", "delete", "com.apple.EmojiPreferences"], capture_output=True)
            out = subprocess.run(["xcrun", "simctl", "spawn", sim, exe, f, "30", "prune"], capture_output=True, text=True).stdout
            shown = out.splitlines()[0].split(": ", 1)[1]
            print(name, shown.replace("\u2615\ufe0f", "\u2615").replace("\u26bd\ufe0f", "\u26bd"))   # Apple adds U+FE0F to ☕ and ⚽

if __name__ == "__main__":
    main()
