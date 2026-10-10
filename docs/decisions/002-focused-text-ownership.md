# Focused text ownership

Status: Implemented and verified
Date: 2026-10-10

## Problem

The Accessibility reader could replace a short compose-field value with text from
an ancestor or window, then split that text using the compose field's cursor
range. The prompt claimed cursor position in a string that belonged to another
control. Selecting text also prevented broad window vocabulary capture. Two
capture operations and two stored representations made the ownership hard to
follow.

The existing separation is intentional. Commit `488585f` routes cursor context
to the cleanup prompt and broader visible text to vocabulary. Commit `f4adcc8`
bounds context to one dictation and rechecks consent at request boundaries.
These constraints continue to apply.

## Usage

Recording start and refresh make one dependency call:

```swift
let snapshot = await withMainActorTimeout { screenContext.capture(recordedApp) }
guard Self.acceptsContext(session, settings, generation: generation) else { return }
await send(.contextRefreshed(generation: generation, textSource: snapshot))
```

The reducer stores `snapshot.focused` and extracted vocabulary. The cleanup
request receives only focused text and vocabulary hints:

```swift
PostProcessingContext(
  text: transcript,
  focusedText: contextAllowed ? capturedFocusedText : nil,
  vocabularyHints: vocabulary
)
```

## Shape

`ScreenContextClient.capture` accepts the recorded `FrontmostApp` and returns a
`TextSourceSnapshot`. The live client verifies the foreground PID and the focused
AX element's PID. It reads value, selection range, and selected text on the exact
same element. The window walk uses the recorded application's window and stays
separate. AppKit and AXorcist remain in the app target.

`FocusedText` owns UTF-16 conversion and bounds in KolCore. Its content is
positioned, unpositioned, or selection-only. Only its initializer can produce a
stored position claim. Invalid offsets, overflow, or an offset inside a Unicode
character retain unpositioned text. Validation happens before truncation. The
focused text has one 3,000-character budget, including any selection; positioned
sides have at most 1,500 characters each.

The temporary snapshot contains focused text and at most 3,000 characters of
window text. Local vocabulary is extracted separately from each source and
merged with focused terms first. The existing remote name request gets a bounded
share of each source. OCR runs independently when enabled. A bounded region around the insertion
caret or focused field supplies vocabulary before broader window terms. AX text
volume cannot suppress OCR, because unrelated sidebar text can satisfy a length
threshold while omitting the identifier beside the composer.

The reducer rechecks the target PID at stop and before remote vocabulary or
cleanup requests, excluding all captured sources on a mismatch. A target change during cleanup rejects the
context-dependent result. The reducer discards raw window text after extraction. It retains one focused
value and the vocabulary terms, compares those values on refresh, and keeps
existing generation, provider, and consent guards. The prompt accepts only
`FocusedText`. Unavailable cursor positions get explicit labels. `CursorContext`,
the flat prompt input, and the two old capture closures are removed.

This interface hides AX binding, text ownership, Unicode conversion, and bounds
behind one capture operation. The pure text factory is reachable by non-hosted
KolCore tests. Source review verifies the live same-element reads.

## Synthesis decision

Two complete designs were compared. Claude Fable proposed a focused enum beside
bounded surroundings. GPT 6.1 proposed a source-segment list with prompt and
vocabulary projections. Claude Opus independently chose the focused snapshot,
scoring it 21/25 against 15/25 for source segments. The parent also chose the
focused snapshot, based on the smaller API and the narrower prompt input.

The synthesis takes `FrontmostApp` from the segment design and retains separate
consumer projections. It rejects the public segment list and raw OCR case because
current OCR is already vocabulary-only. It also rejects public generic owner
readings and mutable bounds. The live reader pairs attributes on one exact
element; exposing owner tokens would add an API without proving that AX reads
came from the correct element. That binding receives independent source review.
The proposed internal owner types cannot be shared with the app target without
an additional public bridge.

The default GPT 5.6 runner failed at its account usage limit before producing an
artifact. An available GPT 6.1 runner produced the second candidate. Grok was
unavailable in the live provider catalog.

## Tradeoffs accepted

- Focused text stored on a descendant does not become the draft automatically.
  Descendant text can still supply window vocabulary. Promoting a descendant
  requires evidence that the descendant is the editing control.
- Message history contributes terms rather than raw prompt prose. Mention rules
  now use names supplied from the screen through focused text or vocabulary.
- Terminal AX text, including selection-only output, is excluded consistently.
  Local OCR vocabulary remains available under its consent setting.
- Unpositioned text keeps a bounded tail. The missing cursor position is explicit.
- The existing main-actor timeout cannot interrupt a synchronous AX call.
  Process isolation remains separate work.

## Alternatives considered

A source-segment array supports future sources but exposes duplicate focused
segments and raw OCR retention that current callers do not need. Keeping both old
capture operations would retain duplicate walks and caller-side fallback policy.
A generic owner-token protocol would test token equality while leaving real AX
ownership dependent on live reads. The chosen API concentrates that policy in
the live capture function and the pure text factory.

## Verification

Baseline XcodeBuildMCP tests passed all 273 tests. The migrated suite also passed
273 tests before final review. Tests cover short drafts beside long window text,
emoji-aligned selections, malformed UTF-16 offsets, long values split before
truncation, selection-only text, total bounds, separate vocabulary budgets, and
existing consent and generation cases.

Promptfoo's current OpenAI adapter includes `reasoning_content` in evaluated output
by default. The provider now sets `showThinking: false` so evals match Kol's
consumption of `message.content`. No application response parsing changed. All four affected static eval prompts
were compared with the built runtime assembler and match after whitespace
normalization.
The final XcodeBuildMCP run passed 277 tests with zero failures or skipped tests.
The screen, focused-text, name, and mention suites passed 5, 3, 6, and 7 cases,
respectively. The debug build script built and installed the app successfully.

Independent review found a target-switch gap at the final request boundary, a
missing selection-consistency check, and missing window-only fallback coverage.
All findings were addressed locally and verified by targeted tests and the full
suite. Stop-before-refresh and switch-during-keychain tests now exclude every
screen-derived source. Conflicting selection attributes become unpositioned.

A temporary native window harness compiled the actual live client against the
built KolCore framework. Its own synthetic window had a short `use draftItem`
field and separate `sidebarItem` text. Capture kept the field separate and
extracted both terms. The harness reported unavailable AX cursor range and
correctly produced unpositioned text. Its process did not have general
Accessibility trust, so this verifies self-window AX reads and vocabulary
routing, not cross-application permissions or every editor's AX behavior.

## Architecture assessment

Implementation kept the selected ownership boundary. The public generic
reading seam was removed during synthesis, and window text became temporary
instead of state retained for the entire session. Review added final target
checks and selection-consistency validation within the existing boundaries.
No repeated workaround or new subsystem was needed, so the architecture was
retained.


### Caret-local OCR revision

Live recordings after the focused-text change still produced `coal core` with
`KolCore` visible. The cleanup request contained sidebar titles but no `KolCore`.
Two same-model design candidates and an independent judge compared bounded
crop recognition with full-window recognition followed by spatial ranking. The
bounded crop was chosen to limit recognition work and unrelated text. Per-line
vocabulary extraction and Apple's caret-bounds constant were taken from the
ranking design.

The native OCR client owns window selection, insertion geometry, screenshot
capture, crop conversion, and distance ordering. It returns vocabulary through
one PID-based operation. The reducer runs OCR in a separate sequential loop,
starting immediately and sleeping three seconds after each completion. The AX
refresh cannot cancel OCR, and static AX text cannot prevent another attempt.
Hints are merged as focused AX terms, local OCR terms, then broader sources,
before deduplication and the 30-term limit. OCR never supplies positioned draft
text. The target PID and window geometry are checked again after capture.

The first implementation captures only the verified independent window without
shadows and crops its image before Vision. It avoids assuming window-local
`SCStreamConfiguration.sourceRect` coordinates. A global-screen geometry helper
keeps negative origins and display pixel scaling testable. Live capture remains
the acceptance check for window image alignment and short-recording latency.


Live verification on October 10 captured a local focused-control crop in 246 ms.
The actual cleanup request put `KolCore` first, and changed raw `We're working on
coal core.` to `We're working on KolCore.`. Independent correctness review added
an exact AX window identity recheck and preserved OCR retries when the recorded
app briefly loses focus. Geometry on partially offscreen windows remains a
platform verification limit.


A subsequent `OCR retries` recording became `ocrRetries` even though that
identifier was absent from the hints. The app-category matcher treated any app
name containing `code` as a code editor. The generic `Code` display name now
matches exactly, preserving VS Code identification without applying code-token
rules to the T3 Code composer.

Groq GPT-OSS cleanup requests now specify low reasoning effort, scoped to the
Groq host and the two documented GPT-OSS model IDs. A three-pair comparison of
synthetic dictation measured median request times of 611 ms with the default
and 246 ms with low reasoning; all three outputs matched. These samples do not
establish production latency percentiles. Code, screen, focused-text, vocabulary,
and separator evals passed after adding explicit punctuation-description and
informal-question examples. The broad English suite now uses supported per-case prompt labels and an
available independent grading model. General, messaging, document, and code
cases run against their intended prompts. The global prompt selector was removed
so dedicated CLI suites can use their own prompt files.


### Release verification

Independent release and Thermos reviews found no remaining release blockers.
The release review identified a foreground-target check missing after the
Keychain wait before remote vocabulary extraction. A regression test reproduced
the request after switching applications; adding the PID check prevented it.
The full suite passed 290 tests after that fix. Unused OCR scheduling counters
and a snapshot character-count getter were removed following the quality review.

Live dictation retained `OCR retries` as prose and resolved `KolCore` and
`Kol/Clients` from nearby screen vocabulary. Measured release-to-insertion times
were 516 ms for the prose sample and 781 ms for the combined identifier sample.
Native alignment on partially offscreen windows and mixed display scales remains
a verification limit.
