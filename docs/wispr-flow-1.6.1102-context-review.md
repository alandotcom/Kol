# Screen context lessons from Wispr Flow 1.6.1102

Inspected on 2026-10-10. Flow has several useful ideas beyond Kol's current context capture: Chromium accessibility setup, an accessibility tree representation alongside plain text, declaration-aware code vocabulary, and context delivery diagnostics. Kol already has cursor-relative text, local OCR, browser category resolution, and periodic capture. The next improvement should increase the relevance and reliability of context rather than increase the amount of text sent to the LLM.

## Scope and confidence

The supplied image was mounted read-only. Inspection covered its Electron ASAR, generated JavaScript, helper metadata, and native helper symbols and strings. Flow and its helper were not launched. No permissions were changed, no Flow service was contacted, and no application code was modified.

No earlier Flow package or analysis was found in the available project thread search, repository notes, or downloaded DMGs. These are findings from the current package, not confirmed additions since the previous review. Remote feature flags and server implementation are unavailable. A packaged handler establishes an implemented path; it does not establish that every user reaches that path or that the server uses every request field.

Artifacts:

- Input: `$HOME/Downloads/Flow-v1.6.1102.dmg`, SHA-256 `c8e4f24a3693c4d89debbfad2e43f1cb61743a2a8355c2d9e99b8b959110b0e7`.
- Mounted app: `/Volumes/Flow-v1.6.1102/Wispr Flow.app`.
- ASAR: `Contents/Resources/app.asar`, SHA-256 `da64ebcb3d1d48032ac0808b4734a3509596a6cc00a39d84ae0deaf921e9c11d`.
- Extracted bundle: `/tmp/kol-flow-1.6.1102/asar/.webpack/main/index.js`, SHA-256 `24413a433e4cf159816d60f194ad32def76741d7a5e5bed9b27581bb74eebac2`.
- Readable bundle: `/tmp/kol-flow-1.6.1102/main.pretty.js`, generated with the repository's installed Prettier. Line references below refer to this generated file. Named anchors support finding the same code in the original bundle.
- Outer app version: `1.6.1102`. Native helper version: `1.6.1100`, according to its Info.plist and `swift-helper-app-dist/provenance.json`.
- Kol comparison: commit `480a5c5938eac8ceefa277165c0dfb71f9b1c061`.

The companion [native helper evidence note](wispr-flow-native-1.6.1102.md) records binary hashes, API imports, string locations, and native-inspection limits.

## What the package actually does

### 1. It carries multiple kinds of context separately

Flow's `getContext()` constructs a request with:

- Application name, bundle ID, and URL.
- Separate AX words, OCR words, code symbols, and file names.
- Textbox contents, text before the selection, selected text, and text after the selection.
- `contentText` from `nearestTexts` and `contentHtml` from `axHTML`.

The textbox path caps before/after text at 500 characters each, trims at whitespace, and preserves selected text. The gRPC context builder sends an empty screenshot field; a separate optional OCR request sends an image. These paths should not be conflated. [F1, F2, F6]

`AppContextUpdate` stores surrounding text and conversation ID, immediately schedules a context update, and starts remote proper-noun extraction. `AppContextHTML` stores the helper's HTML. The later request builder includes that HTML. The server's use of the HTML is unknown. [F1, F3]

The native template represents AX roles and descriptions, selected elements, an insertion marker, nested elements, and scroll-area clipping. This supports a richer representation than a flat string. Static inspection does not establish exact geometry values or native traversal visibility rules. [N1]

**Lesson for Kol:** preserve the provenance of text. A focused draft, a selected range, a message header, sidebar names, and editor source should have distinct meanings. A small typed context model can retain those meanings without reproducing Flow's full HTML.

Kol already distinguishes cursor context and vocabulary, but `ScreenContextClient.findText()` can return text from a child, parent, or window walk. `captureCursorContextImpl()` then applies the focused element's selected range to that returned string. A range from an input is not necessarily a range into surrounding window text. When no range exists, Kol labels the entire fallback string as before-cursor text. These source boundaries deserve attention before adding more capture methods. [K1]

### 2. Chromium accessibility is a path worth testing before OCR

The helper contains explicit success/failure messages for setting `AXManualAccessibility`. Its editor adapter detects the "Screen Reader Optimized" mode and captures text-area/text-field contents from Cursor-like apps, including VS Code and Windsurf. Native evidence supports an accessibility setup mechanism and mode detection. It does not show Flow enabling VoiceOver or prove which apps receive the attribute. [N1]

Kol has no `AXManualAccessibility` setup in its application or core sources. Its visible-text walker prefers `AXVisibleChildren`, reads static text and headings, and uses fixed depth/node limits. OCR starts when the captured text is shorter than 50 characters. [K1, K2]

**Lesson for Kol:** benchmark accessibility setup and editor-specific AX reads against the current walker. The older claim in `docs/context-engineering.md` that Chromium apps universally hide content from AX is too broad. The Flow package supports a more nuanced investigation; it does not prove every target can supply rich AX text.

A useful experiment measures capture in synthetic Slack, browser, Cursor, and VS Code windows before and after AX setup. Count useful names and symbols, record duration, and check visible side effects. Keep OCR as fallback for poor AX results. Do not infer success from the length of toolbar or sidebar text alone.

### 3. Editor vocabulary comes from declarations as well as tabs

`CursorContextUpdate` caches filtered file names, appends text-area contents to surrounding text, and runs a local code parser. The parser uses language heuristics and regex patterns for functions, classes/types, and variables across several languages. It caps each block at 50 function names, 50 class names, and 100 variable names; the handler takes at most 20 variable names per block into the request's symbol field. This is regex extraction, not an LSP integration or compiler parser. [F4]

Flow filters file candidates that are too long, contain URLs, contain long hex runs, or resemble opaque generated stems. Its filename cache holds 100 entries. The bundled default for `IdeFileNamesOutOfAxContext` is enabled, preserving file names separately from ordinary AX nouns. Remote overrides are unknown. [F5]

Kol's IDE client reads tab titles. Its general vocabulary extractor recognizes camelCase, PascalCase, snake_case, multi-word capitalized names, and known file extensions. Declaration-aware extraction can recover plain identifiers such as `render`, `router`, or `cache` that the identifier-shape regexes miss. An enabled LLM vocabulary path may identify additional terms, but it does not replace deterministic declaration extraction. [K3, K4]

**Lesson for Kol:** add a bounded editor-context experiment with source ownership and language-aware symbol extraction. Prioritize nearby declarations and the active editor over identifiers from every visible code block. Evaluate preservation of short and lowercase symbols. Validate filename filters with real generated-file shapes represented by synthetic data.

### 4. Context capture needs a real failure boundary

Flow runs AX work in a separately signed helper process. Native imports include `AXUIElementSetMessagingTimeout`, and native strings identify traversal budget failures and maximum element limits. These establish mechanisms, but not their configured numeric values. Electron supervises helper responses, kills an unresponsive helper, and relaunches after process closure while the app is active. [N1, F7]

Kol's `withMainActorTimeout()` races synchronous `MainActor.run` work against a sleep in a task group. Cancelling the group cannot interrupt a blocking AX call. Structured task groups also wait for unfinished children before exiting. The two-second timer therefore does not provide a hard bound on AX execution or protect the main actor from a stuck target. Window title and browser URL reads also run synchronously in `handleStartRecording()` before the capture effect. [K2]

**Lesson for Kol:** move blocking AX work out of the UI process or otherwise provide a real isolation boundary. Set AX messaging timeouts where appropriate, enforce walk limits, and return partial or empty context without delaying recording. A timeout around an await is insufficient if the awaited synchronous operation cannot stop.

This is a source-level finding; an intentionally unresponsive AX target was not exercised during this review. Verify recovery with a controlled helper failure before declaring the failure boundary effective.

### 5. Measure whether useful context arrives in time

Flow sends updates as app information, raw context, extracted nouns, editor context, and OCR become available. The stream queues context independently of audio. It records `context_status`, AX capture time, vocabulary count, filename count, symbol count, and surrounding-text length. Its status distinguishes no context, raw context, and processed context. Proper-noun instrumentation also records extraction duration and whether another dictation started before the response arrived. [F3, F8]

That instrumentation is useful even when a provider is cloud-based and Kol's transcription is local. The package alone cannot tell us whether Flow's ASR consumes vocabulary before decoding, whether only formatting uses it, or whether those inputs improve accuracy. [F1]

Kol refreshes AX text every second, can refresh OCR after three changed-context counts, and rejects captures belonging to an obsolete session. The final prompt limits combined vocabulary to 30 terms. Local terms, IDE names, OCR terms, and remote terms are concatenated before that cap, so source order can determine which terms survive. [K2]

**Lesson for Kol:** add non-content diagnostics for capture source, elapsed time, target identity, term count by source, rejected/stale captures, and context available at stop. Measure short dictations separately. Use those results to choose source budgets and ranking before adding a more elaborate cache or parser.

### 6. Some apparent gaps are already covered, and some older features are gone

Kol already has cursor-relative before/after/selected text, local regex vocabulary, optional remote noun extraction, browser URL classification, conversation names, and periodic capture. [K1, K2, K4, K5]

Flow's optional screenshot extraction captures the display nearest the mouse, limits image dimensions to 2048, and sends a base64 PNG to `/llm/ocr`. Its bundled preference default is off. Kol instead captures a window by PID and runs Vision OCR locally, then retains vocabulary rather than sending the full OCR image or text. Flow's packaged OCR path provides no reason to replace Kol's local OCR. [F6, K2, K6]

Flow has a bounded Slack noun cache and editor filename cache across dictations. Slack insertion is gated by `SlackTagging`, whose bundled default is off. Names in the implementation describe these as persistent context, but the inspected caches are in-memory LRU objects; disk persistence was not established. [F3, F5, F9]

Kol's `VocabularyCacheClient` remains defined, but there are no application call sites for `merge` or `topTerms` in the inspected sources. Current transcription uses session captures. The older context plan's claim of active cross-session vocabulary caching does not describe the current reducer. [K2, K7]

Flow also observes text after paste, aligns corrections with the pasted text, filters candidate words or short phrases, caps a classifier request at four candidates, and validates that accepted candidates are a subset of the requested candidates. The helper carries paste IDs and observation stop reasons. This is a substantial learning pipeline, not just a text-change listener. [F10, N1]

Kol removed edit tracking in commit `186204c`. Reintroducing it needs a separate acceptance criterion for false suggestions, anchoring, privacy, and user control. It should not be the first context improvement.

## Recommended order

1. **Fix context ownership and responsiveness.** Keep focused text/ranges tied to their originating element and target identity. Establish an AX failure boundary that cannot stall the UI. Verify with focus changes, mismatched fallback text, and a stuck helper.
2. **Measure AX setup and capture quality.** Compare Chromium accessibility setup and app-specific reads with current capture and OCR on synthetic screens. Record relevant terms recovered, misleading terms, latency, and side effects.
3. **Carry compact structure and rank sources.** Preserve selected/focused text, nearby content, and peripheral vocabulary separately. Give each source a deliberate budget. Check name correction accuracy and hallucinated substitutions in evals.
4. **Extend editor extraction.** Recover nearby plain identifiers and declaration names, then filter generated filenames. Verify code dictation with lowercase symbols and existing file-tab hints.
5. **Consider scoped caching only after measurements.** Session isolation currently keeps capture ownership simple. If repeated dictations lose useful terms, try an ephemeral app/window or conversation cache with age and relevance limits.

Use Kol's composable prompt layers for any structured prompt change, keep eval prompt copies in sync, and run the relevant eval suites before tests and a debug build. This review changes documentation only and requires no app build or TCC changes.

## Source index

| ID | Primary source and locator |
| --- | --- |
| F1 | `main.pretty.js:202038`, `getContext()`, fields `contentText`, `contentHtml`, `vocabulary`, `textbox`; original bundle anchor `static getContext(){const e=(0,$t.T4)()` around character offset 3720471. |
| F2 | `main.pretty.js:192645` and `193112`, `MAX_TEXTBOX_CONTENTS_LENGTH = 500`, `limitedTextboxContents()`. |
| F3 | `main.pretty.js:239549`, handlers `AppContextUpdate` and `AppContextHTML`; original bundle around offsets 4403230–4407100. |
| F4 | `main.pretty.js:238680–239010`, `Parsed code symbols - Language`; `239726–239800`, `CursorContextUpdate`; original parser offset 4391070. |
| F5 | `main.pretty.js:241112`, webpack module `68019`, `VX` filename filter and `q0 = 100`; `324382`, bundled `IdeFileNamesOutOfAxContext` default. |
| F6 | `main.pretty.js:338540–338650`, webpack module `1810`, `shouldOCRScreenCapture`; `189274`, `extractProperNounsFromScreenCapture`, endpoint `/llm/ocr`; original bundle offset 6646081. |
| F7 | `main.pretty.js:240693–240747`, watchdog; `241380–241431`, process-close relaunch; anchors `No helper response received, killing helper service and relaunching` and `Launching helper service from process close`. |
| F8 | `main.pretty.js:201210`, `updateContext()`; `226609`, `context_status`/lengths; `230655`, raw/processed/no-context classification; `239610–239660`, noun extraction timing/race instrumentation. |
| F9 | Original bundle offset 6509494, `persistentAppContext` LRU construction with `slackContext` max 50 and filename cap; `main.pretty.js:324322`, bundled `SlackTagging` default false. |
| F10 | `main.pretty.js:208300–208470`, candidate filtering/classification; `189180`, `extractEditedWords()` accepted-candidate validation; `208577–208635`, `updateHistoryAndDictionary()`; `239385`, `UpdateEditedText`. |
| N1 | [Native helper evidence note](wispr-flow-native-1.6.1102.md), especially Accessibility context and geometry, Isolation and responsiveness, and App-specific context and edit observation. |
| K1 | `Kol/Clients/ScreenContextClient.swift`, `findText`, `collectVisibleText`, `captureCursorContextImpl`, `maxContextLength = 3000`, window-walk threshold 50. |
| K2 | `KolCore/TranscriptionFeature.swift`, `withMainActorTimeout`, `handleStartRecording`, `contextRefreshTick`, `ocrCaptured`, `contextTerms`, post-processing context construction. |
| K3 | `Kol/Clients/IDEContextClient.swift`, `extractTabTitlesFromAXTree`, `looksLikeFileName`; `KolCore/VocabularyExtractor.swift`, identifier patterns and source ordering. |
| K4 | `KolCore/Clients/LLMVocabularyClient.swift`, `extractNames`, `parseResponse`. |
| K5 | `Kol/Clients/WindowContextClient.swift`, URL extraction; `KolCore/AppContextResolver.swift`; `KolCore/LLMPostProcessing.swift`, `PromptAssembler.systemPrompt`. |
| K6 | `Kol/Clients/OCRClient.swift`, `captureAndOCR`, ScreenCaptureKit screenshot and `VNRecognizeTextRequest`. |
| K7 | `KolCore/VocabularyCache.swift`; repository search for `vocabularyCache`, `topTerms`, and client merge calls found definitions without runtime callers. |
