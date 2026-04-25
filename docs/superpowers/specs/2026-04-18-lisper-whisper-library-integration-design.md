# Lisper Whisper Library Integration Design

Date: 2026-04-18
Status: Approved for implementation

## Goal

Replace the subprocess-based `whisper-stream` integration with an in-process `libwhisper` integration so the app owns:

- microphone capture
- rolling audio buffers
- transcription timing
- transcript state updates into the app window

The product UI must stop depending on transcript log files or console-oriented subprocess output.

## Why Change

The prior `whisper-stream` prototype proved three things:

1. microphone capture works
2. local Whisper transcription works
3. `whisper-stream` is a poor product integration surface because it is optimized for terminal interaction, not a stable app event protocol

The correct product boundary is direct library integration.

## Scope

### In scope

- add a SwiftPM C shim target for `whisper.h`
- link the app against the locally built `libwhisper` and `ggml` dylibs
- capture microphone input in-process with `AVAudioEngine`
- resample/normalize to `16 kHz` mono float PCM
- maintain a rolling audio buffer
- transcribe on a timer using in-process `whisper_full`
- push transcript results directly into app state
- keep diagnostics logging separate from product transcript state

### Out of scope

- AX typing
- packaging/distribution
- model download UX beyond existing setup tooling
- sophisticated VAD
- polished transcript diffing or partial-token UX

## Architecture

### 1. C shim target

Add a `CWhisper` target that exposes `whisper.h` to Swift and links against the local dynamic libraries.

This target exists only to make the C API available to the Swift runtime layer.

### 2. In-process transcriber

Add a `WhisperLibraryTranscriber` responsible for:

- loading the model once
- owning the whisper context lifecycle
- accepting rolling PCM windows
- invoking `whisper_full`
- extracting decoded segments
- returning a normalized transcript snapshot

### 3. Audio capture layer

Add an `AudioCaptureService` backed by `AVAudioEngine` that:

- requests microphone permission
- captures microphone audio
- converts it to `16 kHz` mono float PCM
- appends frames into a rolling buffer

### 4. Session bridge

The app coordinator starts/stops an in-process session object that combines:

- audio capture
- periodic transcription
- transcript publication into `LisperAppModel`

No transcript file polling is allowed in the product path.

## Runtime Model

### Live updates

For the prototype, updates should be chunked and mostly stable.

Proposed behavior:

- keep a rolling buffer of the last `5-8` seconds
- run transcription roughly every `0.8-1.0` seconds while recording
- replace the textbox with the latest best transcript for the rolling window

This is acceptable for the prototype even if it occasionally rewrites recent text.

### Hotkey behavior

Keep the existing product requirement:

- `Control + Option + Space`
- tap toggles recording
- press-and-hold records for duration, release stops

If the release-monitoring path is unavailable, degrade safely to toggle-only while surfacing that in diagnostics.

## Testing Strategy

### Automated

- binding/config smoke tests for `CWhisper`
- unit tests for transcript extraction/normalization from fake decoder results where possible
- unit tests for app/session state
- audio-buffer logic tests where possible

### Manual

Manual verification remains required:

1. run setup script
2. launch app
3. start recording with hotkey
4. speak
5. confirm the textbox updates live
6. stop recording
7. confirm final text remains visible

## Decisions Log

1. **Stop using transcript files as the product UI path.**
   Reason: that mixes debugging artifacts with product behavior.

2. **Use `libwhisper` directly instead of the `whisper-stream` subprocess.**
   Reason: app-owned transcript state is the correct abstraction boundary.

3. **Use `AVAudioEngine` for microphone capture.**
   Reason: it is the pragmatic native macOS path for a prototype.

4. **Keep chunked live updates over a rolling window instead of trying to replicate token streaming.**
   Reason: this is much simpler and still satisfies the prototype requirement of visible live updates while speaking.
