# Lisper Ephemeral Modal Product Design

Date: 2026-04-25
Status: Approved for implementation

## Goal

Make Lisper feel like a lightweight, native macOS dictation companion whose primary interface is an ephemeral modal, not a persistent app window. The daily workflow is: press a configurable hotkey, speak, see a small reactive voice overlay, then get a stacked raw/enhanced transcript that can be copied or pasted.

The persistent app UI exists mainly for settings: hotkey, model configuration, automation, and appearance.

## Product Direction

Lisper should feel dreamy, flowy, and iridescent, with a "melody in dreamland" visual language. The expressive surface is the ephemeral modal. The settings UI should be calm and utilitarian, while still sharing the same light/dark iridescent theme.

The app should preserve a local-first architecture while allowing advanced users to replace either local model with a remote endpoint and API key.

## Core Flow

### Hotkey Behavior

- Default hotkey: Right Option.
- The hotkey is configurable in settings.
- Tap behavior: toggles listening on or off.
- Hold behavior: push-to-talk. Listening starts while the key is held and stops when it is released.
- If both tap and hold interactions are possible for the same key, the app should distinguish them by press duration.
- The hotkey should open the ephemeral modal when listening starts.

### Listening State

When listening starts, Lisper shows a small center-bottom overlay modal. The modal contains a single reactive orb. The orb should own all voice feedback:

- The orb morphs with microphone energy.
- A small particle or field effect around the orb reacts to audio levels.
- The UI should not use a separate waveform row in MVP.
- The listening state should make it visually obvious that the app can hear the user without showing raw audio machinery.

### Stop And Processing State

When recording stops:

- The modal animates and expands.
- The original transcript appears first.
- If cleanup is enabled, the cleanup model starts processing.
- While cleanup runs, the modal shows a non-blocking loading state for the enhanced result.
- The original transcript remains visible and copyable while cleanup is running.

### Result State

The result state uses stacked text blocks:

1. `Original`
2. `Enhanced`

This is the MVP behavior because stacked blocks make it easy to compare what changed. Animated text diffs, Grammarly-style marked additions/deletions, punctuation changes, and replacement animations are a post-MVP stretch goal.

## Copy Behavior

Each text block is a copy target.

- Clicking anywhere inside a text bubble copies that text.
- A copy icon appears in the bottom-right corner of the text bubble as the clear call to action.
- The icon is an affordance; it is not the only clickable area.
- Copying raw and enhanced text are separate actions.
- Text bubbles should have an iridescent highlight treatment that subtly reacts to the mouse cursor.
- Cursor reactivity is MVP scope for the modal result state.

### Copy Feedback

Copy feedback must not move the layout.

- Reserve a fixed-height microcopy row under each text bubble.
- When text is copied, show `Text copied` in that row.
- The message fades out after a few seconds.
- A subtle shimmer animation runs when feedback appears.
- Manual copy clicks retrigger the shimmer and reset the fade-out timer.
- Auto-copy triggers the same feedback on the text block that was copied.

## Cleanup And Auto-Copy Semantics

Cleanup is optional post-processing after the speech-to-text pass.

- If cleanup is enabled and succeeds, the enhanced text is the preferred result.
- If cleanup is disabled, the original transcript is the preferred result.
- If cleanup fails, the app preserves and uses the original transcript.
- Cleanup failure should be visible but non-destructive.
- If auto-copy is enabled, Lisper copies the preferred result:
  - enhanced text when cleanup succeeds
  - original text when cleanup is disabled
  - original text when cleanup fails

## Automation Settings

### Auto-Copy

- Optional setting.
- When enabled, the app automatically copies the preferred result at the end of the session.
- It must trigger the same copy feedback as a manual copy action.

### Auto-Paste

- Optional setting.
- Off by default.
- Requires explicit opt-in because writing into the active app is higher risk than copying to clipboard.
- When enabled, the app pastes the preferred result into the currently active text field after transcription/cleanup resolves.
- If cleanup is enabled and still running, auto-paste waits for cleanup success or failure so it can paste the preferred result.
- If auto-paste fails because the target app or field is unavailable, the app should preserve the result in the modal and show a clear non-destructive error.

## Model Configuration

Lisper has two model slots:

1. Speech-to-text model
2. Cleanup text model

Each model slot supports:

- local default implementation
- remote endpoint URL override
- API key field
- `Test` button

API keys should be stored in Keychain. Non-secret endpoint configuration can be stored in app preferences.

### Speech-To-Text Slot

The default implementation is local speech-to-text.

The remote override should accept an endpoint URL and API key. The MVP test button validates:

- endpoint is reachable
- credentials are accepted
- response shape is compatible enough for Lisper to parse a transcript

The MVP test does not need to benchmark quality or latency.

### Cleanup Text Slot

The default implementation is a lightweight cleanup model.

The remote override should accept an endpoint URL and API key. The MVP test button validates:

- endpoint is reachable
- credentials are accepted
- a tiny cleanup prompt returns parseable text

The cleanup model may use text input only in MVP. Feeding the audio signal into cleanup is a desired architecture direction, but the MVP should not block on multimodal cleanup unless a local or remote model slot can support it cleanly.

## Settings UI

The settings UI is the main persistent app surface.

Required settings sections:

- Hotkey
- Models
- Automation
- Appearance

### Hotkey Settings

- Show the current hotkey.
- Allow recording a replacement hotkey.
- Default to Right Option.
- Preserve tap-to-toggle and hold-to-talk semantics.

### Models Settings

- Show speech-to-text model slot.
- Show cleanup text model slot.
- For each slot, show local default state, endpoint URL, API key field, and `Test` button.
- Show clear success/failure states for tests.

### Automation Settings

- Post-processing toggle.
- Auto-copy toggle.
- Auto-paste toggle, off by default.

### Appearance Settings

- Light mode.
- Dark mode.
- System mode if cheap to support.
- Preserve the dreamy, iridescent visual language across themes without making settings visually noisy.

## Architecture

The implementation should be split around explicit boundaries:

### Session Coordinator

Owns the dictation lifecycle:

- hotkey event interpretation
- listening start/stop
- press duration handling for tap versus hold
- session tokens
- cancellation
- final result selection

### Audio Feedback Model

Receives microphone samples or summary levels and exposes lightweight UI state for the orb:

- current energy
- smoothed energy
- recent peaks or particle intensity
- speaking/silence state if useful

This model should not perform transcription.

### Transcription Service

Converts audio into raw text. It should have a protocol boundary so local and remote implementations are interchangeable.

### Cleanup Service

Converts raw transcript, and later optional audio context, into enhanced text. It should have a protocol boundary so local and remote implementations are interchangeable.

### Copy/Paste Service

Owns clipboard writes and active-field paste behavior.

Clipboard copy should be reliable in MVP. Active-field paste should be explicit opt-in and fail safely.

### Settings Store

Owns persisted user preferences:

- hotkey
- model endpoints
- automation toggles
- appearance

Secrets must not be stored in plain app preferences.

## MVP Scope

MVP includes:

- center-bottom ephemeral modal
- reactive orb with particle/field audio feedback
- tap-to-toggle and hold-to-talk hotkey semantics
- configurable hotkey with Right Option default
- raw transcript display after stop
- cleanup processing after stop
- stacked original/enhanced result blocks
- full-bubble click-to-copy behavior
- bottom-right copy affordance
- non-layout-shifting `Text copied` shimmer feedback
- cursor-reactive iridescent text bubble effects
- auto-copy setting and preferred-result semantics
- auto-paste setting, off by default
- settings UI for hotkey, models, automation, and appearance
- remote endpoint/API key/test controls for both model slots

## Post-MVP Stretch Goals

- Animated diff between original and enhanced transcript.
- Marked additions, deletions, punctuation changes, and replacements.
- Multimodal cleanup that uses both audio signal and transcript when the active cleanup model supports it.
- Provider-specific presets for common remote APIs.
- Transcription quality and latency benchmarking from settings.
- More advanced focus-target insertion that tracks and rewrites a session-owned span.

## Failure Model

### Microphone Permission

If microphone permission is unavailable, listening should not start. The modal or settings UI should show a clear recovery message.

### Accessibility Permission

Accessibility permission is only required for active-field paste or richer focused-field behavior. If it is missing, auto-paste should fail safely and leave the transcript copyable in the modal.

### Cleanup Failure

If cleanup fails:

- keep original transcript visible
- show an error state for enhanced text
- auto-copy original if auto-copy is enabled
- do not discard the session result

### Remote Model Failure

Remote model failures should report enough detail for the user to fix endpoint/key issues without exposing secrets.

### Copy Failure

Clipboard copy failures should show copy feedback only on success. If copy fails, show a small non-destructive failure message in the same reserved feedback area.

### Auto-Paste Failure

Auto-paste failures should not retry indefinitely. They should leave the result visible and copyable.

## Testing Requirements

Automated tests should cover:

- session result selection when cleanup succeeds, is disabled, or fails
- auto-copy target selection
- copy feedback state timing/retrigger behavior
- cursor-reactive text bubble state with deterministic pointer positions
- settings persistence for automation toggles and endpoints
- remote model test success/failure parsing with fake clients
- audio feedback level smoothing with deterministic sample arrays
- stale session events ignored by session token

Manual verification should cover:

- hotkey tap-to-toggle
- hotkey hold-to-talk
- modal positioning
- orb responsiveness to microphone input
- copy by clicking text bubble
- auto-copy feedback
- cursor-reactive iridescent text bubble feedback
- settings test buttons
- auto-paste off by default
