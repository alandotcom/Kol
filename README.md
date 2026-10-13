# Kol — Voice → Text

Kol (קול, Hebrew for "voice") is a fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) — a macOS menu bar app for on-device voice-to-text using [Parakeet TDT](https://github.com/FluidInference/FluidAudio) on Apple Silicon, with optional LLM post-processing.

## Features

- **On-device transcription** via [Parakeet TDT](https://github.com/FluidInference/FluidAudio) — fast, accurate, multilingual, runs entirely on Apple Silicon
- **AI post-processing** fixes punctuation, removes filler words and corrects speech-recognition errors. Choose a provider in Settings:
  - **Local (on-device)** runs an English cleanup model on your Mac with Core ML, with no API key and nothing sent over the network. Kol downloads the model (about 700 MB) from [Hugging Face](https://huggingface.co/alandotcom/kol-cleanup-360m-coreml) the first time you choose it. A typical cleanup takes about 250 ms on Apple Silicon. It corrects names it sees on screen or in the conversation title, and pastes your transcript unchanged when it is unsure.
  - **[Groq](https://groq.com)**, **[OpenRouter](https://openrouter.ai)**, or any **OpenAI-compatible API** use a cloud model with your API key, stored in the macOS Keychain. These adapt to the target app (for example, bullet lists in documents and a casual tone in messaging) through a composable prompt: core rules, language rules, app context and your custom rules.
- **Word removals and remappings**: remove words you never want (um, uh) or optional ones such as "literally" and "basically", and replace words with your own spellings
- **Context-aware** — captures screen text, IDE file names, and vocabulary near the cursor to improve transcription accuracy
- **Press-and-hold** or **double-tap** hotkey recording modes
- **Automatic updates** through Sparkle, which you can turn off under Settings → General → Updates

## Install

Download `Kol-vX.Y.Z.zip` from the [latest release](https://github.com/alandotcom/Kol/releases/latest), unzip it and move `Kol.app` to Applications. Releases are signed and notarized, and later versions update in place.

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

## Releases

See [Releasing Kol](docs/releasing.md) for notarization setup and release commands.

## License

This project is licensed under the MIT License — originally created by [Kit Langton](https://github.com/kitlangton). See `LICENSE` for details.
