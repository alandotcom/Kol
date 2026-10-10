# Kol LLM Post-Processing Evals

Evaluation suite for the LLM post-processing pipeline that cleans up raw ASR (speech-to-text) output.

Uses [promptfoo](https://www.promptfoo.dev/) — a config-driven eval framework for LLM testing.

## Quick Start

```bash
# Set your Groq API key
export GROQ_API_KEY=your_key_here

# Run all evals
bun run eval

# View results in browser
bun run eval:view
```

## Running Specific Suites

```bash
cd evals

# English suite with each case routed to its app-context prompt
bun run --cwd .. eval

# Hebrew only
npx promptfoo@latest eval --tests datasets/hebrew.yaml --prompts prompts/hebrew-general.txt

# Edge cases only
npx promptfoo@latest eval --tests datasets/edge-cases.yaml

# Folder-path vocabulary in a general compose field
bun run --cwd .. eval:paths

# Explicit separators and hyphenated identifiers in messaging
bun run --cwd .. eval:separators
```

## Test Structure

### Datasets (`datasets/`)
- `english.yaml` — 30 English test cases (general, code, messaging, document contexts)
- `hebrew.yaml` — 30 Hebrew test cases (general, code-switching, messaging, document)
- `edge-cases.yaml` — 20 edge cases (empty input, adversarial, mixed language, etc.)

### Prompt Templates (`prompts/`)
Each file is the exact system prompt sent to the LLM, matching what `PromptAssembler.systemPrompt()` produces for that language + app context combination:
- `english-general.txt` — English, no app context
- `english-code.txt` — English, code editor/terminal
- `english-messaging.txt` — English, messaging app
- `english-document.txt` — English, document/email
- `hebrew-general.txt` — Hebrew, no app context
- `hebrew-messaging.txt` — Hebrew, messaging

## Adding Test Cases

Add a new entry to the appropriate dataset YAML:

```yaml
- description: "Short description of what's being tested"
  vars:
    input: "the raw asr text that would come from speech recognition"
  assert:
    # Automated checks (fast, deterministic)
    - type: not-contains
      value: " um "
    - type: contains
      value: "expected term"
    # LLM-as-judge (slower, subjective quality)
    - type: llm-rubric
      value: "Description of what good output looks like"
```

### Assertion Types

| Type | Use For |
|------|---------|
| `contains` | Expected term is present |
| `not-contains` | Filler/preamble is removed |
| `equals` | Exact match (short outputs) |
| `llm-rubric` | LLM judges output quality against a rubric |
| `javascript` | Custom logic (e.g., Hebrew script detection) |

### Hebrew Script Detection

```yaml
- type: javascript
  value: "/[\u0590-\u05FF]/.test(output)"
```

## Updating Prompts

If you change `PromptLayers` in `KolCore/LLMPostProcessing.swift`, regenerate the prompt template files to match. The eval tests the actual prompt text the LLM receives, not the Swift assembly logic (that's covered by `PromptAssemblerTests.swift`).

## Comparing Providers / Models

Edit `promptfooconfig.yaml` to add providers:

```yaml
providers:
  - id: openai:chat:meta-llama/llama-4-scout-17b-16e-instruct
    label: groq-llama4-scout
    config:
      apiBaseUrl: https://api.groq.com/openai/v1
      apiKeyEnvar: GROQ_API_KEY
      temperature: 0

  - id: openai:chat:llama-4-scout-17b-16e
    label: cerebras-llama4
    config:
      apiBaseUrl: https://api.cerebras.ai/v1
      apiKeyEnvar: CEREBRAS_API_KEY
      temperature: 0
```

Then run `bun run eval` — promptfoo will test all providers side-by-side.

Focused text and vocabulary-only window context cases run with `bun run eval:focused` after sourcing `.env`. The screen prompt copies match the runtime focused-text labels. Mention cases provide extracted vocabulary rather than raw message history.


Each English case selects a prompt label through `prompts`. The default config
registers those labels; per-test `options.prompt` overrides are unsupported by the
current promptfoo evaluator. Dedicated CLI suites have no inherited prompt filter.
The grading model is Qwen 3.8 27B on Groq, independent of the GPT-OSS candidate.
The candidate uses low reasoning effort, matching runtime cleanup requests.
