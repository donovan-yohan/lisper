# Lisper

## Run Tests

```bash
swift test
```

For the app shell smoke checks:

```bash
swift test --filter AppExecutableSmokeTests
```

## Set Up Local Whisper Tooling

```bash
bash scripts/setup-whisper-local.sh
```

The script keeps the prototype dependencies in `.tools/` inside the repo, clones `whisper.cpp` if needed, builds `whisper-stream`, and downloads a small English model.

## Run the Demo

```bash
swift run lisper-demo
```

Use conventional flags to switch the scripted mode and target:

```bash
swift run lisper-demo --target focusedTextField
swift run lisper-demo --target focusedTextField --fallback
```

The first focused command shows the clean rewrite path. The fallback form forces the demo to show the fallback behavior.

Unknown arguments are rejected with a usage message, so prefer the flag form above.

## Launch The App

Launch the macOS app with:

```bash
swift run lisper-app
```

The default global hotkey is `Right Option`.

- Tap `Right Option` to toggle listening.
- Hold `Right Option` for push-to-talk.
- Listening opens a small center-bottom ephemeral modal with reactive orb feedback.
- When recording stops, the modal expands into stacked `Original` and `Enhanced` text blocks.
- Click anywhere inside a text block to copy it. The bottom-right copy icon is the affordance, but the whole bubble is clickable.

The app currently captures microphone audio in-process with `libwhisper`. The older process-backed `whisper-stream` path still configures:

- capture device `0`
- `--step 1000`
- `--length 5000`
- `--keep 200`
- `-kc`
- `-l en`

To verify the app executable builds without running it:

```bash
swift build --product lisper-app
```

## Settings

The persistent app surface is Settings. Open it from the Lisper menu bar item (`waveform` icon) with `Options...`, or use the standard macOS `Lisper -> Settings...` menu / `Command + ,` when the app is active.

- `Hotkey`: shows the current hotkey and preserves tap-to-toggle plus hold-to-talk semantics.
- `Models`: each model slot can stay local or use a remote endpoint. Remote slots expose endpoint URL, API key, and `Test`. API keys are stored in Keychain and settings retain only the key reference.
- `Automation`: post-processing is on by default, auto-copy is off by default, and auto-paste is off by default.
- `Appearance`: system, light, and dark themes.

When auto-copy is enabled, Lisper copies the enhanced result if cleanup succeeds. If cleanup is disabled or fails, it copies the original transcript. Auto-paste uses the same preferred result, but requires explicit opt-in.

The app writes status, diagnostics, and transcript updates to:

```bash
~/Library/Logs/Lisper/diagnostics.log
```

You can tail it while the app is running:

```bash
tail -f ~/Library/Logs/Lisper/diagnostics.log
```

## Packaging TODO

Packaging and shipping for end users is deferred for this prototype.
