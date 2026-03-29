# Kol — Voice → Text (with Hebrew/Caspi support)

Kol (קול, Hebrew for "voice") is a fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) with added support for **Hebrew speech recognition** via [Caspi-1.7B CoreML](https://huggingface.co/alandotcom/caspi-1.7b-coreml), a Hebrew-optimized fine-tune of Qwen3-ASR running on Apple Silicon.

<img width="812" alt="Kol with Caspi Hebrew model" src="https://github.com/user-attachments/assets/38f7acf0-fcb9-4bed-9a5b-1abc9beb4417" />

## What's added

- **Caspi 1.7B (Hebrew)** model option — on-device Hebrew ASR via CoreML on Apple Silicon
- Auto-downloads model from [HuggingFace](https://huggingface.co/alandotcom/caspi-1.7b-coreml) on first use (~2.8 GB)
- **Auto language switching** — Hebrew keyboard active? Uses Caspi. Otherwise uses Parakeet. No manual switching needed.
- **AI post-processing** — optional LLM cleanup via [Groq](https://groq.com), [Cerebras](https://cerebras.ai), or any OpenAI-compatible API (~80ms latency):
  - Fixes punctuation, removes filler words, corrects ASR errors
  - Formats lists as bullet points in docs, keeps casual tone in messaging
  - Adapts to the target app (Terminal, Slack, Notes, etc.)
  - Composable prompt architecture: core rules + language-specific + app-context + your custom rules
- Uses [alandotcom/FluidAudio](https://github.com/alandotcom/FluidAudio/tree/caspi-1.7b-compat) fork with Qwen3-ASR 1.7B support

## Performance

- ~2x real-time on Apple Silicon (M-series)
- ~5% WER on Hebrew benchmarks
- ~6 GB peak memory (int8 quantized)
- ~80ms LLM post-processing (Groq)

## Building from source

Requires macOS 15+, Xcode 16+, Apple Silicon.

```bash
git clone https://github.com/alandotcom/Kol.git
cd Kol
xcodebuild build \
  -scheme Kol \
  -configuration Release \
  -skipMacroValidation \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual

# Find and install the built app
cp -R ~/Library/Developer/Xcode/DerivedData/Kol-*/Build/Products/Release/Kol.app /Applications/
open /Applications/Kol.app
```

Or open `Kol.xcodeproj` in Xcode, set your signing team under Signing & Capabilities, and hit Cmd+R.

On first launch, grant microphone and accessibility permissions. Select **Caspi 1.7B (Hebrew)** in Settings — the model downloads automatically (~2.8 GB).

---

*Originally forked from [kitlangton/Hex](https://github.com/kitlangton/Hex):*

Press-and-hold a hotkey to transcribe your voice and paste the result wherever you're typing.

> **Note:** Kol is currently only available for **Apple Silicon** Macs.

Kol supports [Parakeet TDT v3](https://github.com/FluidInference/FluidAudio) via the awesome [FluidAudio](https://github.com/FluidInference/FluidAudio) (the default—it's frickin' unbelievable: fast, multilingual, and cloud-optimized), [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device transcription, and now **Caspi-1.7B** for Hebrew. We use the incredible [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) for structuring the app.

## Instructions

Once you open Kol, you'll need to grant it microphone and accessibility permissions—so it can record your voice and paste the transcribed text into any application, respectively.

Once you've configured a global hotkey, there are **two recording modes**:

1. **Press-and-hold** the hotkey to begin recording, say whatever you want, and then release the hotkey to start the transcription process.
2. **Double-tap** the hotkey to *lock recording*, say whatever you want, and then **tap** the hotkey once more to start the transcription process.

## Contributing

**Issue reports are welcome!** If you encounter bugs or have feature requests, please [open an issue](https://github.com/alandotcom/Kol/issues).

**Note on Pull Requests:** At this stage, I'm not actively reviewing code contributions for significant features or core logic changes. The project is evolving rapidly and it's easier for me to work directly from issue reports. Bug fixes and documentation improvements are still appreciated, but please open an issue first to discuss before investing time in a large PR. Thanks for understanding!

### Changelog workflow

- **For AI agents:** Run `bun run changeset:add-ai <type> "summary"` (e.g., `bun run changeset:add-ai patch "Fix clipboard timing"`) to create a changeset non-interactively.
- **For humans:** Run `bunx changeset` when your PR needs release notes. Pick `patch`, `minor`, or `major` and write a short summary—this creates a `.changeset/*.md` fragment.
- Check what will ship with `bunx changeset status --verbose`.
- `npm run sync-changelog` (or `bun run tools/scripts/sync-changelog.ts`) mirrors the root `CHANGELOG.md` into `Kol/Resources/changelog.md` so the in-app sheet always matches GitHub releases.
- The release tool consumes the pending fragments, bumps `package.json` + `Info.plist`, regenerates `CHANGELOG.md`, and feeds the resulting section to GitHub + Sparkle automatically. Releases fail fast if no changesets are queued, so you can't forget.
- If you truly need to ship without pending Changesets (for example, re-running a failed publish), the release script will now prompt you to confirm and choose a `patch`/`minor`/`major` bump interactively before continuing.

## License

This project is licensed under the MIT License — originally created by [Kit Langton](https://github.com/kitlangton). See `LICENSE` for details.
