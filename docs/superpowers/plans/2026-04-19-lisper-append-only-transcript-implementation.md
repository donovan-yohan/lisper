# Lisper Append-Only Transcript Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the full transcript for one recording session from start to stop while still allowing live rewrites of the current trailing phrase.

**Architecture:** Keep transcript assembly inside `LisperAppModel` by replacing the current single replacement-style string with a committed prefix plus a mutable live tail. Drive the change test-first so session accumulation, stop finalization, and reset behavior are covered at the model layer.

**Tech Stack:** Swift, XCTest, Combine-backed `ObservableObject` state in `LisperCore`

---

### Task 1: Lock The Intended Transcript Behavior In Tests

**Files:**
- Modify: `Tests/LisperCoreTests/AppModelTests.swift`
- Modify: `Tests/LisperCoreTests/AudioCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testTranscriptUpdatesAccumulateAcrossRollingWindowResets() async throws
func testStopRecordingPreservesAccumulatedTranscript() async throws
func testStartingNewSessionClearsCommittedTranscript() async throws
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `swift test --filter AppModelTests`
Expected: FAIL because the model still replaces `transcriptText` with the latest snapshot.

### Task 2: Implement Session Transcript Assembly

**Files:**
- Modify: `Sources/LisperCore/AppModel.swift`

- [ ] **Step 1: Add session-scoped transcript buffers**

```swift
private var committedTranscript: String = ""
private var liveTranscriptTail: String = ""
```

- [ ] **Step 2: Replace direct transcript assignment with merge logic**

```swift
private func applyTranscript(_ transcript: String, from sessionToken: AppSessionToken)
private func mergeTranscriptSnapshot(_ transcript: String)
private func commitLiveTranscriptTail()
private func rebuildTranscriptText()
```

- [ ] **Step 3: Finalize the live tail when recording stops or fails without clearing the visible transcript**

```swift
public func finishRecording(for sessionToken: AppSessionToken)
public func stopRecording()
```

- [ ] **Step 4: Run the targeted tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS

### Task 3: Guard Regression Paths

**Files:**
- Modify: `Tests/LisperCoreTests/AudioCaptureServiceTests.swift`
- Modify: `Tests/LisperCoreTests/AppModelTests.swift`

- [ ] **Step 1: Adjust existing replacement-oriented assertions to the new accumulation model**

```swift
XCTAssertEqual(model.transcriptText, "hello live")
```

- [ ] **Step 2: Run the focused suite for model and audio-capture interactions**

Run: `swift test --filter 'AppModelTests|AudioCaptureServiceTests'`
Expected: PASS

- [ ] **Step 3: Run the full package tests**

Run: `swift test`
Expected: PASS
