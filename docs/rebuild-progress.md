# Rebuild progress

The [original audit](../exa-results/kol-codebase-audit-2026-10-09/audit.md)
records findings against the code before the rebuild. This file tracks subsequent
implementation so the original evidence remains intact.

## Completed before the context privacy work

- Updated the Point-Free dependency group to restore Xcode 27 builds and tests,
  addressing KOL-01. Other dependency upgrades remain open.
- Replaced the custom app shell with native Settings, a separate searchable
  History window, and a nonactivating recording panel. The
  [design note](decisions/001-native-macos-surfaces.md) records the accepted
  structure and runtime checks.
- Changed the Groq default to `openai/gpt-oss-120b` and added OpenRouter with
  separate credentials and a searchable live model catalog.
- Added optional trailing spaces and local filler-word removal. The latest
  completed verification before this slice passed all 245 tests and installed
  Kol Debug.

## Context privacy: KOL-02 and KOL-03

Implemented in `TranscriptionFeature` with a context generation for each
dictation. Local vocabulary extraction remains available with AI cleanup off,
and automatic vocabulary no longer carries across dictations. Capture, ASR, and
cleanup results identify their generation before changing state.

Both provider paths recheck current consent and provider configuration after
loading credentials. Cleanup includes screen, IDE, OCR, and conversation data
only when the relevant settings permit it. Responses that arrive after consent
or provider changes do not replace the original transcription. A request already
sent cannot be recalled.

Independent review identified three issues that were fixed in this slice:
untagged ASR completions, IDE filenames lost during refresh, and stale processing
flags when replacing a pending cleanup. Reducer tests cover these cases along
with delayed keychain, OCR, and provider responses using synthetic data.

Verification passed all 257 tests with zero failures or skipped tests, including
12 new test declarations covering 25 privacy scenarios. Logs are in
`build/verification/context-privacy-full-tests.log`. The test state uses explicit
in-memory shared values and does not depend on the user's saved settings.
The repository build script also built and installed Kol Debug successfully;
the build log is `build/verification/context-privacy-build.log`. These checks
used mocked provider calls and capture inputs, not live private screen content.

## Window launch follow-up

History now disables scene restoration as well as default launch. The debug
build passed all 257 tests and was installed successfully. Runtime verification
opened History through the Window menu, quit with History open, and relaunched
into Settings with no History window restored. Logs are in
`build/verification/history-launch-tests.log` and `history-launch-build.log`.

A reported brightness flash when clicking Settings tabs remains unresolved.
Window dimensions stayed constant, but automated screenshots did not capture
the transient brightness change. A screen recording of the flash is needed to
distinguish a toolbar material change from a pane redraw.

## Recording lifecycle: KOL-04 and KOL-05

Recording, transcription, cleanup, archival, and insertion now share one session
identifier and an explicit phase. Recorder operations require that identifier,
so delayed cleanup from an old recording cannot stop its replacement. Startup
returns a typed result, and failed startup clears the recording indicator.

Each take owns its audio file and sleep assertion. Media pause and resume calls
run in order. Cancellation rejects late transcription and cleanup results,
removes uncommitted audio, and prevents subsequent history insertion or paste.
History committed before cancellation remains available. A synchronous native
operation already in progress can finish before cancellation takes effect.

Initial screen capture, refresh capture, and the refresh timer also belong to
the session. Replacement and failed startup cancel their outstanding work,
including when the replacement has screen context disabled.

Independent review also found that cancellation could arrive before TCA
registered a queued effect. Startup and timer entry now check the current
session directly. A production `Store` test sends Start and Cancel without
yielding and verifies that no microphone acquisition or timer survives.
Repeated stop during acquisition preserves the first stop's duration.

Source review found that cancellation between clipboard preparation and paste
could leave cancelled text behind when clipboard retention was disabled.
Cancellation now restores the previous clipboard only while Kol still owns
the current contents. The same ownership check protects delayed restoration
after successful paste. This partially addresses KOL-09; overlapping insertion
transactions and the live copy-during-restoration check remain open.

Controlled-delay tests reproduced three failures before implementation. The
current full suite passes all 273 tests with zero failures or skipped tests.
The added tests use synthetic audio and mocked providers; clock-controlled
tests check that cancelled capture work leaves no pending sleeps. Evidence is
in `build/verification/session-lifecycle/`, including
`baseline-regressions.log`, `queued-admission-regression.log`, and
`full-suite-reviewed.log`. Independent review has no unresolved findings.

The repository debug build succeeded and installed Kol Debug. Launch logs
confirm app startup, model preload, and existing permissions. Native UI
verification could not proceed because the Mac was locked. Live microphone
cancellation, stop grace, sleep prevention and release, media restoration,
and pasteboard restoration remain unverified. `debug-build.log`,
`runtime-launch.log`, and `runtime-checks.md` in
the verification directory record these limits.

## Menu bar icon follow-up

The native menu bar loaded `KolIcon` at 256 by 256 points. The rewritten
SwiftUI label applied an 18-point view frame, which did not change the native
image size used by `MenuBarExtra`. The vector asset now declares an intrinsic
size of 18 by 18 points, uses a single universal representation, and preserves
vector data. The ineffective resizing modifiers were removed.

All 273 tests passed, and the debug build was installed and relaunched.
AppKit inspection of the installed bundle confirmed an 18 by 18 point
template image, including a 36 by 36 pixel Retina representation. Before and
after measurements, test output, and build output are in
`build/verification/menu-icon/`. The locked Mac prevented visual confirmation
of the menu bar.

## Remaining work

The full audit remains the backlog. Recording lifecycle ownership has passed
automated checks and source review. Its remaining acceptance work is live
dictation and cancellation on an unlocked Mac.

Other open areas include bounded Accessibility calls, audio executor ownership,
archive recovery, overlapping clipboard insertions, remaining dependency
upgrades, and distribution verification. The native UI still needs a full
VoiceOver walkthrough and live
dictation checks.

Local cleanup model work is deferred until after the current rebuild. The
[Gluon research note](../exa-results/detta-gluon-model.md) records the findings.
