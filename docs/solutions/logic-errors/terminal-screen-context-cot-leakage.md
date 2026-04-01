---
title: "Terminal screen context noise causes LLM chain-of-thought leakage in dictation output"
date: "2026-03-31"
category: logic-errors
module: ScreenContext
problem_type: logic_error
component: tooling
severity: high
symptoms:
  - "LLM outputs step-by-step reasoning with arrow mappings instead of cleaned transcription"
  - "Terminal AX context returns ~1500 tokens of rendered TUI layout noise"
  - "Code context prompt arrow examples mimicked by model in output"
  - "Only occurs when dictating into terminal applications (Ghostty, Terminal.app, iTerm2)"
root_cause: config_error
resolution_type: code_fix
tags:
  - screen-context
  - terminal
  - chain-of-thought
  - llm-prompt
  - context-engineering
  - vocabulary
---

# Terminal screen context noise causes LLM chain-of-thought leakage in dictation output

## Problem

When dictating into a terminal emulator (Ghostty running Claude Code), the LLM post-processor leaked its chain-of-thought reasoning into the output, producing multi-line word-by-word mapping traces instead of the final transcription text. Prompt token count was inflated (~1,875 tokens) due to terminal screen context noise.

## Symptoms

- LLM output contained intermediate reasoning steps with arrow notation (`cole -> Kol`, `features -> Features`, `So the final answer is...`) instead of just the cleaned text
- Only occurred when dictating into terminal applications
- Prompt token count inflated to ~1,875 (normal for terminals should be ~1,000)
- The `screenContext` prompt section contained rendered TUI output: build results, menu options, whitespace-padded columns, tmux status bars

## What Didn't Work

- **Anti-COT prompt instruction alone**: Added "Do NOT show your reasoning" to `PromptLayers.core`. Necessary but not sufficient — the ~1500 tokens of terminal noise still overwhelmed the model into reasoning out loud.
- **CharacterSet-based TUI chrome filter**: Attempted to strip Unicode box-drawing characters (U+2500-U+257F) and status indicators from terminal text. Failed because terminal AX APIs return *rendered* text content where box-drawing characters are already converted to spaces as padding — no Unicode box-drawing characters left to filter.
- **Unified log verification**: Tried `log show`/`log stream` to inspect the actual prompt. Couldn't get unified logging working from Claude Code's terminal sandbox. Workaround: temporary file dump to `/tmp/kol-last-prompt.txt` and inspection of transcription history JSON.

## Solution

Four coordinated changes:

### 1. Skip AX screen context for terminals

Terminal AX text is fundamentally different from GUI app text — it contains rendered TUI chrome that is useless as dictation context. OCR-based vocabulary extraction already provides useful identifiers.

`ScreenContextClient.swift` — return nil for terminals:
```swift
if isTerminal {
    return nil
}
```

`TranscriptionFeature.swift` — skip in both initial capture and 1-second refresh tick:
```swift
} else if !PromptLayers.isTerminal(state.sourceAppBundleID) {
    state.capturedScreenContext = screenContext.captureVisibleText(state.sourceAppBundleID)
} else {
    state.capturedScreenContext = nil
}
```

### 2. Anti-COT prompt instruction

Added to `PromptLayers.core` and synced to all 9 eval prompt files:
```
- Do NOT show your reasoning, intermediate steps, or word-by-word mappings.
  Never use arrows (→, ->) to show how you converted words.
```

### 3. Inject source app name into vocabulary hints

After removing screen context, single-word app names like "Ghostty" were no longer discoverable — the `VocabularyExtractor` only catches camelCase, PascalCase, snake_case, multi-word proper nouns, and file names.

`TranscriptionFeature.swift`:
```swift
var capturedVocabulary = vocabularyCache.topTerms(maxVocabularyHints)
if let appName = state.sourceAppName, !appName.isEmpty,
   !(capturedVocabulary ?? []).contains(appName) {
    capturedVocabulary = (capturedVocabulary ?? []) + [appName]
}
```

### 4. Simplified appContextCode prompt

Removed verbose operator/syntax rule listings that used arrow notation (`"equals" → =`) and replaced with concrete input/output examples. This eliminated the arrow format the model was mimicking and reduced prompt token usage.

## Why This Works

The root cause was compound: (1) terminal AX text contains rendered TUI layout — whitespace-padded columns, status bars, CLI output — that is noise for dictation cleanup, consuming ~1500 tokens; (2) the `appContextCode` prompt used arrow notation for conversion rules, which the model latched onto when confused by noisy context.

Two separate context pipelines exist: AX-based screen context (raw text near cursor) and OCR-based vocabulary extraction (identifiers, proper nouns, file names). For terminals, the AX pipeline produces only noise while the OCR pipeline produces useful signal. Skipping AX for terminals and relying on OCR vocabulary reduced prompt tokens from 1,875 to 1,017 (46% reduction) while improving output quality.

## Prevention

- **Context sources should be classified by app category**: Terminal apps should only receive OCR-based vocabulary extraction, never raw AX screen text. When adding new context sources, evaluate which app categories benefit vs. suffer from each source.
- **Avoid output-format-like notation in prompts**: Arrow notation, tables, or step-by-step formatting in system prompts can leak into model output. Use concrete input/output examples instead of conversion rule listings.
- **Monitor prompt token budgets**: The transcription history JSON stores prompt token counts. Unusually high counts signal a noisy context source (expected: ~1,000 for terminals, ~1,500 for GUI apps with screen context).
- **Add eval cases for terminal dictation**: Test cases with noisy screen context catch COT leakage regressions.

## Related Issues

- `docs/solutions/integration-issues/ocr-vocabulary-extraction-electron-apps.md` — sibling solution applying the same "vocabulary over raw text" principle to Electron apps where AX returns too little text
- `docs/context-engineering.md` — the `TerminalAdapter` section (line ~859) envisioned extracting commands/paths from terminal AX text; this fix takes a different approach (skip AX entirely, rely on OCR vocabulary)
