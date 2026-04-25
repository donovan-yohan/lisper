# Lisper Whisper Library Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the subprocess-based Whisper prototype with an in-process `libwhisper` integration that captures microphone audio and updates the app window transcript directly while the user speaks.

**Architecture:** Add a `CWhisper` shim target and a Swift runtime layer that combines `AVAudioEngine` capture, a rolling PCM buffer, and periodic `whisper_full` calls. The app window must render app-owned live transcript state only, while diagnostics remain separate.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, AppKit, AVFoundation, Carbon, C interoperability, local `libwhisper`

---

### Task 1: Add `CWhisper` bindings and in-process transcriber core

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CWhisper/module.modulemap`
- Create: `Sources/CWhisper/shim.h`
- Create: `Sources/LisperCore/WhisperLibraryTranscriber.swift`
- Create: `Tests/LisperCoreTests/WhisperLibraryTranscriberTests.swift`

- [ ] **Step 1: Write the failing binding/config tests**

```swift
import XCTest
@testable import LisperCore

final class WhisperLibraryTranscriberTests: XCTestCase {
    func testWhisperRuntimeDefaultsUseExpectedWindowing() {
        XCTAssertEqual(WhisperRuntimeDefaults.windowDurationSeconds, 5.0)
        XCTAssertEqual(WhisperRuntimeDefaults.updateIntervalSeconds, 1.0)
    }

    func testTranscriptNormalizerJoinsDecodedSegments() {
        XCTAssertEqual(
            WhisperTranscriptNormalizer.normalize(["hello", "world"]),
            "hello world"
        )
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WhisperLibraryTranscriberTests`
Expected: FAIL because the transcriber core and bindings do not exist yet.

- [ ] **Step 3: Implement the shim target and transcriber shell**

```c
module CWhisper [system] {
  header "shim.h"
  export *
}
```

```swift
public enum WhisperRuntimeDefaults {
    public static let sampleRate: Int = 16000
    public static let windowDurationSeconds: Double = 5.0
    public static let updateIntervalSeconds: Double = 1.0
}

public struct WhisperTranscriptNormalizer {
    public static func normalize(_ segments: [String]) -> String { ... }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WhisperLibraryTranscriberTests`
Expected: PASS with `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CWhisper Sources/LisperCore/WhisperLibraryTranscriber.swift Tests/LisperCoreTests/WhisperLibraryTranscriberTests.swift
git commit -m "feat: add whisper library bindings and transcriber core"
```

### Task 2: Add in-process audio capture and session driver

**Files:**
- Create: `Sources/LisperCore/AudioCaptureService.swift`
- Modify: `Sources/LisperCore/AppModel.swift`
- Create: `Tests/LisperCoreTests/AudioCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing audio/session tests**

```swift
import XCTest
@testable import LisperCore

final class AudioCaptureServiceTests: XCTestCase {
    func testRollingAudioBufferKeepsMostRecentWindow() {
        var buffer = RollingAudioBuffer(maxSamples: 4)
        buffer.append([1, 2, 3])
        buffer.append([4, 5])
        XCTAssertEqual(buffer.snapshot(), [2, 3, 4, 5])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AudioCaptureServiceTests`
Expected: FAIL because the audio capture layer does not exist yet.

- [ ] **Step 3: Implement rolling audio capture and session hooks**

```swift
public struct RollingAudioBuffer {
    public mutating func append(_ samples: [Float]) { ... }
    public func snapshot() -> [Float] { ... }
}

@MainActor
public final class LisperAppModel: ObservableObject {
    public func applyLiveTranscript(_ transcript: String, from sessionToken: AppSessionToken) { ... }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AudioCaptureServiceTests`
Expected: PASS with `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LisperCore/AudioCaptureService.swift Sources/LisperCore/AppModel.swift Tests/LisperCoreTests/AudioCaptureServiceTests.swift
git commit -m "feat: add in-process audio capture primitives"
```

### Task 3: Replace subprocess app wiring with library-backed live transcription

**Files:**
- Modify: `Sources/lisper-app/AppSupport.swift`
- Modify: `Tests/LisperCoreTests/AppExecutableSmokeTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Write/adjust failing smoke tests for the new runtime path**

```swift
import XCTest
@testable import LisperCore

final class AppExecutableSmokeTests: XCTestCase {
    func testHotkeyConstantIsDocumentedAndStable() {
        XCTAssertEqual(LisperDefaults.hotkeyDisplay, "Control + Option + Space")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail if the old subprocess assumptions remain**

Run: `swift test --filter AppExecutableSmokeTests`
Expected: FAIL or require updates because the old process-launch invariants no longer apply.

- [ ] **Step 3: Implement the app coordinator around in-process transcription**

```swift
@MainActor
final class LisperAppCoordinator: ObservableObject {
    // hotkey start/stop
    // audio capture start/stop
    // periodic transcription task
    // direct updates into model transcript state
}
```

- [ ] **Step 4: Run verification**

Run: `swift test`
Expected: PASS with `0 failures`.

Run: `swift build --product lisper-app`
Expected: PASS with exit code `0`.

Manual:
- launch `swift run lisper-app`
- press hotkey
- speak
- confirm textbox updates live without depending on transcript log files

- [ ] **Step 5: Commit**

```bash
git add Sources/lisper-app Tests/LisperCoreTests README.md
git commit -m "feat: switch lisper app to in-process whisper library transcription"
```
