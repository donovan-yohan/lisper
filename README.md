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

## Launch The App Prototype

Launch the macOS prototype with:

```bash
swift run lisper-app
```

The hardcoded global hotkey is `Control + Option + Space`.

The prototype currently launches `whisper-stream` with:

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
