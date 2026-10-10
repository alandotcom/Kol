# Native macOS surfaces

Status: Accepted
Date: 2026-10-09

## Context

Kol is a menu bar dictation utility. Most interactions happen through a global
shortcut while another application retains keyboard focus. The previous window
combined settings, transcript history, and app information inside custom sidebar
navigation with decorative backgrounds. That structure gave preference editing
and transcript reading the same layout despite their different needs.

## Decision

Use three surfaces with distinct responsibilities:

- **Settings:** a SwiftUI Settings scene with General, Recording, Text, Models,
  and Privacy panes. Group related preferences using system forms and controls.
- **History:** a separate resizable window with a searchable transcript list,
  selectable detail text, and toolbar actions. Keep processing metadata secondary.
  Open it only through an explicit command; suppress launch and window restoration.
- **Recording:** a compact nonactivating panel that communicates the actual
  recording or processing phase while keyboard focus stays in the destination app.

Keep the menu bar as the entry point. Use standard app commands, including
Settings and About, and retain login-launch suppression of foreground windows.

System typography, semantic colors, native navigation, and standard control
styles define the appearance. Use a system material for the transient recording
panel, with an opaque fallback for Reduce Transparency. Avoid hand-painted glass,
window-wide tint gradients, oversized shortcut illustrations, and content cards
that duplicate native grouping.

## Behavior constraints

- Ending shortcut capture must restore global shortcut handling, including when
  a pane or window closes.
- Pausing history saving preserves existing transcripts and recordings.
  Destructive deletion remains an explicit, confirmed action.
- Copying selected text uses the normal macOS responder behavior. A separate
  command may copy the entire transcript.
- A processing indicator represents real work. An idle transition does not prove
  that dictation succeeded.
- The recording panel must never become the key window or intercept mouse input.
- Accessibility labels, keyboard focus, reduced motion, and reduced transparency
  are part of the implementation contract.

## Consequences

SwiftUI owns ordinary window and preference presentation. AppKit remains useful
for the nonactivating recording panel and application lifecycle integration.
The scene layout changes independently of the transcription engine and prompt
behavior. macOS 27 is the verification environment; the deployment target remains
macOS 26 for this change.

The initial panel remains a status display. Interactive stop/cancel controls and
failure recovery require a separate recording-session lifecycle design so that
the UI cannot offer actions the pipeline does not safely support.

## Visual verification

The debug build provides a synthetic panel harness:

```sh
open "/Applications/Kol Debug.app" --args --preview-recording-panel --preview-appearance=light
```

Quit the debug app before changing launch arguments. Use `dark` instead of
`light` to inspect the other appearance. The appearance override applies only to
the debug process and also works with normal startup. The panel harness skips
normal app startup effects and offers recording phases, synthetic microphone
levels, reduced-motion/transparency overrides, and a typing-focus check. Its
window diagnostics read the actual panel visibility and key-window state.

Keep screenshots under the ignored `build/design-verification/` directory. Use
synthetic or empty content in shared captures; saved transcripts and custom
context can contain private information.

### Verification on macOS 27.0.1

- XcodeBuildMCP completed all 220 tests with zero failures or skipped tests.
- The debug build script built and installed the app successfully with Xcode 27.
- Runtime checks covered native Settings presentation, Command-comma from
  History, transcript search, and the History sidebar's 240-point minimum.
- The synthetic panel appeared without becoming the key window. Text entry
  retained focus while the panel appeared. Light and dark rendering and the
  reduced-motion/transparency overrides were exercised.
- Independent source review found a modifier-only shortcut threshold display
  issue; the effective threshold is now shown and the reviewer confirmed the fix.

These checks do not cover a full VoiceOver walkthrough, live microphone-to-paste
dictation, or provider requests. Shortcut capture needs a manual check because
the UI automation tool's app-switching keys can be captured as a new shortcut.

## References

- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Apple: Modernize your AppKit app, WWDC26](https://developer.apple.com/videos/play/wwdc2026/289/)
