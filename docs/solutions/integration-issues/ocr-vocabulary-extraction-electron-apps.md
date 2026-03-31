---
title: "OCR-based vocabulary extraction for Electron/Chromium apps"
date: "2026-03-31"
category: integration-issues
module: ScreenContext
problem_type: integration_issue
component: tooling
severity: medium
symptoms:
  - "AX text < 50 chars from Electron apps (Slack, Discord, Teams, browsers)"
  - "LLM vocabulary hints missing proper nouns visible on screen"
  - "OCR .fast garbles names (Aron Soltsman instead of Aaron Saltzman)"
  - "Single-word noun extraction produces too many false positives"
root_cause: missing_include
resolution_type: code_fix
tags:
  - ocr
  - screencapturekit
  - vision
  - vocabulary
  - electron
  - accessibility
  - context-engineering
---

# OCR-based vocabulary extraction for Electron/Chromium apps

## Problem

Electron/Chromium apps (Slack, Discord, Teams, browsers) expose zero message content via the macOS Accessibility API. The `AXWebArea` reports `AXNumberOfCharacters = 0`. AX only captures 7-37 chars from the focused text input field, while native apps like iMessage expose 500+ chars. This means the vocabulary extraction pipeline gets almost no proper nouns to feed the ASR model and LLM for these apps.

## Symptoms

- `ScreenContextClient` returns 7-37 chars from Slack (placeholder text, input field content)
- `VocabularyExtractor` finds 0 terms from the sparse AX text
- LLM post-processing receives no vocabulary hints for name spelling
- ASR transcribes "clawed" instead of "Claude" because no biasing vocabulary is available

## What Didn't Work

- **Vision `.fast` recognition**: Garbles names badly. "Aaron Saltzman" becomes "Aron Soltsman", "Omar Agely" becomes "Omar Agelw". The vocabulary is supposed to help ASR spell names correctly -- garbled names actively hurt.
- **Single-word proper noun extraction from OCR**: Picks up every capitalized word including sentence-start words ("It", "Want", "Thoughts", "Insane"). The UI word blocklist approach doesn't scale -- too many common English words appear capitalized at sentence start in messaging apps.
- **Feeding raw OCR text to LLM screen context**: Considered but rejected. The vocabulary cache (proper nouns, identifiers) is the high-value signal. Raw OCR text from messaging apps is noisy with UI chrome, timestamps, and message fragments that don't help the LLM.
- **Waiting for OCR result at stop time**: Initially implemented a 500ms timeout in `handleStopRecording` to ensure the LLM gets OCR vocabulary. Removed in favor of reading vocabulary from the persistent cache directly in `handleTranscriptionResult`.

## Solution

### Architecture: OCR feeds vocabulary cache only

OCR text is not used as LLM screen context. Instead, OCR extracts proper nouns and identifiers via `VocabularyExtractor`, which merges them into `VocabularyCacheClient`. The cache persists across recordings, so the second recording in the same app gets vocabulary instantly.

```
Recording start → AX capture (7-37 chars for Electron apps)
                → Quality gate: < 50 chars? → OCR fires async
                → OCR: ScreenCaptureKit screenshot + Vision .accurate
                → VocabularyExtractor → VocabularyCacheClient (persistent)

Recording stop  → handleTranscriptionResult reads vocabulary from cache
                → LLM gets vocabulary hints via PromptLayers.vocabularyHints()
                → WhisperKit gets prompt tokens for ASR biasing
```

### Key implementation decisions

1. **Vision `.accurate` not `.fast`**: 300-500ms vs 150ms, but correct name spelling is the whole point. OCR runs every ~3s (cooldown), not on the hot path.

2. **Multi-word proper nouns only**: `properNounRegex` requires 2+ capitalized words (`\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b`). Single-word extraction was tried and removed -- too noisy for messaging contexts.

3. **Garbage filter**: `looksLikeGarbage` rejects OCR misreads with <15% vowel ratio or 5+ consecutive lowercase consonants. Catches `dlsc0LntiWti`, `IrnplerrwtstiDn` while accepting real names and camelCase identifiers.

4. **Vocabulary cache is the bridge**: OCR terms persist in `VocabularyCacheClient` (in-memory LRU, frequency+recency sorted). `handleTranscriptionResult` reads from cache at line 873, not from state -- this captures OCR terms even when OCR completes after transcription starts.

5. **Quality gate at 50 chars**: OCR only fires when AX text is sparse. Native apps (iMessage: 500+ chars, VS Code: full file content) never trigger OCR. The threshold is checked at recording start and on each context refresh tick.

## Why This Works

Electron/Chromium apps render content via GPU compositing, making it invisible to AX. OCR is the only way to read screen content for these apps. By extracting just the vocabulary (proper nouns, identifiers) rather than using raw OCR text, we get the high-value signal (name spelling for ASR biasing) without the noise (UI chrome, timestamps, message fragments).

The vocabulary cache bridges the timing gap between async OCR completion and synchronous state reads. On the first recording, OCR may complete after the LLM runs, but the vocabulary cache is populated for all subsequent recordings.

## Prevention

- When adding new context sources, feed vocabulary extraction (not raw text) to the LLM pipeline. Vocabulary is the high-value, low-noise signal.
- Use Vision `.accurate` for any OCR that feeds vocabulary -- name spelling accuracy matters more than speed.
- Apply `looksLikeGarbage` filter to all vocabulary extraction, not just OCR. OCR misreads are the most common source of garbage, but AX can produce noise too.
- Test vocabulary extraction with real Electron apps (Slack, Discord) -- the AX tree structure varies significantly between native and Electron apps.

## Related Issues

- `docs/context-engineering.md` section 9 -- OCR design document
- `docs/solutions/build-errors/spm-c-module-transitive-dependency-non-hosted-tests.md` -- test infrastructure fix done alongside this work
