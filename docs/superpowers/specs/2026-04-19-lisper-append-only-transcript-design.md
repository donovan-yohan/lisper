# Lisper Append-Only Transcript Design

Date: 2026-04-19
Status: Approved for implementation

## Goal

Keep the transcript append-only for the duration of a recording session so the text visible when recording stops contains the full message spoken from record start through record end.

Live updates may still revise recently displayed words, but silence or rolling-window resets must not delete already captured copy from earlier in the same session.

## Why Change

The in-process Whisper integration transcribes a rolling audio window. The app currently treats each decode result as the full visible transcript and replaces the textbox contents on every update.

That behavior is wrong for product use:

- early words disappear after pauses
- silence can make the textbox look like the user said less than they actually did
- stopping recording can leave only the last chunk instead of the full message

The product requirement is session-complete transcript capture, not rolling-window snapshot display.

## Scope

### In scope

- change transcript assembly in `LisperAppModel`
- preserve full-session transcript state from recording start to stop
- allow live tail rewrites while preventing deletion of committed earlier copy
- finalize the full transcript when recording stops
- add unit tests covering session accumulation and reset behavior

### Out of scope

- explicit silence detection
- token-level partial streaming
- changes to audio capture or whisper inference cadence
- punctuation/refinement improvements

## Architecture

### 1. Session transcript state

Replace the single replacement-style transcript model with two internal buffers:

- `committedTranscript`
- `liveTranscriptTail`

`committedTranscript` stores append-only text that is considered stable for the current session.

`liveTranscriptTail` stores the mutable trailing portion that the rolling decoder is still allowed to revise.

The UI-facing `transcriptText` is derived from these two buffers and rendered as one normalized string.

### 2. Update boundary

Each new rolling decode is interpreted as either:

- a revision of the current live tail
- a continuation after earlier committed text

The model must preserve committed text and only rewrite the live tail. If a new decode no longer meaningfully overlaps the current tail, the existing tail is committed and the new decode becomes the next live tail.

### 3. Session finalization

When the user stops recording, any remaining live tail is committed into the session transcript before the app returns to idle.

This guarantees that the last visible transcript after stop is the full session transcript.

## Runtime Model

### Recording start

Starting a new recording session must clear all session transcript state:

- empty `committedTranscript`
- empty `liveTranscriptTail`
- empty `transcriptText`

No transcript state carries across sessions.

### Live transcript updates

For each incoming transcript snapshot:

1. normalize the snapshot the same way the current product path already expects
2. compare it against the current `liveTranscriptTail`
3. if it is a revision of the same trailing phrase, replace only `liveTranscriptTail`
4. if it has moved on to later speech and no longer overlaps enough with the current tail, append the old tail into `committedTranscript` and set the new snapshot as `liveTranscriptTail`
5. recompute `transcriptText`

This keeps the live UX responsive while preserving the full message across pauses.

### Recording stop

On stop:

1. commit any remaining `liveTranscriptTail`
2. clear the mutable tail
3. leave `transcriptText` showing the full committed session transcript
4. transition app state to idle

## Matching Rule

The first implementation should use a pragmatic text-overlap heuristic rather than a full diff engine.

Recommended rule:

- trim and normalize whitespace for comparisons
- look for overlap between the end of the current session display and the beginning of the new snapshot
- treat a meaningful overlap as a tail revision
- treat no meaningful overlap as a new chunk that should be appended after committing the old tail

This is intentionally simple. The goal is correct session accumulation, not linguistically perfect merge behavior.

If a later iteration proves this heuristic too weak, the merge logic can be upgraded without changing the public model contract.

## Testing Strategy

### Automated

Add `LisperAppModel` tests for:

- repeated live updates that revise a trailing phrase without losing earlier text
- a pause/new phrase transition that appends instead of replacing
- stopping recording preserves the full accumulated transcript
- starting a new session clears prior transcript state
- stale session events do not mutate the current session transcript

### Manual

Manual verification should confirm:

1. start recording
2. speak a multi-part sentence with a pause in the middle
3. confirm earlier words remain visible while later words continue updating
4. stop recording
5. confirm the textbox contains the full message from the entire session

## Failure Model

### Weak overlap match

If the overlap heuristic cannot confidently align two adjacent snapshots, the system should prefer preserving prior text by committing the old tail and appending a new one rather than replacing the entire transcript.

This may occasionally duplicate a few words, but it is preferable to losing content from the session.

### Session interruption

If recording fails mid-session, the latest committed transcript plus any live tail already shown should remain visible until the next recording starts.

## Decisions Log

1. **Preserve full-session transcript state in the app model.**
   Reason: the product contract is "everything spoken during this recording", not "latest rolling window output".

2. **Allow the trailing phrase to remain mutable during recording.**
   Reason: Whisper snapshots can improve recent words, and the UI should still benefit from those revisions.

3. **Use a simple overlap heuristic for the first merge implementation.**
   Reason: this is the smallest change that fixes the product bug without introducing a heavier transcript diff system.

4. **Finalize by committing the live tail on stop.**
   Reason: the user expects the textbox content at stop time to be ready to send as the full message.
