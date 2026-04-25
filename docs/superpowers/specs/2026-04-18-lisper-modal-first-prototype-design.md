# Lisper Modal-First Prototype Design

Date: 2026-04-18
Status: Approved for implementation

## Goal

Build a working macOS prototype that:

- captures real microphone audio
- runs real local `whisper.cpp` transcription
- streams chunked transcript updates into a normal app window textbox
- supports a hardcoded global hotkey:
  - tap to toggle recording
  - press and hold to record, release to stop

This milestone explicitly stops at modal/window output. Real Accessibility typing into arbitrary apps is deferred until after the modal prototype is stable.

## Scope

### In scope

- native macOS app window
- hardcoded global hotkey
- real `whisper.cpp` integration
- real microphone capture through the live whisper path
- chunked live updates that favor stability over token-by-token noise
- final transcript commit on stop
- protocol-backed test seams around hotkey, transcription process state, and transcript parsing
- a setup path for local developer dependencies

### Out of scope

- real Accessibility typing
- packaging/distribution for end users
- user-configurable hotkeys
- refinement/post-processing
- multi-engine benchmarking UI
- polished product UI

## Product Shape

The first working prototype is a normal macOS window with:

- a large transcript textbox
- a session status line
- a small diagnostics area showing the active hotkey and whisper dependency state

The app should launch into a usable state for debugging and demoing. The transcript textbox is the primary output surface.

## Runtime Model

### Session behavior

1. App starts and opens a normal window.
2. App installs a hardcoded global hotkey: `Control + Option + Space`.
3. On hotkey press:
   - if idle, begin a transcription session
   - if already recording and this is a tap/toggle interaction, end the session
4. On key release:
   - if the current interaction is hold-to-talk, end the session
5. During the session, the app reads live transcript updates from `whisper.cpp` and updates the textbox.
6. When the session ends, the last stable transcript remains in the textbox as the final result.

### Transcript stability

The first real prototype should prefer mostly stable chunked updates, not noisy token churn.

For this milestone, "streaming" means:

- regular transcript refreshes while the user is still speaking
- updates emitted by the live whisper path at a useful cadence
- the textbox visibly updating during the session

It does **not** require perfect token-level partial decoding behavior.

## Architecture

### 1. App Shell

Responsible for:

- app lifecycle
- window creation
- view model wiring
- microphone permission flow
- user-visible status and errors

### 2. Hotkey Layer

Responsible for:

- registering the hardcoded global hotkey
- distinguishing tap-to-toggle from hold-to-talk
- emitting semantic session commands (`start`, `stop`)

### 3. Whisper Session Layer

Responsible for:

- locating the `whisper-stream` executable
- locating the model file
- starting/stopping the process
- reading stdout/stderr
- converting process output into transcript updates and state transitions

### 4. Transcript Assembly Layer

Responsible for:

- parsing `whisper.cpp` streaming output
- normalizing chunked updates
- tracking the latest stable transcript for the UI

This layer should be testable with fixtures and fake process output.

## Dependency Contract

For the prototype, Lisper may depend on locally available `whisper.cpp` artifacts instead of a polished bundled distribution.

The app should support:

- explicit environment configuration for the executable/model paths
- probing a few common local defaults
- a clear "dependency missing" state in the UI when the binary or model cannot be found

Packaging/shipping remains a TODO.

## Testing Strategy

### Automated

- unit tests for transcript parsing
- unit tests for session state transitions
- unit tests for hotkey interaction classification where feasible
- integration-style tests for process output -> UI state mapping using fake runners

### Manual

Manual verification is required for the first working prototype:

1. launch the app
2. confirm the app window appears
3. trigger the hotkey
4. speak into the microphone
5. confirm transcript text appears and updates while speaking
6. stop recording
7. confirm the final transcript remains in the textbox

## Failure Model

### Missing microphone permission

- app stays usable
- recording does not start
- UI shows a clear permission error

### Missing whisper dependency

- app stays usable
- recording does not start
- UI shows which dependency is missing

### Whisper process startup failure

- session returns to idle
- stderr is surfaced in diagnostics or a concise error message

### Process crash during recording

- preserve the latest stable transcript already shown
- surface the failure in the UI
- allow another session without restarting the app

## Decisions Log

The following decisions were made to unblock implementation without stopping for more user input:

1. **Wrap `whisper.cpp`'s real-time streaming binary instead of implementing Whisper inference in Swift.**
   Reason: this is the fastest path to a real mic + real whisper + real app prototype.

2. **Keep the first prototype modal-first and defer AX typing entirely.**
   Reason: this isolates the audio/ASR path from macOS Accessibility reliability problems.

3. **Use a hardcoded hotkey first: `Control + Option + Space`.**
   Reason: settings UI is unnecessary before the capture path works.

4. **Prefer stable chunked updates over noisy live token churn.**
   Reason: this is a better fit for early `whisper.cpp` integration and a clearer prototype UX.

5. **Treat packaging/shipping as a TODO and allow external local dependencies for now.**
   Reason: end-user distribution should not block prototype validation.
