# Suggestion bar benchmark (English)

How close Vikey's suggestion bar is to the iOS system keyboard's, on the same text.

A case is a place in a real sentence: the text before the cursor, and what is typed there.
- `part`: a word cut after 1..len-1 of its letters, so every keystroke is equally likely.
- `full`: the whole word, before its space.
- `next`: nothing typed after a space. These are next-word predictions.

Both keyboards are typed on the same way: the text before the cursor is set by the app (so neither keyboard learns from it), then the case's letters are tapped at key centres.

- **Apple:** `AppleRef/` is an app plus a UI test, run on a simulator with only the English (US) keyboard. The test reads the bar through accessibility, cells left to right, with the auto-correct cell marked.
- **Vikey:** `iOS/Tests/SuggestionBenchTests.swift` runs the real `KeyboardViewController` in English. It skips unless `CASES` is set.

## Run

```sh
# cases from text (one text per line); dev to tune on, test to report on. Also writes apple_in_{dev,test}.json,
# the cases cut to [id, text, letters], which both runners read
Tools/suggest/make_cases.py OUT_DIR text1.txt text2.txt --per-split 1000
# Apple: a simulator set to the English (US) keyboard only (AppleKeyboards, AppleLocale, AppleLanguages)
Tools/suggest/apple_run.sh <sim udid> OUT_DIR/apple_in_dev.json OUT_DIR/apple_dev.jsonl
# Vikey
Tools/suggest/vikey_run.sh <sim udid> OUT_DIR/apple_in_dev.json OUT_DIR/vikey_dev.jsonl
Tools/suggest/score.py OUT_DIR/cases_dev.json OUT_DIR/apple_dev.jsonl OUT_DIR/vikey_dev.jsonl --show 30
```

Each run takes about 2.7 s per case on Apple's side (key taps through XCUITest) and a few seconds in all on Vikey's.

## The model

`iOS/Keyboard/SuggestLM.swift` ranks words. It blends two models, half each (`networkShare`):
- **Word counts** (`SuggestEN.bin`, built by `pack_lm.py`): Katz back-off over triples, pairs and single words.
- **A small LSTM** (`SuggestNN.bin`, built by `pack_nn.py`, run by `SuggestNN.swift`) that reads up to 32 tokens back.

Both come from vikey-data `lm_en/`: `fetch_lm.py` and `merge.py` make the counts, `dump_tokens.py` and `train_nn.py` the network, and `eval_nn.py` scores the blend in Python against Apple's bar.

Rebuild after retraining:

```sh
python3 Tools/suggest/pack_lm.py --src mix_r4 --minc 20
~/.venvs/vikeydata/bin/python Tools/suggest/pack_nn.py --src mix_r4 --model lstm.pt   # after pack_lm: it maps to its word ids
```

## Metrics

The words a bar offers are its cells minus the word as typed (Apple quotes it: “resi”).
- **recall:** the share of Apple's offered words that Vikey's bar has too.
- **top:** Apple's first offered word is in Vikey's bar.
- **fix-agree:** when either keyboard will auto-correct (a highlighted cell), both pick the same word.

Gotchas:
- XCUITest's `typeText` bypasses the keyboard's predictions, so keys are tapped by coordinate.
- A new simulator inherits the Mac's region: on a Vietnamese Mac it gets the bilingual English and Vietnamese keyboard, with an introduction sheet over the keys.
- A test method can't be named `testRun`: XCTest's `testRun` property takes its selector, and the method never runs.

The test texts (in the private vikey-data repo, `suggest/`) are `synthetic/synthetic_en.txt` (LLM-written chat, notes and reviews) and `real/hn.txt` (Hacker News comments). Neither is in any count Vikey ships.

## Key areas (D65)

Which key a touch types, Vikey against Apple:
```
Tools/suggest/tapsample.py ~/Work/vikey-data/suggest/tap2/all.json          # 48 situations x 200 scattered touches
TEST_RUNNER_TAPS=all.json xcodebuild test -project Tools/suggest/AppleRef/AppleRef.xcodeproj -scheme AppleRef -only-testing:AppleRefUITests/AppleRefUITests/testTapMap   # Apple keyboard on
TEST_RUNNER_TAP_POINTS=all.json TEST_RUNNER_TAP_APPLE=apple_a.log,apple_b.log xcodebuild test ... -only-testing:VikeyTests/TapAreaBenchTests
Tools/suggest/tapfit.py bench.log          # fit TapModel's numbers, every 4th situation held out ("learn": per-key biases)
```
Drop Apple's touches that came out as digits or symbols: a touch on 123 leaves Apple's keyboard on the numbers for the next cases.
Apple agrees with itself 93.8% re-tapping the same points, so that is the ceiling.

