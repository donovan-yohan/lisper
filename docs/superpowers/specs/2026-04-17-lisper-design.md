# Lisper Design

Date: 2026-04-17
Status: Draft for review

## Goal

Build `lisper`, a macOS-native local dictation app optimized for live speech-to-text on Apple Silicon.

The product should support two primary user experiences:

1. `Live` mode, where transcription appears while the user is still speaking.
2. `Final` mode, where transcription is committed after the recording session ends.

The product should support two primary output targets:

1. `Lisper Modal`, where text appears inside the app UI.
2. `Focused Text Field`, where text is written into the active macOS text input when possible.

For MVP, live mode does not perform refinement. Refinement is a separate post-processing layer that can be added later for final-mode transcripts and optional user-provided API keys.

## Product Requirements

### Core requirements

- Runs locally on the user’s machine.
- Works on macOS only.
- Shows transcription live while recording.
- Allows refinement to be enabled or disabled as a separate concern from live transcription.
- Allows output either in an app modal or directly into the currently focused text field.

### Personal-use-first requirements

- Must work well on an Apple Silicon MacBook with `M1` and `32 GB` RAM.
- Productization for other users is a secondary goal.
- A future bring-your-own-key path is allowed, but not part of the MVP critical path.

## Recommended Approach

Use a native `Swift` / `SwiftUI` macOS app with a pluggable ASR engine interface.

The first engine should be `whisper.cpp` because it is the lowest-risk path to a working local product. The app should be designed so that additional engines can be benchmarked and added later without changing the rest of the architecture.

This keeps the first version focused on:

- microphone capture
- live transcript display
- focused-field insertion
- session safety
- settings

instead of blocking the product on the perfect ASR stack.

## Alternatives Considered

### Option 1: `whisper.cpp` first, benchmark others later

Recommended.

Pros:

- Most mature local ASR path for an MVP.
- Strong Apple Silicon support.
- Lower integration risk.
- Faster route to a usable app.

Cons:

- Live partial behavior may not be the best possible long-term UX.
- A more advanced streaming engine may outperform it later.

### Option 2: multi-engine architecture from day one

Pros:

- Better long-term architecture.
- Makes `Fast` versus `Accurate` profiles easier to expose later.

Cons:

- More upfront work before a usable app exists.
- Higher integration and benchmark complexity in phase one.

### Option 3: MLX/CoreML-first research prototype

Pros:

- Potentially stronger Apple Silicon optimization.
- More aligned with future high-quality local streaming.

Cons:

- Higher research burden.
- Higher risk that the shell app slips while engine experimentation expands.

## Architecture

Lisper should be built around four independent layers.

### 1. Capture Layer

Responsible for:

- global hotkey handling
- microphone capture
- VAD and session lifecycle
- mode selection for `Live` versus `Final`

This layer should know nothing about text insertion details or refinement.

### 2. ASR Engine Layer

Responsible for:

- accepting live audio input
- producing partial transcript updates
- producing a final transcript at session end

The engine should conform to a common interface so that the app can switch between:

- `whisper.cpp` as the first backend
- possible future MLX/CoreML backends
- possible future higher-accuracy backends

### 3. Output Layer

Responsible for:

- rendering transcript updates in the Lisper modal
- writing transcript updates into the focused macOS text field when possible
- falling back safely when direct editing is not reliable

This layer owns insertion safety and target app compatibility.

### 4. Refinement Layer

Responsible for:

- optional post-processing after a final transcript exists
- future local or API-key-powered refinement

For MVP:

- `Live` mode bypasses refinement completely.
- `Final` mode may add refinement later, but that is not required to validate the product.

## Runtime Model

### Live session flow

1. User triggers the hotkey.
2. Lisper opens a transcription session.
3. Audio capture begins.
4. The selected ASR engine emits partial transcript updates.
5. Lisper routes those updates to either the modal or the active text target.
6. When the user stops recording, Lisper commits the final transcript for the session.
7. In final mode only, optional refinement can run after transcription completes.

### Session-owned insertion span

When writing to a focused text field, Lisper should attempt to track the text span that it inserted during the active session and only rewrite that span as partial transcript updates improve.

This is a design target, not an MVP guarantee.

The app must treat this as a capability to validate against real macOS apps, not as an assumption that all text fields support safe in-place rewriting.

## Output Modes

### Lisper Modal

Behavior:

- transcript updates render inside the app UI
- no reliance on arbitrary third-party text field behavior
- safest MVP mode

Use cases:

- universal compatibility
- debugging
- unsupported target apps

### Focused Text Field

Behavior:

- uses macOS Accessibility APIs to inspect and interact with the active text input
- attempts direct in-place session-owned updates when possible
- falls back to final commit insertion or clipboard/paste when needed

Constraints:

- may behave inconsistently across macOS apps
- should be considered unsupported for secure fields
- should fail safely rather than silently corrupting text

## Failure Model

### Missing permissions

If Accessibility permission is missing:

- focused-field mode should fail over to Lisper Modal
- the app should clearly surface what permission is required

If microphone permission is missing:

- no transcription session should start
- the app should show a clear permission recovery path

### Direct editing failure

If direct field mutation fails:

- preserve the last stable transcript state
- fall back to final insertion behavior
- if necessary, fall back to clipboard/paste

### Engine failure

If the ASR engine stalls or fails:

- preserve the last stable partial transcript
- surface the error in the UI
- allow retry without app restart

### Focus changes

If the focused target changes mid-session:

- default to the original target for the session
- do not automatically follow focus changes during an active dictation session

This avoids writing text into unintended destinations.

## Settings

### MVP settings

- `Transcription Mode`: `Live` or `Final`
- `Output Target`: `Lisper Modal` or `Focused Text Field`
- `Refinement`: off for live mode MVP

### Internal settings for benchmarking

- engine backend
- engine profile
- VAD/session parameters

These can remain hidden until benchmark results justify exposing a user-facing `Fast` versus `Accurate` toggle.

## Benchmark Plan

Benchmark on the target machine: `M1 MacBook` with `32 GB` RAM.

### Initial engine set

- `whisper.cpp`
- one MLX/CoreML streaming candidate
- one heavier accuracy-oriented local candidate

### Metrics

- first-token latency
- steady-state partial update latency
- final transcript latency
- CPU usage
- GPU usage where measurable
- RAM usage
- transcript quality on short dictation tasks

### App compatibility matrix

Validate focused-field behavior against:

- native macOS text field
- browser textarea
- Electron-based editor or app
- secure field edge case

## Out of Scope for MVP

- Windows support
- cross-platform app shell
- server-dependent transcription
- mandatory refinement in live mode
- guaranteed arbitrary-text-field in-place rewriting in every app
- multi-user cloud product concerns

## Open Questions

1. Is session-owned in-place rewriting reliable enough across common macOS apps to expose as a default mode?
2. Which local engine pairing is strong enough to justify a user-facing `Fast` and `Accurate` toggle?
3. Should bring-your-own-key refinement land before or after local final-mode refinement experiments?

## Recommendation

Build `lisper` as a native Swift/SwiftUI macOS app with:

- `whisper.cpp` as the first local ASR backend
- `Live` and `Final` transcription modes
- `Lisper Modal` and `Focused Text Field` output modes
- no refinement in live mode MVP
- a first-class fallback path when focused-field rewriting is unreliable

This delivers the core user value quickly while preserving a clean path to future benchmarking, engine upgrades, and optional refinement.
