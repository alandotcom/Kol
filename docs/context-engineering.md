# Context Engineering for Kol

## Motivation

Kol's transcription quality is fundamentally limited by how much it knows about what the user is looking at. Today, context capture is a single synchronous AX text grab at recording start, fed only to LLM post-processing. The ASR model runs blind. This document outlines a comprehensive context engineering strategy — methods for capturing, structuring, caching, and routing contextual information to maximize transcription accuracy across the entire pipeline.

---

## Current State

**What Kol does today:**
- `ScreenContextClient.captureVisibleText()` — single synchronous AX call at recording start, returns up to 3000 chars of visible text
- `ScreenContextClient.captureCursorContext()` — structured before/after/selected text relative to cursor position *(Phase A, done)*
- `characterBeforeCursor()` — single char before cursor for spacing decisions
- App category detection via bundle ID / display name → code / messaging / document
- Terminal-aware windowing (tail of text vs head)
- `VocabularyExtractor` — regex-based extraction of identifiers, proper nouns, file names from screen text *(Phase A, done)*
- `VocabularyCacheClient` — in-memory LRU cache of extracted vocabulary across dictation sessions *(Phase A, done)*
- Context fed to LLM post-processing via `PromptAssembler` system prompt with structured cursor context and vocabulary hints
- Vocabulary cache persists for app lifetime (not across launches)

**What's missing:**
- ASR model has zero contextual information
- ~~No structured cursor-relative text (before/after)~~ *(done)*
- ~~No proper noun or identifier extraction~~ *(done — local regex)*
- ~~No persistent vocabulary across dictation sessions~~ *(done — in-memory LRU)*
- No post-paste correction tracking
- No conversation awareness in messaging apps
- No IDE-specific context (variable names, open files)
- Context captured once, never updated during dictation

---

## 0. Foundation: AX Framework Selection

### Problem
Kol's `ScreenContextClient` (~260 lines) uses raw `AXUIElement` C API calls for text extraction near the cursor. This works for the current single-grab-at-recording-start approach, but the features planned in this document — tree walking, element querying, real-time observation, app-specific adapters — would require hundreds of lines of custom traversal, querying, and observation code on top of the raw C API.

### Decision: AXorcist

**[steipete/AXorcist](https://github.com/steipete/AXorcist)** — MIT, Swift 6.2, SPM library, single dependency (`swift-log`). It is the accessibility engine behind both Peekaboo (3K stars) and Ghost OS (1.2K stars).

**What it provides over raw `AXUIElement` calls:**

| Capability | Raw C API | AXorcist |
|------------|-----------|----------|
| Find element by role/title/value | Manual tree walk | `QueryCommand` with 6 match modes (exact, contains, regex, prefix, suffix, containsAny) |
| Hierarchical navigation | Manual parent/child iteration | `PathNavigator` with locator chains |
| Recursive tree dump | Custom BFS/DFS code | `collectAll` with depth limits and filter criteria |
| Focused element + attributes | `AXUIElementCopyAttributeValue` | `getFocusedElement` with attribute selection |
| Real-time observation | `AXObserverAddNotification` + CFRunLoop | `observe` command with async notifications (`AXFocusedUIElementChanged`, `AXValueChanged`, `AXSelectedTextChanged`) |
| Structured output | Manual dictionary building | `AXElementData` — Codable struct with role, attributes, textual content, children, path |
| Permissions | Manual `AXIsProcessTrusted` | Async/await + `AsyncStream<Bool>` for monitoring |
| Text extraction | Manual parameterized attribute queries | `insertionPointLineNumber()`, `selectedTextRange`, `isEditable()`, `stringValue()` |

**Which planned features benefit:**

| Feature | Without AXorcist | With AXorcist |
|---------|-----------------|---------------|
| Structured cursor context (§1) | Extend existing raw API code | `getFocusedElement` with attribute queries |
| IDE-specific context (§4) | Custom AX tree walk per editor | `collectAll` with role filter for tab bar elements |
| Conversation awareness (§5) | Custom walk of chat UI per app | `collectAll` with role/subrole filters for message elements |
| Continuous context updates (§8) | Polling timer + manual AX calls | `observe` for `AXValueChanged` / `AXFocusedUIElementChanged` |
| App-specific adapters (§10) | Imperative per-app traversal code | Declarative queries and path locators |

**Requirements:**
- Swift 6.2 (`swift-tools-version: 6.2`) — verify Xcode compatibility before adopting
- macOS 14+
- Add as SPM dependency: `.package(url: "https://github.com/steipete/AXorcist.git", from: "0.1.0")`

**Migration path:**
1. Add AXorcist as a dependency
2. Rewrite `ScreenContextClient` internals to use AXorcist queries (keep the public API unchanged)
3. New features (§4, §5, §8, §10) build directly on AXorcist from the start
4. Remove raw `AXUIElement` C API calls as features migrate

### Complementary: CursorBounds

**[Aeastr/CursorBounds](https://github.com/Aeastr/CursorBounds)** — 111 stars, SPM, macOS, last push Jan 2026. Provides:
- Cursor screen position (caret rect, text field bounds, mouse position)
- Browser context extraction for 18+ browsers (current URL, domain, page title)
- App context (focused app name, bundle ID, window title)

**Use case:** The browser URL context is uniquely useful — it tells us "user is writing in Gmail" vs "user is writing in Google Docs" without parsing window titles. This enriches app category detection (§10 BrowserAdapter) and could distinguish `mail.google.com` (email mode) from `docs.google.com` (document mode) directly.

**Not a replacement for AXorcist** — CursorBounds gives cursor *position* and app metadata, not text content or tree structure.

### Alternatives Considered

| Library | Stars | Status | Why not |
|---------|-------|--------|---------|
| AXSwift (tmandry) | 404 | Unmaintained since 2023 | No tree walking, no structured output, no observation helpers |
| AXUI/AXON (1amageek) | 5 | New, tiny community | No license, no text extraction, flat dump only |
| MacosUseSDK (mediar-ai) | 195 | Active | Backup if Swift 6.2 is a blocker — macOS 12+, zero deps |
| Raw C API (current) | — | — | Works for current scope, doesn't scale to §4-§10 |

---

## 1. Structured Cursor Context

### Problem
`captureVisibleText()` returns a single string. The LLM doesn't know where the cursor is within that text, which limits its ability to match style/tone of surrounding content and resolve ambiguous words.

### Design
Split the existing AX capture into structured fields:

```swift
struct CursorContext {
    let beforeText: String?    // Up to 500 chars before cursor, truncated at word boundary
    let afterText: String?     // Up to 500 chars after cursor, truncated at word boundary
    let selectedText: String?  // Currently selected text (if any)
    let isEditable: Bool       // Whether the focused element accepts text input
    let elementRole: String?   // AX role of focused element (AXTextArea, AXTextField, etc.)
}
```

### Implementation
- Already read `kAXSelectedTextRangeAttribute` in `characterBeforeCursor()` — extend to extract the range value
- Use `kAXStringForRangeParameterizedAttribute` with ranges `[0, selectionStart]` and `[selectionEnd, length]`
- Truncate each field to 500 chars at word boundaries (find last/first whitespace within limit)
- For `beforeText`: truncate from the front (keep nearest 500 chars to cursor)
- For `afterText`: truncate from the back (keep first 500 chars after cursor)
- Expose as new `ScreenContextClient.captureCursorContext()` alongside existing `captureVisibleText()`

### Prompt Integration
Update `PromptLayers.screenContext` to present structured fields:

```
<before_cursor>
...text before cursor...
</before_cursor>
<after_cursor>
...text after cursor...
</after_cursor>
```

This replaces the current flat "visible on screen near cursor" text block.

### Dependencies
- None — builds on existing AX infrastructure

### Complexity
Low. Mostly refactoring existing code.

---

## 2. Proper Noun & Identifier Extraction

### Problem
The LLM sees raw screen context but must infer which words are proper nouns, identifiers, or domain terms worth preserving. This is error-prone — the LLM may "correct" a correctly-transcribed proper noun or miss an ASR error on a name it doesn't recognize.

### Design
Extract a vocabulary list from screen context before sending to the LLM:

```swift
struct ExtractedVocabulary {
    let properNouns: [String]     // Names, companies, products from text
    let identifiers: [String]     // camelCase/snake_case tokens from code
    let fileNames: [String]       // Detected file paths/names
}
```

### Implementation

**Option A: Local extraction (no network)**
- Regex-based identifier extraction: `/\b[a-z][a-zA-Z0-9]*(?:[A-Z][a-zA-Z0-9]*)+\b/` for camelCase, `/\b[a-z]+(?:_[a-z]+)+\b/` for snake_case
- Capitalized-word extraction for proper nouns: `/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/` (filter out sentence-start words using position heuristics)
- File extension detection: `/\b[\w.-]+\.\w{1,5}\b/`
- Pros: Zero latency, no API cost, works offline
- Cons: Lower accuracy for proper nouns, can't distinguish "Hello" (sentence start) from "Hello" (product name)

**Option B: LLM-assisted extraction**
- Fire-and-forget async call to the LLM endpoint at recording start:
  ```
  System: Extract proper nouns, names, and technical identifiers from this text. Return as comma-separated list. If none, return "EMPTY".
  User: <screen context text>
  ```
- Use the fastest available model (e.g., Cerebras inference)
- Race with the transcription — if extraction finishes before transcription, include results in LLM post-processing prompt; otherwise skip
- Pros: Higher accuracy
- Cons: Adds latency, requires API, costs tokens

**Recommended: Start with Option A, add Option B as enhancement**

### Prompt Integration
Add extracted vocabulary as explicit hints in the LLM prompt:

```
<vocabulary_hints>
Names and identifiers visible on screen: TranscriptionFeature, PromptAssembler, handleStartRecording, Jane Smith, Kol
</vocabulary_hints>
```

Place after screen context, before custom rules.

### Dependencies
- Structured cursor context (section 1) improves extraction quality but isn't required

### Complexity
Medium. Option A is straightforward regex work. Option B requires async orchestration.

---

## 3. Persistent Vocabulary Cache

### Problem
Context is ephemeral — switching away from an app and back loses all extracted vocabulary. Users dictating in Slack lose the names they were just talking to. Users in Xcode lose the function names they were just editing.

### Design

```swift
struct VocabularyCache {
    // Per-app LRU caches
    var messagingNames: LRUCache<String>    // Max 50 entries
    var codeIdentifiers: LRUCache<String>   // Max 100 entries
    var codeFileNames: LRUCache<String>     // Max 50 entries

    // Keyed by app category (not individual app)
    func merge(extracted: ExtractedVocabulary, category: AppContextCategory)
    func vocabulary(for category: AppContextCategory) -> [String]
}
```

### Implementation
- In-memory LRU caches, keyed by app context category
- On each dictation: extract vocabulary (section 2), merge into cache
- When assembling prompt: include cached vocabulary alongside freshly-extracted vocabulary
- Dedup entries (case-insensitive for names, case-sensitive for identifiers)
- Caches persist for app lifetime, not across launches (no disk persistence needed initially)
- Consider: persist to UserDefaults or a small JSON file for cross-launch survival

### Cache Eviction
- LRU with fixed max size per category
- On merge: touch existing entries, append new ones, evict oldest if over limit

### Dependencies
- Proper noun extraction (section 2)

### Complexity
Low-medium. LRU cache is straightforward; integration with prompt assembly needs care.

---

## 4. IDE-Specific Context

### Problem
Code editors expose rich structural information beyond raw text — open file names, visible identifiers, language mode, cursor position within a function. Kol treats all code editors identically.

### Design

```swift
struct IDEContext {
    let openFileNames: [String]       // Tab bar / file tree
    let visibleIdentifiers: [String]  // Variable/function/class names near cursor
    let languageMode: String?         // File extension or editor language setting
    let currentFunction: String?      // Function/method containing cursor
}
```

### Implementation

**Phase 1: AX-based extraction**
- For VS Code / Cursor / Zed: read AX tree to extract tab titles (file names)
- Parse the focused text area content for identifiers using language-aware regex
- Detect language from file extension in tab title or from identifiers (heuristic)

**Phase 2: Editor extension integration (future)**
- VS Code extension that exposes current file, symbols, and language via a local IPC channel
- Xcode: read workspace state from `xcuserdata` or use Xcode's scripting bridge
- This is significantly more work and can wait

### Prompt Integration
For code context, extend the code app context layer:

```
<editor_context>
Open files: AppFeature.swift, TranscriptionFeature.swift, LLMPostProcessing.swift
Language: Swift
Nearby identifiers: handleStartRecording, capturedScreenContext, resolveModelAndLanguage
</editor_context>
```

### Dependencies
- Proper noun extraction (section 2) for identifier parsing
- Structured cursor context (section 1) for positional awareness

### Complexity
Phase 1: Medium. Phase 2: High (per-editor integrations).

---

## 5. Conversation Awareness

### Problem
In messaging apps (Slack, iMessage, WhatsApp), Kol doesn't know who the user is talking to or what was said. This means the LLM can't resolve references ("tell him", "yes to that"), match conversational tone, or correctly capitalize participant names.

### Design

```swift
struct ConversationContext {
    let participants: [String]          // Names of people in the conversation
    let recentMessages: [ChatMessage]   // Last N messages
    let conversationId: String?         // Opaque ID for cache keying
}

struct ChatMessage {
    let sender: String
    let content: String
    let isCurrentUser: Bool
}
```

### Implementation

**Phase 1: Participant extraction from AX tree**
- In messaging apps, the AX tree contains sender names as `AXStaticText` elements with specific roles/subroles
- Walk the AX tree from the focused text input upward to find the conversation container
- Extract unique names from text elements that appear to be message headers/sender labels
- Heuristic: look for repeated patterns like `Name:` or elements with `AXRoleDescription == "heading"` near message content

**Phase 2: Message content extraction**
- Read message content from AX tree elements below sender labels
- Build a chronological message list
- Limit to last 5-10 messages to control prompt size

**Phase 3: Conversation ID tracking**
- Hash the participant list + app + channel name to create a stable conversation ID
- Use this to cache participant names across dictation sessions

### Prompt Integration
New prompt layer `PromptLayers.conversationContext`:

```
<conversation>
Participants: Sarah, Mike, Alan
Recent messages:
- Sarah: Can you review the PR today?
- Mike: Which one?
- Sarah: The context engineering one
</conversation>
```

### Privacy Considerations
- Conversation content never leaves the device unless LLM post-processing is enabled
- When LLM is enabled, conversation context goes to the same API endpoint as screen context
- Add a separate toggle: `llmConversationContextEnabled` (default: off)
- Never cache message content to disk

### Dependencies
- Structured cursor context (section 1) for locating the text input within the conversation
- Persistent vocabulary cache (section 3) for caching participant names

### Complexity
High. AX tree structure varies significantly across messaging apps. Phase 1 (names only) is more tractable than Phase 2 (message content).

---

## 6. ASR Vocabulary Biasing

### Problem
The most impactful context — vocabulary hints — never reaches the ASR model. The ASR transcribes "clawed" when the user said "Claude" because the model has no signal that "Claude" is a likely word in this context. The LLM can fix some of these, but prevention is better than cure.

### Design
Feed extracted vocabulary to the ASR model as a biasing word list, so recognition is steered toward contextually-likely words. Four approaches available, ordered by priority.

### FluidAudio's Existing Custom Vocabulary Infrastructure

Upstream FluidAudio (FluidInference/FluidAudio) already has a sophisticated CTC-based vocabulary boosting pipeline for Parakeet models. This is critical context for our approach:

**What exists (Parakeet only):**
- `CustomVocabularyContext` — define terms with aliases for common misspellings/phonetic variants
- `CtcKeywordSpotter` — spots vocabulary terms in CTC log-probabilities using a DP algorithm (arXiv:2406.07096)
- `VocabularyRescorer` — three-pass algorithm: (1) spot keywords via CTC, (2) align with transcript timestamps, (3) evaluate replacements using acoustic evidence + string similarity guards (Levenshtein, stopword guards, length ratio guards)
- `BKTree` — Burkhard-Keller tree for O(log V) fuzzy string matching on large vocabularies
- `BpeTokenizer` / `CtcTokenizer` — tokenization infrastructure
- `VocabularyBoostingCapable` protocol — being designed for engines that support vocabulary boosting
- Standalone 1MB CTC head — runs on TDT encoder output, 99.4% dictionary recall at 70x RTF

**What does NOT exist:**
- No vocabulary boosting for Qwen3-ASR (the entire pipeline is inside `ASR/Parakeet/SlidingWindow/CustomVocabulary/`)
- No `VocabularyBoostingCapable` conformance for `Qwen3AsrManager`
- No logit-level biasing for autoregressive decoders (Qwen3, Whisper) — the CTC approach is fundamentally different
- No extension/plugin API — FluidAudio is a monolithic Swift package

**Fork divergence concern:** Our fork (`alandotcom/FluidAudio`, `caspi-1.7b-compat` branch) adds Qwen3-ASR/Caspi support. We want to minimize divergence from upstream to keep merging feasible. This strongly favors approaches that work at the Kol layer over approaches that modify FluidAudio internals.

### Approach A: Post-ASR Text Rescoring via FluidAudio's VocabularyRescorer (recommended first step)

Use FluidAudio's existing `VocabularyRescorer` string-matching infrastructure at the **Kol layer**, after Qwen3 transcription completes. No fork changes needed.

**How it works:**
1. Qwen3 produces a transcript (as today)
2. Before sending to LLM post-processing, run `VocabularyRescorer` on the text
3. The rescorer uses string similarity (Levenshtein + guards) to match transcript words against vocabulary terms
4. High-confidence matches are substituted; ambiguous ones are passed to the LLM as hints

**What we lose vs CTC-based rescoring:**
- No acoustic evidence scoring (CTC log-probabilities) — decisions are purely string-based
- No timestamp-based alignment — matching is positional only
- Lower recall for phonetically-distant substitutions (e.g., "in video" → "NVIDIA" relies on string similarity alone)

**What we keep:**
- BK-tree fuzzy matching, stopword guards, length ratio guards, alias support
- All the carefully-tuned thresholds from `ContextBiasingConstants`
- Zero fork divergence

**Implementation:**
```swift
// In Kol's TranscriptionFeature, after transcription, before LLM
let vocabulary = CustomVocabularyContext(terms: extractedVocabulary.map {
    CustomVocabularyTerm(text: $0)
})
let rescored = VocabularyRescorer.rescore(
    transcript: rawTranscription,
    vocabulary: vocabulary
)
```

**Note:** Need to verify that `VocabularyRescorer` can run without CTC scores (text-only mode). If not, we extract the string-matching logic into Kol directly — the algorithms are well-documented in the FluidAudio source.

### Approach B: Prompt-Based Biasing for Qwen3 (low effort, low reward)

Inject hotwords into Qwen3's system message. The model was trained with some contextual biasing data during SFT.

**For Caspi / Qwen3-ASR:**
- `Qwen3AsrManager.buildPromptTokens()` currently builds a hardcoded chat template with only the language task description:
  ```
  <|im_start|>system\nTranscribe the audio to Hebrew text.<|im_end|>
  ```
- **To add biasing:** Modify `buildPromptTokens()` to accept an optional context string, tokenize it, and insert tokens between the task description and `<|im_end|>`:
  ```
  <|im_start|>system\nTranscribe the audio to Hebrew text. Context: Claude, Kol, TranscriptionFeature<|im_end|>
  ```
- **Requires:** Either shipping `merges.txt` for runtime BPE tokenization, or pre-tokenizing terms at the Kol layer using `vocab.json` (already loaded by FluidAudio)
- **Caveat:** Community reports (QwenLM/Qwen3-ASR#62, #106) say the effect on open-source 0.6B/1.7B models is "very minimal." Issue #106 reports context text leaking verbatim into output. The cloud-only Qwen3-ASR-Flash was further SFT'd for this but isn't available as open weights.
- **Fork impact:** Small change to `buildPromptTokens()` signature + tokenizer addition. Moderate divergence.

**For WhisperKit:**
- Already supports `initialPrompt` in `DecodingOptions` — Kol currently ignores this
- Trivial to wire up: pack vocabulary into the prompt string
- Same caveat: Whisper prompt biasing is soft and can hallucinate prompt words

**For Parakeet:**
- Parakeet is CTC-based (non-autoregressive) — prompt biasing doesn't apply
- Upstream's CTC vocabulary boosting is the correct approach (see Approach A)

### Approach C: Trie-Based Logit Biasing in Qwen3 Decode Loop (high effort, high reward)

During autoregressive decoding, boost logits for tokens that are valid continuations of hotwords in a prefix tree (Trie).

**How it works:**
1. Build a token-level Trie from vocabulary (e.g., "Claude" → token sequence `[23840, 2937]`)
2. In each step of `generate()`, check if decoded tokens so far partially match a Trie entry
3. If so, boost logits for next valid continuation tokens: `logits[k] += lambda`
4. The boost parameter `lambda` controls strength (too high = forced substitution, too low = no effect)

**Insertion point in FluidAudio:**
```swift
// Qwen3AsrManager.swift, decode loop (~line 404)
let logits = try runStatefulDecoder(...)
// ← applyTrieBias(logits, decodedTokens: outputTokens, trie: trie, lambda: 5.0)
let tokenId = argmaxFromLogits(logits)  // vDSP_maxvi over 151,936 float values
```

**Key advantages over prompt biasing:**
- No context window pressure (doesn't consume decoder tokens)
- No risk of context leakage into output
- Strength tunable per-word via `lambda`
- Works even if the model wasn't trained with biasing data

**Fork impact:** Significant — new `TokenTrie.swift`, modifications to `Qwen3AsrManager.transcribe()` and the generate loop. High divergence from upstream.

**BPE complication:** A single word can have multiple valid BPE decompositions. The Trie must encode all of them, or use byte-level fallback. FluidAudio's existing `BpeTokenizer` (in `CustomVocabulary/WordSpotting/`) could potentially be reused, but it's built for Parakeet's vocabulary, not Qwen3's 151,936-token vocab.

**Does NOT work for Parakeet** — CTC decoding has no autoregressive step.

**References:**
- LOGIC: Logit-Space Integration for Contextual Biasing (Microsoft, arXiv:2601.15397, Jan 2026) — 9% entity WER reduction, 2.8% latency overhead
- Lightweight Prompt Biasing for Contextualized E2E ASR (arXiv:2506.06252, Jun 2025) — 30.7% entity WER reduction
- Contextual Biasing for LLM-Based ASR with Hotword Retrieval and RL (arXiv:2512.21828, Dec 2025) — 63% KER reduction

### Approach D: LLM Hint Injection (model-agnostic supplement)

Pass vocabulary-aware correction candidates to the LLM post-processing step. Works for all ASR engines.

```
<possible_corrections>
"clawed" might be "Claude" (visible on screen)
"hex" might be "Kol" (app name in context)
</possible_corrections>
```

This is a supplement to Approaches A-C, not a replacement. The LLM can make judgment calls that pure string matching can't (e.g., "clawed code" → "Claude Code" requires semantic understanding). Already partially covered by the existing screen context prompt layer.

### Recommended Sequencing

1. **Approach A** (post-ASR text rescoring) — zero fork divergence, reuses FluidAudio infra, benefits all models
2. **Approach B for WhisperKit** — trivial, just wire up `DecodingOptions.initialPrompt`
3. **Approach D** (LLM hint injection) — enhance existing prompt layers with explicit correction candidates
4. **Approach B for Caspi** — small fork change to `buildPromptTokens()`, test whether it helps
5. **Approach C** (Trie logit biasing) — the real win for Qwen3, but high fork divergence; wait for upstream `VocabularyBoostingCapable` support or implement if needed

### Upstream Trajectory

FluidAudio is actively developing:
- `VocabularyBoostingCapable` protocol for model-agnostic vocabulary support (#434)
- `StreamingAsrEngine` protocol that Qwen3 may eventually conform to (#434)
- CTC head extraction for more efficient vocabulary scoring (#435, #450)

If upstream adds `VocabularyBoostingCapable` to `Qwen3AsrManager`, Approaches B and C become unnecessary fork changes. Worth tracking upstream progress before investing in fork-side logit biasing.

### Dependencies
- Proper noun extraction (section 2) — need vocabulary to bias toward
- Persistent vocabulary cache (section 3) — for cross-dictation continuity
- For Approach A: verify `VocabularyRescorer` works without CTC scores, or extract string-matching logic
- For Approaches B/C: FluidAudio fork modifications (we control the fork)

### Complexity
- Approach A: Low (Kol-layer integration with existing FluidAudio types)
- Approach B: Low (WhisperKit) / Medium (Caspi — fork change + tokenizer)
- Approach C: High (Trie + BPE + logit injection in fork)
- Approach D: Low (prompt layer addition)

---

## 7. Post-Paste Edit Tracking

### Problem
When users correct transcription errors after paste, that information is lost. These corrections are the highest-quality signal for improving prompts, vocabulary, and word remappings — but Kol doesn't observe them.

### Design

```swift
struct EditTracker {
    let pastedText: String
    let editedText: String        // Final text after user edits
    let editVector: String        // "MMSIM" — Match/Substitution/Insert/Delete per word
    let corrections: [Correction] // Extracted word-level substitutions
}

struct Correction {
    let original: String   // What Kol pasted
    let corrected: String  // What the user changed it to
    let type: CorrectionType // .substitution, .insertion, .deletion, .casing
}
```

### Implementation

**Phase 1: Basic edit detection**
- After paste, poll the focused AX text element (e.g., every 500ms for 5 seconds)
- Compare current textbox content with pasted text
- Use the before/after text (from structured cursor context) as anchors to isolate the pasted region
- If the region has changed, compute word-level diff

**Phase 2: Edit vector computation**
- Align original and edited word arrays using edit distance algorithm
- Produce a character-per-word vector: `M`atch, `S`ubstitution, `I`nsert, `D`elete, `C`asing-only
- Store in `TranscriptionHistory` alongside existing metadata

**Phase 3: Auto-learn from corrections**
- Extract single-word substitutions (the highest-confidence corrections)
- If a word is corrected consistently (e.g., "clawed" → "Claude" more than twice), auto-add as a word remapping
- Show suggested remappings in Settings for user approval

**Phase 4: Prompt improvement signal**
- Track aggregate edit vector patterns over time
- If punctuation corrections dominate → tune punctuation prompt layer
- If proper noun corrections dominate → improve vocabulary extraction
- Surface stats in Settings: "X corrections in last 7 days, Y auto-learned words"

### Privacy
- All edit tracking is local-only
- Edit vectors (pattern strings like "MMSM") are safe to include in anonymized telemetry if we add analytics later
- Actual text content never leaves device without explicit consent

### Dependencies
- Structured cursor context (section 1) for before/after anchoring
- Word remappings infrastructure (already exists in Kol)

### Complexity
High. AX polling after paste is fragile — apps update their AX tree at different rates, and the user might switch apps immediately. Phase 1 needs robust timeout/cancellation logic.

---

## 8. Continuous Context Updates

### Problem
Context is captured once at recording start. If the user starts recording, then scrolls or switches context, the captured text is stale. For short dictations this rarely matters, but for longer recordings or when the user glances at reference material, fresh context could help.

### Design
Refresh context periodically during recording, making the latest snapshot available to LLM post-processing.

### Implementation

**Approach: Background AX polling during recording**
- On recording start: capture initial context (as today)
- Start a background timer (e.g., every 1 second) that re-captures visible text
- On recording stop: use the most recent context snapshot for LLM post-processing
- Cancel timer on stop/cancel

**Considerations:**
- AX calls are main-thread-only on macOS — must be careful not to block UI
- AX calls can be slow (10-100ms) depending on app complexity
- Only update if the focused element or app has changed (use `AXUIElementGetPid` + element identity)
- Rate-limit: don't poll more than once per second

**State management:**
```swift
// In TranscriptionFeature.State
var capturedScreenContext: String?           // Most recent snapshot
var contextUpdateCount: Int = 0             // For analytics
var lastContextCaptureTime: Date?
```

### Dependencies
- None — works with existing infrastructure
- Benefits from structured cursor context (section 1)

### Complexity
Medium. Timer management and main-thread coordination are the main challenges.

---

## 9. OCR as Parallel Context Path

### Problem
AX APIs can't see text rendered as images, canvas-drawn text, PDF content in some viewers, or text in apps with poor accessibility support. These are common in design tools, PDF readers, and some web apps.

### Design
Capture a screenshot and run OCR to extract text that AX can't reach.

### Implementation

**Phase 1: On-device OCR via Vision framework**
- Use `VNRecognizeTextRequest` (available macOS 10.15+) for on-device text recognition
- Capture screenshot of the focused window via `CGWindowListCreateImage`
- Run OCR asynchronously at recording start, alongside AX capture
- Merge OCR results with AX results, deduplicating overlapping text

**Phase 2: Targeted OCR**
- Instead of full-screen OCR, capture only the area around the cursor
- Use AX position data to determine the region of interest
- Reduces OCR time and noise from irrelevant screen regions

### Prompt Integration
OCR-extracted vocabulary is added to the same vocabulary hints section as AX-extracted vocabulary. No separate prompt layer needed.

### Performance
- `VNRecognizeTextRequest` with `.fast` recognition level: ~50-100ms for a window screenshot
- `.accurate` level: ~200-500ms (probably too slow for recording start)
- Run async and race with recording — if OCR finishes before transcription, include results

### Dependencies
- None — parallel to AX pipeline
- Proper noun extraction (section 2) can process OCR text as additional input

### Complexity
Medium. Vision framework API is well-documented. Main challenge is performance tuning and dedup with AX text.

---

## 10. App-Specific Context Adapters

### Problem
Different app categories expose context differently. A one-size-fits-all AX walker misses app-specific signals (e.g., Slack channel names, Xcode build errors, browser URL context).

### Design
Pluggable context adapters per app category:

```swift
protocol AppContextAdapter {
    static var supportedApps: [String] { get }  // Bundle IDs
    func captureContext(from element: AXUIElement) -> AppSpecificContext
}

struct AppSpecificContext {
    let vocabulary: [String]
    let metadata: [String: String]  // e.g., "channel": "#engineering"
    let conversationParticipants: [String]?
}
```

### Implementation

**SlackAdapter:**
- Extract channel name from window title or AX tree
- Extract participant names from message headers
- Cache names per channel

**XcodeAdapter:**
- Extract file name from navigator or tab bar
- Extract build errors/warnings from Issue Navigator
- Extract symbol names from the current scope

**BrowserAdapter:**
- Extract page title and URL from AX window title
- Use URL to determine sub-context (e.g., `docs.google.com` → document mode, `mail.google.com` → email mode)
- Walk `AXWebArea` subtree to extract visible page content (headings, static text, links) for vocabulary and surrounding context
- Use role filters (`AXHeading`, `AXStaticText`, `AXLink`) to prioritize content near the focused element

**TerminalAdapter:**
- Extract recent command output (last N lines)
- Detect current directory from prompt line
- Extract command history for identifier vocabulary

### Dependencies
- Structured cursor context (section 1)
- Conversation awareness (section 5) for messaging adapters

### Complexity
High overall, but each adapter is independent and can be built incrementally. Start with the apps users dictate in most.

---

## Implementation Status

### Phase A — in progress

**§0 AXorcist — done (dependency only)**
- AXorcist added as SPM dependency to the Kol target
- ScreenContextClient internals NOT yet migrated — still uses raw `AXUIElement` C API
- Migration deferred to when a feature actually needs AXorcist's query/observation APIs

**§1 Structured Cursor Context — done**
- `CursorContext` model in `KolCore/CursorContext.swift` — `beforeCursor`, `afterCursor`, `selectedText`, `isTerminal`, `flatText`
- `ScreenContextClient.captureCursorContext()` — new method using raw AX API, splits text at cursor position, applies 1500-char windowing per side, word-boundary truncation
- `PromptLayers.structuredScreenContext()` — new prompt layer with `--- BEFORE CURSOR ---` / `--- AFTER CURSOR ---` / `--- SELECTED TEXT ---` sections
- `PromptAssembler.systemPrompt()` — prefers structured context over flat `screenContext` when available; falls back gracefully
- `TranscriptionFeature.handleStartRecording()` — captures structured context, stores in `state.capturedCursorContext`
- Eval prompt `evals/prompts/english-code-screen.txt` updated to structured format
- 9 new PromptAssemblerTests covering structured context and fallback

**§2 Proper Noun & Identifier Extraction (Option A) — done**
- `VocabularyExtractor` in `KolCore/VocabularyExtractor.swift` — pure enum, regex-based, no network
- Patterns: camelCase, PascalCase, snake_case identifiers; multi-word proper nouns; file names with known extensions
- Capped at 50 terms, deduplicated case-insensitively
- `PromptLayers.vocabularyHints()` — new prompt layer: "Names and identifiers visible on screen: ..."
- Layer ordering: core → language → app context → screen context → vocabulary hints → custom rules
- 13 VocabularyExtractorTests (camelCase, PascalCase, snake_case, proper nouns, file names, dedup, cap, edge cases)

**§3 Persistent Vocabulary Cache — done**
- `VocabularyCacheClient` in `KolCore/VocabularyCache.swift` — TCA `@DependencyClient` with `merge`/`topTerms`/`clear`
- Backed by `NSLock`-protected LRU cache (max 200 entries), sorted by frequency then recency
- In-memory only (no disk persistence), rebuilds from screen context captures each session
- Integrated in `TranscriptionFeature.handleStartRecording()` — extracts vocabulary, merges into cache, passes top 30 terms to prompt
- 5 VocabularyCacheTests (merge, frequency ordering, limit, clear, case-insensitive dedup)

**No new settings added.** Vocabulary extraction piggybacks on existing `llmPostProcessingEnabled && llmScreenContextEnabled` gates.

### Architecture changes

**KolCore framework target** — extracted from the app target to fix test infrastructure:
- Native Xcode framework target (not SPM package — avoids the slow incremental builds that the original Hex SPM package had)
- Contains: models (LLMPostProcessing, CursorContext, HotKey, KeyEvent, KolSettings, WordRemapping, WordRemoval, TranscriptionHistory, ParakeetModel, QwenModel), logic (HotKeyProcessor, VocabularyExtractor, VocabularyCache, RecordingDecision), shared infra (Logging, Constants)
- Dependencies: ComposableArchitecture, Dependencies, DependenciesMacros, Sauce + TCA transitive deps
- App target uses `@_exported import KolCore` — no import changes needed in app source files
- Test target imports `@testable import KolCore` directly — no host app needed, no debug dylib linker issues

**Test target restructured:**
- Removed `BUNDLE_LOADER`/`TEST_HOST` — tests are non-hosted, link KolCore framework directly
- Fixed `PRODUCT_NAME = Kol` (was "Kol Debug"), fixed `DEVELOPMENT_TEAM`
- 69 tests pass via `xcodebuild test` CLI
- `HotKeyProcessorTests` disabled — crashes in non-hosted context (uses `withDependencies` which needs investigation)
- `RecordingRaceTests` disabled — needs hosted test for `TranscriptionFeature` (uses `TestStore`)

### Phase B — done

**§6A Post-ASR Text Rescoring — tried and removed**
- Ported FluidAudio's `VocabularyRescorer` (Levenshtein similarity, stopword/length guards, compound matching) as `TextRescorer` in KolCore.
- **Removed from codebase.** Testing showed that string-similarity rescoring produces too many false positives in practice (e.g. "Cloudflare proxy" matched to "Claude Max"). The vocabulary hints to the LLM are sufficient — the LLM can make semantic judgments that pure string matching cannot.
- **Lesson learned:** Pre-LLM text manipulation is risky. The LLM already handles vocabulary-aware correction well when given screen context and vocabulary hints. Adding a second correction layer before it introduces compounding errors.

**§6B WhisperKit Prompt Token Biasing — done**
- `TranscriptionClient.transcribe` extended with optional `vocabularyHints: [String]?` parameter
- WhisperKit path encodes vocabulary as prompt tokens via `whisperKit.tokenizer.encode()`, filtered for special tokens
- Sets `DecodingOptions.promptTokens` and `usePrefillPrompt = true` when vocabulary available
- Parakeet and Qwen paths pass through unaffected (CTC/autoregressive biasing N/A)
- `TranscriptionFeature.handleStopRecording()` passes `capturedVocabulary` to transcription call

**§6C LLM Correction Hints — tried and removed**
- Built `PromptLayers.correctionHints()` and `PostProcessingContext.correctionHints` field to pass TextRescorer matches to the LLM.
- **Removed from codebase** along with TextRescorer. Correction hints fed TextRescorer false positives directly to the LLM (e.g. `"Cloudflare proxy" might be "Claude Max"`), which the LLM then applied as corrections.
- **Lesson learned:** Presenting "X might be Y" to an instruction-following LLM is effectively telling it to do the replacement. The correction hints format is too authoritative for low-confidence matches.

**§8 Continuous Context Updates — done**
- 1-second timer effect during recording, gated by `llmPostProcessingEnabled && llmScreenContextEnabled`
- New actions: `contextRefreshTick` (fires timer), `contextRefreshed` (updates state with fresh context)
- AX calls dispatched to main thread via `MainActor.run { ... }`
- Re-extracts vocabulary, merges into cache, updates `capturedVocabulary` with latest terms
- Timer cancelled in `handleStopRecording`, `handleCancel`, `handleDiscard` via `CancelID.contextRefresh`
- `state.contextUpdateCount` tracks refresh count per recording (logged on stop)

**§4 IDE-Specific Context (Phase 1) — done**
- `IDEContext` model in `KolCore/IDEContext.swift` — `openFileNames`, `detectedLanguage` (auto-detected from file extensions)
- `IDEContextClient` in `Kol/Clients/IDEContextClient.swift` — raw AX API (same approach as ScreenContextClient), walks window AX tree for tab-like elements (AXRadioButton, AXTab), filters by `looksLikeFileName` heuristic
- `PromptLayers.ideContext()` — new prompt layer: "Open files: ... \nLanguage: Swift"
- Integrated in `handleStartRecording()` for code editors (detected via `appContextCategory == .code`)
- Tab file names merged into vocabulary cache for ASR biasing
- 7 IDEContextTests (language detection from extensions, auto-detect in init, edge cases)

**Prompt changes:**
- Core prompt: added "Do NOT rephrase, restructure, or reword sentences" rule to prevent LLM paraphrasing
- Vocabulary hints: changed wording from "use their exact spelling and casing when they match spoken words" to "use their exact spelling and casing when they appear in the transcription" — less aggressive matching instruction
- Layer ordering: core → language → app context → IDE context → screen context → vocabulary hints → custom rules

**No new settings added.** All Phase B features piggyback on existing gates (`llmPostProcessingEnabled`, `llmScreenContextEnabled`).

### Remaining work

- **AXorcist migration** — ScreenContextClient and IDEContextClient both use raw `AXUIElement` C API. AXorcist is an SPM dependency but not yet imported. Migration deferred to when observation APIs (§8 real-time AX notifications) are needed.
- **IDE tab AX tree tuning** — IDEContextClient's tab extraction heuristic needs verification per editor (VS Code, Cursor, Xcode, Zed) via Accessibility Inspector
- **RecordingRaceTests** — disabled, needs hosted test target. Low priority.
- **Manual smoke test** — debug build, dictate in VS Code/Terminal/Slack/Notes, verify continuous context and IDE context in logs

---

## Priority & Sequencing

### Phase A — Foundation (low complexity, high impact)
1. **Structured cursor context** (section 1)
2. **Proper noun extraction — local regex** (section 2, Option A)
3. **Persistent vocabulary cache** (section 3)

### Phase B — Intelligence (medium complexity, high impact)
4. **ASR vocabulary biasing** (section 6) — start with post-ASR text rescoring via FluidAudio's VocabularyRescorer (no fork changes), then WhisperKit initialPrompt, then LLM hint injection, then evaluate fork changes only if upstream doesn't add VocabularyBoostingCapable for Qwen3
5. **Continuous context updates** (section 8)
6. **IDE-specific context** (section 4, Phase 1)

### Phase C — Advanced (high complexity, medium impact)
7. **Post-paste edit tracking** (section 7, Phases 1-2)
8. **On-device OCR** (section 9, Phase 1)
9. **Conversation awareness** (section 5, Phase 1 — names only)

### Phase D — Polish & Integration
10. **App-specific adapters** (section 10) — build per-app as needed
11. **Auto-learn from corrections** (section 7, Phases 3-4)
12. **LLM-assisted extraction** (section 2, Option B)
13. **Conversation message extraction** (section 5, Phase 2)

---

## Settings & Privacy Model

All new context features should follow this pattern:

| Feature | Setting | Default | Gated by |
|---------|---------|---------|----------|
| Structured cursor context | (none — replaces existing) | on | `llmScreenContextEnabled` |
| Vocabulary extraction | `vocabularyExtractionEnabled` | on | `llmPostProcessingEnabled` |
| Vocabulary cache | (none — passive) | on | vocabulary extraction |
| ASR biasing | `asrVocabularyBiasingEnabled` | on | vocabulary extraction |
| Continuous updates | `continuousContextEnabled` | on | `llmScreenContextEnabled` |
| Edit tracking | `editTrackingEnabled` | off | (independent) |
| Auto-learn words | `autoLearnFromEditsEnabled` | off | edit tracking |
| Conversation context | `conversationContextEnabled` | off | `llmPostProcessingEnabled` |
| OCR context | `ocrContextEnabled` | off | `llmPostProcessingEnabled` |

Privacy invariant: **No context data leaves the device unless `llmPostProcessingEnabled` is on.** ASR biasing, vocabulary caching, and edit tracking are purely local.

---

## Verification

### Per-feature testing
- Unit tests for vocabulary extraction regex patterns
- Unit tests for structured cursor context parsing (before/after split)
- Unit tests for edit vector computation
- `PromptAssemblerTests` extended for new prompt sections

### Integration testing
- Build debug, dictate in each app category, verify prompt content via LLM debug logging
- Compare transcription accuracy with/without vocabulary hints (manual A/B)
- Verify edit tracking by dictating, making corrections, checking stored edit vectors

### Eval suite
- Add eval cases for proper noun preservation with vocabulary hints
- Add eval cases for cursor-aware formatting (e.g., continuing a sentence vs starting new)
- Add eval cases for conversation-aware tone matching
