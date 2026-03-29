# Kol – Dev Notes for Agents

This file provides guidance for coding agents working in this repo.

## Project Overview

Kol (קול, Hebrew for "voice") is a macOS menu bar application for on‑device voice‑to‑text. This is a fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) with added Hebrew ASR and LLM post-processing. It supports Whisper (Core ML via WhisperKit), Parakeet TDT v3 (Core ML via FluidAudio), and Caspi 1.7B (Hebrew, Core ML via Qwen3-ASR). Users activate transcription with hotkeys; text can be auto‑pasted into the active app.

## Fork-Specific Features

### Caspi 1.7B Hebrew ASR
- **Model**: [alandotcom/caspi-1.7b-coreml](https://huggingface.co/alandotcom/caspi-1.7b-coreml) — Hebrew fine-tune of Qwen3-ASR-1.7B
- **FluidAudio fork**: [alandotcom/FluidAudio](https://github.com/alandotcom/FluidAudio/tree/caspi-1.7b-compat) — adds Qwen3-ASR 1.7B config + Caspi repo
- **Conversion scripts**: [alandotcom/caspi-hebrew-asr](https://github.com/alandotcom/caspi-hebrew-asr) — CoreML conversion from PyTorch
- **Key files**: `QwenModel.swift`, `QwenClient.swift`
- **Model dispatch**: `TranscriptionClient.isQwen()` routes to `QwenClient`, same pattern as `isParakeet()`

### Automatic Language Switching
- Checks macOS keyboard input source via `TISCopyCurrentKeyboardInputSource()` (Carbon)
- Hebrew keyboard → Caspi model + `language: "he"`
- Any other keyboard → Parakeet (fast English/multilingual)
- Logic in `TranscriptionFeature.resolveModelAndLanguage()`

### LLM Post-Processing
- Optional cleanup of transcriptions via OpenAI-compatible API (Groq, Cerebras, or custom)
- **Composable prompt architecture** — NOT a monolithic system prompt:
  - `PromptLayers.core` — always present (punctuation, filler removal)
  - `PromptLayers.hebrew` / `.english` — language-specific, selected based on detected language
  - `PromptLayers.appContextCode` / `.appContextMessaging` / `.appContextDocument` — adapts to target app
  - `PromptLayers.screenContext(visibleText:)` — opt-in, captures text near cursor via Accessibility API
  - Custom rules — user-provided facts (name, company, common terms)
  - `PromptAssembler.systemPrompt()` composes applicable layers in order: core → language → app context → screen context → custom rules
- **Key files**: `LLMPostProcessing.swift` (KolCore), `LLMPostProcessingClient.swift`, `ScreenContextClient.swift`, `KeychainClient.swift`, `LLMSectionView.swift`
- **Insertion point**: `TranscriptionFeature.handleTranscriptionResult()`, after word removals/remappings, before `finalizeRecordingAndStoreTranscript()`
- **Screen context capture**: `ScreenContextClient` uses AX APIs at recording start (synchronous). State stored in `TranscriptionFeature.State.capturedScreenContext`, cleared on cancel/discard.
- **Graceful fallback**: on any LLM error, original text is pasted
- **API key**: stored in macOS Keychain via `KeychainClient`, NOT in settings JSON
- **Tests**: `PromptAssemblerTests.swift` for prompt composition
- **Evals**: promptfoo-based eval suite — see Eval Workflow section below

### Prompt change workflow

When modifying any prompt in `LLMPostProcessing.swift`:

1. **Update the eval prompt files** — `evals/prompts/*.txt` are static copies of the assembled system prompts. They must be kept in sync manually. If you change `appContextCode`, update `evals/prompts/english-code.txt` and `evals/prompts/english-code-screen.txt`.
2. **Run evals before building** — see Eval Workflow below.
3. **Run unit tests** — `cd KolCore && swift test`
4. **Then build** — `killall Kol 2>/dev/null; ./scripts/build-install.sh`

## Build & Development Commands

```bash
# Build + sign + install (the only command you need)
killall Kol 2>/dev/null; ./scripts/build-install.sh

# Run tests (must be run from KolCore directory for unit tests)
cd KolCore && swift test

# Open in Xcode (recommended for development)
open Kol.xcodeproj
```

### Build rules for agents

- **Always use `./scripts/build-install.sh`** — it handles xcodebuild, codesign, and rsync. Do NOT run `xcodebuild` manually.
- **Always `killall Kol` before installing** — the old process must be killed so the new binary is loaded. Without this, the user will test stale code.
- **After installing, run `open /Applications/Kol.app`** to relaunch.
- **KolCore cache auto-invalidation** — `build-install.sh` automatically detects when KolCore sources have changed and selectively cleans only KolCore build artifacts (~21MB) instead of all DerivedData (~330MB). You no longer need to manually delete DerivedData. Just run:
  ```bash
  killall Kol 2>/dev/null; ./scripts/build-install.sh
  ```
- **Xcode uses file system synchronization** (`PBXFileSystemSynchronizedRootGroup`) — new `.swift` files added to the `Kol/` directory are automatically included in the build. No need to edit the `.xcodeproj` file.
- **Check for build failures** — the script prints "(N failures)" if there are errors. If you see failures, grep the build output for `error:` before proceeding. Do NOT sign and install a broken build.

**Signing note**: Use `codesign` post-build with a stable identity so macOS permissions (accessibility, input monitoring, microphone) persist between installs. Ad-hoc signing (`-`) resets permissions every build.

## Architecture

The app uses **The Composable Architecture (TCA)** for state management. Key architectural components:

### Features (TCA Reducers)
- `AppFeature`: Root feature coordinating the app lifecycle
- `TranscriptionFeature`: Core recording and transcription logic
- `SettingsFeature`: User preferences and configuration
- `HistoryFeature`: Transcription history management

### Dependency Clients
- `TranscriptionClient`: Routes to WhisperKit, ParakeetClient, or QwenClient based on model
- `ParakeetClient`: FluidAudio ASR for Parakeet models
- `QwenClient`: FluidAudio Qwen3AsrManager for Caspi Hebrew model
- `LLMPostProcessingClient`: OpenAI-compatible API for transcription cleanup
- `ScreenContextClient`: Captures focused text field content via macOS Accessibility API for LLM context
- `KeychainClient`: macOS Keychain for API key storage
- `RecordingClient`: AVAudioRecorder wrapper for audio capture
- `PasteboardClient`: Clipboard operations
- `KeyEventMonitorClient`: Global hotkey monitoring via Sauce framework

### Key Dependencies
- **WhisperKit**: Core ML transcription (tracking main branch)
- **FluidAudio**: Core ML ASR — Parakeet (multilingual) + Qwen3-ASR/Caspi (Hebrew). Uses [alandotcom/FluidAudio](https://github.com/alandotcom/FluidAudio) fork (`caspi-1.7b-compat` branch)
- **Sauce**: Keyboard event monitoring
- **Sparkle**: Auto-updates (feed: https://hex-updates.s3.amazonaws.com/appcast.xml)
- **Swift Composable Architecture**: State management
- **Inject**: Hot Reloading for SwiftUI

## Important Implementation Details

1. **Hotkey Recording Modes**: The app supports both press-and-hold and double-tap recording modes, implemented in `HotKeyProcessor.swift`. See `docs/hotkey-semantics.md` for detailed behavior specifications including:
   - **Modifier-only hotkeys** (e.g., Option) use a **0.3s threshold** to prevent accidental triggers from OS shortcuts
   - **Regular hotkeys** (e.g., Cmd+A) use user's `minimumKeyTime` setting (default 0.2s)
   - Mouse clicks and extra modifiers are discarded within threshold, ignored after
   - Only ESC cancels recordings after the threshold

2. **Model Management**: Models are managed by `ModelDownloadFeature`. Curated defaults live in `Kol/Resources/Data/models.json`. The Settings UI shows Parakeet, Caspi, and Whisper models. Caspi auto-downloads from HuggingFace on first use.

3. **Sound Effects**: Audio feedback is provided via `SoundEffect.swift` using files in `Resources/Audio/`

4. **Window Management**: Uses an `InvisibleWindow` for the transcription indicator overlay

5. **Permissions**: Requires audio input and automation entitlements (see `Kol.entitlements`)

6. **Logging**: All diagnostics should use the unified logging helper `KolLog` (`KolCore/Sources/KolCore/Logging.swift`). Pick an existing category (e.g., `.transcription`, `.recording`, `.settings`) or add a new case so Console predicates stay consistent. Avoid `print` and prefer privacy annotations (`, privacy: .private`) for anything potentially sensitive like transcript text or file paths.

## Models

- Default: Parakeet TDT v3 (multilingual, ~650MB) via FluidAudio
- **Caspi 1.7B** (Hebrew, ~2.8GB int8) via FluidAudio Qwen3AsrManager — auto-downloads from [HuggingFace](https://huggingface.co/alandotcom/caspi-1.7b-coreml)
- Whisper Small (Tiny), Whisper Medium (Base), Whisper Large v3
- Note: Distil‑Whisper is English‑only and not shown by default
- Model dispatch: `TranscriptionClient` checks `isParakeet()` then `isQwen()` then falls through to WhisperKit

### Storage Locations

- WhisperKit models
  - `~/Library/Application Support/com.alandotcom.Kol/models/argmaxinc/whisperkit-coreml/<model>`
- Parakeet (FluidAudio)
  - We set `XDG_CACHE_HOME` on launch so Parakeet caches under the app container:
  - `~/Library/Containers/com.alandotcom.Kol/Data/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml`
  - Legacy `~/.cache/fluidaudio/Models/…` is not visible to the sandbox; re‑download or import.

### Progress + Availability

- WhisperKit: native progress
- Parakeet: best‑effort progress by polling the model directory size during download
- Availability detection scans both `Application Support/FluidAudio/Models` and our app cache path

## Building & Running

- macOS 14+, Xcode 15+

### Packages

- WhisperKit: `https://github.com/argmaxinc/WhisperKit`
- FluidAudio: `https://github.com/alandotcom/FluidAudio.git` branch `caspi-1.7b-compat` (fork with Qwen3-ASR 1.7B support)

### Entitlements (Sandbox)

- `com.apple.security.app-sandbox = true`
- `com.apple.security.network.client = true` (HF downloads)
- `com.apple.security.files.user-selected.read-write = true` (optional import)
- `com.apple.security.automation.apple-events = true` (media control)

### Cache root (Parakeet)

Set at app launch and logged:

```
XDG_CACHE_HOME = ~/Library/Containers/com.alandotcom.Kol/Data/Library/Application Support/com.alandotcom.Kol/cache
```

FluidAudio models reside under `Application Support/FluidAudio/Models`.

## UI

- Settings → Transcription Model shows a compact list with radio selection, accuracy/speed dots, size on right, and trailing menu / download‑check icon.
- Context menu offers Show in Finder / Delete.

## Troubleshooting

- Repeated mic prompts during debug: ensure Debug signing uses "Apple Development" so TCC sticks
- Sandbox network errors (‑1003): add `com.apple.security.network.client = true` (already set)
- Parakeet not detected: ensure it resides under the container path above; downloading from Kol places it correctly.

## Eval Workflow

The project has a promptfoo-based eval suite in `evals/` that tests LLM post-processing quality. **Run evals before building whenever you change prompts.**

```bash
# API key is in .env — always source it first
source .env

# Run the default English suite (general, messaging, document contexts)
bun run eval

# Run code dictation evals (keyword preservation, operator conversion)
bun run eval:code

# Run screen context evals (identifier resolution from visible text)
bun run eval:screen

# View results in browser
bun run eval:view
```

### Eval structure
- `evals/promptfooconfig.yaml` — main config, runs `english.yaml` with `english-general.txt` prompt
- `evals/prompts/` — static copies of assembled system prompts (must be updated when `LLMPostProcessing.swift` prompts change)
- `evals/datasets/english.yaml` — general, messaging, document test cases (~31 cases)
- `evals/datasets/code-dictation.yaml` — code keyword, operator, and screen context test cases (~23 cases)
- `evals/datasets/edge-cases.yaml` — adversarial and edge case inputs
- `evals/datasets/hebrew.yaml` — Hebrew-specific test cases

### Adding new eval cases
- Code dictation tests go in `datasets/code-dictation.yaml` (NOT `english.yaml`)
- Screen context tests use `english-code-screen.txt` prompt (has `{{screenContext}}` variable)
- Non-screen code tests use `english-code.txt` prompt
- General/messaging/document tests go in `english.yaml`

## Changelog Workflow Expectations

1. **Always add a changeset:** Any feature, UX change, or bug fix that ships to users must come with a `.changeset/*.md` fragment. The summary should mention the user-facing impact plus the GitHub issue/PR number (for example, "Improve Fn hotkey stability (#89)").
2. **Use non-interactive changeset creation:** AI agents should use the non-interactive script:
   ```bash
   bun run changeset:add-ai patch "Your summary here"
   bun run changeset:add-ai minor "Add new feature"
   bun run changeset:add-ai major "Breaking change"
   ```
3. **Only create changesets, don't process them:** Agents should only create changeset fragments. The release tool is responsible for running `changeset version` to collect changesets into `CHANGELOG.md` and syncing to `Kol/Resources/changelog.md`.
4. **Reference GitHub issues:** When a change addresses a filed issue, link it in code comments and the changeset entry (`(#123)`) so release notes and Sparkle updates point users back to the discussion. If the work should close an issue, include "Fixes #123" (or "Closes #123") in the commit or PR description so GitHub auto-closes it once merged.

## Git Commit Messages

- Use a concise, descriptive subject line that captures the user-facing impact (roughly 50–70 characters).
- Follow up with as much context as needed in the body. Include the rationale, notable tradeoffs, relevant logs, or reproduction steps—future debugging benefits from having the full story directly in git history.
- Reference any related GitHub issues in the body if the change tracks ongoing work.

## Releasing a New Version

Releases are automated via a local CLI tool that handles building, signing, notarizing, and uploading.

### Prerequisites

1. **AWS credentials** must be set (for S3 uploads):
   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   ```

2. **Notarization credentials** stored in keychain (one-time setup):
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD"
   ```

3. **Dependencies installed** at project root and in tools:
   ```bash
   bun install                # project root (for changesets)
   cd tools && bun install    # tools dependencies
   ```

### Release Steps

1. **Ensure all changes are committed** - the release tool requires a clean working tree

2. **Ensure changesets exist** - any user-facing change should have a `.changeset/*.md` file:
   ```bash
   bun run changeset:add-ai patch "Fix microphone selection"
   ```

3. **Run the release command** from project root:
   ```bash
   bun run tools/src/cli.ts release
   ```

### What the Release Tool Does

1. Checks for clean working tree
2. Finds pending changesets and applies them (bumps version in `package.json`)
3. Syncs changelog to `Kol/Resources/changelog.md`
4. Updates `Info.plist` and `project.pbxproj` with new version
5. Increments build number
6. Cleans DerivedData and archives with xcodebuild
7. Exports and signs with Developer ID
8. Notarizes app with Apple
9. Creates and signs DMG
10. Notarizes DMG
11. Generates Sparkle appcast
12. Uploads to S3 (versioned DMG + `kol-latest.dmg` + appcast.xml)
13. Commits version changes, creates git tag, pushes
14. Creates GitHub release with DMG and ZIP attachments

### If No Changesets Exist

The tool will prompt you to either:
- Stop and create a changeset (recommended)
- Continue with manual version bump (useful for re-running failed releases)

### Artifacts

Each release produces:
- `Kol-{version}.dmg` - Signed, notarized DMG
- `Kol-{version}.zip` - For Homebrew cask
- `kol-latest.dmg` - Always points to latest
- `appcast.xml` - Sparkle update feed

### Troubleshooting

- **"Working tree is not clean"**: Commit or stash all changes before releasing
- **Notarization fails**: Check Apple ID credentials and app-specific password
- **S3 upload fails**: Verify AWS credentials and bucket permissions
- **Build fails**: Ensure Xcode 16+ and valid code signing certificates
