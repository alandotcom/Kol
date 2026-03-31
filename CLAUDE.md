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
  - `PromptLayers.ideContext(fileNames:language:)` — open file names from IDE tab bar (code editors only)
  - `PromptLayers.screenContext(visibleText:)` / `.structuredScreenContext(context:)` — opt-in, captures text near cursor via Accessibility API
  - `PromptLayers.vocabularyHints(terms:)` — extracted identifiers and proper nouns from screen text
  - Custom rules — user-provided facts (name, company, common terms)
  - `PromptAssembler.systemPrompt()` composes applicable layers in order: core → language → app context → IDE context → screen context → vocabulary hints → custom rules
- **Key files**: `KolCore/LLMPostProcessing.swift`, `LLMPostProcessingClient.swift`, `ScreenContextClient.swift`, `IDEContextClient.swift`, `KeychainClient.swift`, `LLMSectionView.swift`
- **Insertion point**: `TranscriptionFeature.handleTranscriptionResult()`, after word removals/remappings, before `finalizeRecordingAndStoreTranscript()`
- **Screen context capture**: `ScreenContextClient` uses AX APIs at recording start (synchronous), then refreshes every 1s during recording via `contextRefreshTick` timer effect. State stored in `TranscriptionFeature.State.capturedScreenContext` / `capturedCursorContext`, cleared on cancel/discard.
- **IDE context capture**: `IDEContextClient` extracts open file tab titles from code editors (VS Code, Cursor, Xcode, Zed) via AX tree walk. File names feed into vocabulary cache and a dedicated prompt layer. Captured at recording start only.
- **Graceful fallback**: on any LLM error, original text is pasted
- **API key**: stored in macOS Keychain via `KeychainClient`, NOT in settings JSON
- **Tests**: `PromptAssemblerTests.swift` for prompt composition
- **Evals**: promptfoo-based eval suite — see Eval Workflow section below

### Prompt change workflow

When modifying any prompt in `LLMPostProcessing.swift`:

1. **Update the eval prompt files** — `evals/prompts/*.txt` are static copies of the assembled system prompts. They must be kept in sync manually. If you change `appContextCode`, update `evals/prompts/english-code.txt` and `evals/prompts/english-code-screen.txt`.
2. **Run evals before building** — see Eval Workflow below.
3. **Run unit tests** — see "Run tests" commands below
4. **Then build** — `./scripts/build-install.sh --debug`

## Build & Development Commands

```bash
# Debug build for local testing (default workflow)
killall "Kol Debug" 2>/dev/null; ./scripts/build-install.sh --debug && open "/Applications/Kol Debug.app"

# Release build + install to /Applications (only for final verification before release)
killall Kol 2>/dev/null; ./scripts/build-install.sh

# Run tests (preferred — uses running Xcode instance, fastest)
xcodebuildmcp xcode-ide call-tool --remote-tool RunAllTests --json '{"arguments":{"tabIdentifier":"windowtab1"}}'

# Run tests (fallback — standalone, no Xcode required)
xcodebuildmcp macos test --scheme Kol --project-path Kol.xcodeproj

# Open in Xcode (recommended for development)
open Kol.xcodeproj

# Trigger a transcription and capture logs (no Xcode needed)
./scripts/test-transcribe.sh              # 3s silence, current focused app
./scripts/test-transcribe.sh 5            # 5s silence
./scripts/test-transcribe.sh 3 Slack      # focus Slack first
./scripts/test-transcribe.sh 3 Messages   # focus Messages first
./scripts/test-transcribe.sh 3 Cursor     # focus Cursor first
```

### Runtime log capture (test-transcribe)

`scripts/test-transcribe.sh` launches Kol Debug, simulates the Right Option hotkey via CGEvent, and streams unified logs to `/tmp/kol-transcribe-test.log`. Use this to exercise the full transcription pipeline (recording → VAD → transcription → LLM post-processing) without manual interaction.

- **How it works**: CGEvent posts Right Option key down/up events that Kol's global `CGEventTap` monitor picks up. Records silence from the mic (VAD will skip transcription, but all logging fires).
- **Focus an app**: Pass a second argument (e.g., `Messages`, `Slack`, `Cursor`) to activate that app before recording, so Kol captures its screen context, vocabulary, and conversation metadata.
- **Logs**: All `com.alandotcom.Kol` subsystem logs at debug level, written to `/tmp/kol-transcribe-test.log`. Note: `<private>` redaction is normal for unified logging outside the Xcode debugger — the log structure and categories are still visible.
- **When to use**: After changing screen context, vocabulary extraction, recording, or LLM prompt code — faster than manual testing.

### Build rules for agents

- **Use debug builds for local testing** — run `./scripts/build-install.sh --debug`, which installs to `/Applications/Kol Debug.app`. The release install (`./scripts/build-install.sh` without `--debug`) installs to `/Applications/Kol.app` and is only for final verification before a release.
- **Always use `./scripts/build-install.sh`** — it handles xcodebuild, codesign, and rsync. Do NOT run `xcodebuild` manually.
- **Xcode uses file system synchronization** (`PBXFileSystemSynchronizedRootGroup`) — new `.swift` files added to the `Kol/` directory are automatically included in the build. No need to edit the `.xcodeproj` file.
- **Check for build failures** — the script prints "(N failures)" if there are errors. If you see failures, grep the build output for `error:` before proceeding. Do NOT sign and install a broken build.
- **Pipe build/test output to a file, then grep the file** — builds are slow. Do NOT pipe output through grep inline and then re-run the command to see different parts. Instead, run once with output redirected to a temp file (e.g., `./scripts/build-install.sh --debug > /tmp/build.log 2>&1`), then grep `/tmp/build.log` as many times as needed.
- **Run tests via xcodebuildmcp** — prefer the Xcode IDE path (`xcodebuildmcp xcode-ide call-tool --remote-tool RunAllTests ...`) when Xcode is open; fall back to standalone (`xcodebuildmcp macos test --scheme Kol --project-path Kol.xcodeproj`) otherwise. Do NOT use raw `xcodebuild test` directly.
- **Never commit until tests pass** — work is not done until all tests are green. Run tests and confirm zero failures before committing. Do NOT assume failing tests are "pre-existing" or "unrelated" unless the user explicitly tells you so. If tests fail, diagnose and fix them as part of your current work.

### TCC permissions and code signing — critical rules

macOS TCC (Transparency, Consent, and Control) grants accessibility, input monitoring, and microphone permissions per **CDHash** — a hash of the signed binary. Any change to the code signature invalidates all TCC grants for that app, forcing the user to re-add permissions manually in System Settings. This is extremely disruptive. Follow these rules:

1. **NEVER run `codesign` manually on a built app.** The build script (`build-install.sh`) already handles signing. Running `codesign --force` after the build changes the CDHash and wipes permissions. If you need to verify the signature, use `codesign -dvvv` (read-only).

2. **NEVER run `tccutil reset`** — this wipes ALL TCC permissions for the bundle ID, including the production app's grants. There is no way to restore them programmatically; the user must manually re-add in System Settings.

3. **Do NOT re-sign when copying to `/Applications/Kol Debug.app`** — just `cp -R` the built app. The build script's signature is already correct.

4. **Both `Kol.app` and `Kol Debug.app` share bundle ID `com.alandotcom.Kol`** — TCC commands that target the bundle ID (like `tccutil reset`) affect BOTH apps. Never run destructive TCC operations.

5. **If permissions break**, the only fix is for the user to manually toggle the app off/on in System Settings → Privacy & Security → Accessibility / Input Monitoring, or remove and re-add via the + button. Do NOT try to fix this programmatically.

6. **Minimize rebuilds during testing** — every rebuild changes the binary, which changes the CDHash. On macOS 26 (Tahoe), TCC is aggressive about CDHash tracking and may invalidate grants on rebuild even with the same signing identity. Batch your changes and rebuild once, not iteratively.

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
- `ScreenContextClient`: Captures focused text field content via macOS Accessibility API for LLM context; refreshed every 1s during recording
- `IDEContextClient`: Extracts open file tab titles from code editors via AX tree walk
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

5. **Continuous Context Refresh**: During recording, a 1-second timer (`contextRefreshTick`) re-captures screen text via AX APIs and updates the vocabulary cache. Gated by `llmPostProcessingEnabled && llmScreenContextEnabled`. Timer cancelled on stop/cancel/discard via `CancelID.contextRefresh`.

6. **WhisperKit Vocabulary Biasing**: When vocabulary hints are available, they're encoded as prompt tokens via `whisperKit.tokenizer.encode()` and set on `DecodingOptions.promptTokens`. Only applies to WhisperKit models (Parakeet and Qwen paths are unaffected).

7. **Permissions**: Requires audio input and automation entitlements (see `Kol.entitlements`)

8. **Logging**: All diagnostics should use the unified logging helper `KolLog` (`Kol/Core/Logging.swift`). Pick an existing category (e.g., `.transcription`, `.recording`, `.settings`) or add a new case so Console predicates stay consistent. Avoid `print` and prefer privacy annotations (`, privacy: .private`) for anything potentially sensitive like transcript text or file paths.

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
- Documented solutions to past build/test issues: `docs/solutions/` (YAML frontmatter searchable by module, tags, problem_type)

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

Releases use `scripts/release.sh`, which bumps versions, builds, signs, creates a ZIP, pushes to GitHub, and creates a GitHub release.

```bash
# Ensure all changes are committed (clean working tree required)
./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.1.0
```

### What the Release Script Does

1. Validates semver and checks for clean working tree
2. Bumps version in `Info.plist`, `project.pbxproj`, and `package.json`
3. Increments build number
4. Commits version bump + creates git tag `v<version>`
5. Builds with xcodebuild (Release configuration)
6. Signs with Apple Development identity
7. Creates ZIP artifact in `build/`
8. Pushes commit + tag to `fork` remote
9. Creates GitHub release via `gh release create` with ZIP attached
