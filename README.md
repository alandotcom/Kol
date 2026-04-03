# Kol — Voice → Text

Kol (קול, Hebrew for "voice") is a fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) — a macOS menu bar app for on-device voice-to-text using [Parakeet TDT](https://github.com/FluidInference/FluidAudio) on Apple Silicon, with optional LLM post-processing.

<img width="812" alt="Kol Settings" src="docs/screenshots/settings.png" />

<details>
<summary>More screenshots</summary>

<img width="812" alt="Kol Transforms" src="docs/screenshots/transforms.png" />
<img width="812" alt="Kol Advanced" src="docs/screenshots/advanced.png" />

</details>

## Features

- **On-device transcription** via [Parakeet TDT](https://github.com/FluidInference/FluidAudio) — fast, accurate, multilingual, runs entirely on Apple Silicon
- **AI post-processing** — optional LLM cleanup via [Groq](https://groq.com), [Cerebras](https://cerebras.ai), or any OpenAI-compatible API (~80ms latency):
  - Fixes punctuation, removes filler words, corrects ASR errors
  - Formats lists as bullet points in docs, keeps casual tone in messaging
  - Adapts to the target app (Terminal, Slack, Notes, etc.)
  - Composable prompt architecture: core rules + language-specific + app-context + your custom rules
- **Context-aware** — captures screen text, IDE file names, and vocabulary near the cursor to improve transcription accuracy
- **Press-and-hold** or **double-tap** hotkey recording modes

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

On first launch, grant microphone and accessibility permissions. The Parakeet model downloads automatically (~650 MB).

## Instructions

Once you open Kol, you'll need to grant it microphone and accessibility permissions—so it can record your voice and paste the transcribed text into any application, respectively.

Once you've configured a global hotkey, there are **two recording modes**:

1. **Press-and-hold** the hotkey to begin recording, say whatever you want, and then release the hotkey to start the transcription process.
2. **Double-tap** the hotkey to *lock recording*, say whatever you want, and then **tap** the hotkey once more to start the transcription process.

## License

This project is licensed under the MIT License — originally created by [Kit Langton](https://github.com/kitlangton). See `LICENSE` for details.
