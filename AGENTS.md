# Working on Vikey as a coding agent

How an agent takes a task on this fork from report to open PR. Layout, commands and gotchas are in `CLAUDE.md`;
where each platform's tests live is the table in `CONTRIBUTING.md`; labels are in `TRIAGE.md`.

## Ground rules

- Git stays on the fork: branch from `origin/main`, push to `origin` (`lang315/Vikey`), open PRs with
  `gh pr create --repo lang315/Vikey --base main`. `upstream` (`tonyminibot/Vikey`) is fetch-only: never push,
  open PRs or comment there.
- The user merges. Your work ends at an open PR with green CI.
- One change per PR. A second bug found on the way gets its own branch and decision.

## 1. Classify

Name the kind: `correctness` (wrong output, lost text, crash, privacy) or `taste` (what a word should become, when
auto switch triggers, how something looks). Unclear means `taste`. For `taste`, lay out the options as keys typed and
text shown for each, ask the user, and build the option they pick.

Done when: the kind is named, and for `taste` the user has chosen.

## 2. Make it red

Write the test first, as the exact keys the user typed:
- Typing behavior: cases in `Tools/autoswitch/rules/rules.tsv`, tagged with the decision `D<N>` (step 3). A bug the
  user reported also gets a row in `Tools/autoswitch/rules/reported.tsv`.
- Mac event-tap code that changes what is typed (`App/Core/VikeyCore.mm`): mirror the change in
  `Tools/autoswitch/test/harness.cpp`, which replays what the Mac app does with the engine's output, and test there.
- Other platform code: that platform's `Tests/` folder.

Done when: the new cases fail on `main` and every other check passes. Keep the failing output for the PR.

## 3. Record the decision

Add `## N. <what the user sees>` at the top of `DECISIONS.md` with Status, Problem (in the user's words), Fix, Result,
Not covered; the newest entries are the model. N is one above the highest number in both `DECISIONS.md` and
`upstream/main:DECISIONS.md` (`git fetch upstream` first), since the two share one number space.

Done when: `python3 Tools/autoswitch/rules/decisions.py` passes.

## 4. Fix

Make the smallest change in the layer that owns the bug. An `Engine/` change ships on every platform, and
`Engine/Driver.cpp` (iPhone, Android) must keep matching the simulator.

Done when: the new cases pass and `Tools/autoswitch/check.sh` fails on golden diffs at most.

## 5. Account for golden diffs

`check.sh` prints every golden line that changed. Explain each in Result, as intended or as a regression you then
fix, and only then run `Tools/autoswitch/check.sh update`.

Done when: `check.sh` exits 0 and every changed golden line is explained in Result.

## 6. Measure

Run `python3 Tools/quality/scorecard.py --compare origin/main`. App changes also build with the `CLAUDE.md` command
and run their platform tests. Sweeps over word lists are scratch scripts kept outside the repo.

Done when: Result gives before → after for every metric that moved and says "unchanged" for the rest.

## 7. Review

Get a fresh review of the diff (`/code-review`, or a reviewer subagent given the diff alone). Reproduce each finding in
the harness, add it as a case (`review: was "..."`), fix it, and note it in the decision ("Found in review").
Commit fixes as `D<N>: review fixes: <what broke>`.

Done when: every finding is fixed with a case, or answered in the PR body.

## 8. Open the PR

- Branch `fix/d<N>-<slug>`; commit subject `D<N>: <what the user sees>`.
- Body sections: Problem, Fix (D<N>), Review fixes, Evidence, Not covered. Evidence is the red output from step 2,
  `check.sh` output with its exit status, the scorecard numbers, and build output for app changes. Not covered names
  what was not tried live. Screenshots are optional on this fork.

Done when: the PR is open on `lang315/Vikey`, the Engine rules run is green, and the PR report comment is posted.
Then hand over to the user.

## Upstream sync

Branch `sync/upstream-<version>`. When upstream brings a decision number the fork already uses, the fork's decision
moves to the next free number and upstream's keeps its own. Renumber in a separate commit before
`git merge upstream/main`, with a word-boundary replace over the heading, mentions, code comments and `D<N>` tags,
and add a line to the entry naming its old number (D73 is the model).

Done when: every `## N.` heading in `DECISIONS.md` is unique and `check.sh` exits 0 on the merge.
