# Vikey

Vietnamese Telex typing with automatic Vietnamese/English switching for macOS, iOS, Android, Windows, Linux.

## Layout
- `Engine/`: shared C++17 engine. A change here ships on every platform. `Driver.cpp` is what the iOS keyboard runs.
- `App/`: macOS app (Swift). `iOS/`, `Android/`, `Windows/`, `Linux/`: platform apps.
- `Tools/autoswitch/`: engine harness, simulators, corpora; rule tests in `rules/`.
- `DECISIONS.md`: numbered decision log, newest first. `CONTRIBUTING.md`, `TRIAGE.md`: PR and issue rules.

## Commands
```sh
Tools/autoswitch/check.sh          # engine lock: rule cases, reported bugs, decision coverage, goldens, Telex lock, driver parity, perf
Tools/autoswitch/check.sh update   # accept golden changes, only after reviewing every printed diff
xcodegen generate && xcodebuild -project Vikey.xcodeproj -scheme Vikey -configuration Release build   # macOS app
python3 Tools/quality/scorecard.py --compare origin/main   # accuracy and speed vs main
```
Other platforms' tests: table "Where tests go" in `CONTRIBUTING.md`.

## Engine change workflow
1. Add cases to `Tools/autoswitch/rules/rules.tsv`, tagged with the decision (`D64`).
2. Add a `## N. ...` entry at the top of `DECISIONS.md` (Status, Problem, Fix, Not covered). `rules/decisions.py` fails when a decision has no test and no reason in `rules/decisions.tsv`.
3. Run `check.sh`, review the golden diffs, then `check.sh update`. Say in the PR which results changed and why.
4. Commit subject: `D<N>: <what the user sees>`, e.g. `D64: stretching "ờ" with o kept the ơ ("ờooo")`.

## Gotchas
- `Vikey.xcodeproj` is generated and gitignored: edit `project.yml`.
- `check.sh` is zsh and runs the default Telex style with `VIKEY_TELEX_STYLE` unset. Styles 1 and 2 (D56) have their own case files.
