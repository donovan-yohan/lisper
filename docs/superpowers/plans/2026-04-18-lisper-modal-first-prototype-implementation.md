# Lisper Modal-First Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working macOS prototype that captures real microphone audio through `whisper.cpp`'s streaming binary and shows live transcript updates in a normal app window.

**Architecture:** Add a real macOS app executable that wraps a protocol-driven `whisper-stream` session runner, then bind its state into a SwiftUI window with a hardcoded global hotkey. Keep the process/output parsing layer testable with fake runners so the real mic/whisper path is the only manual verification boundary.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, AppKit, Carbon, Foundation, XCTest, local `whisper.cpp`

---

### Task 1: Build the whisper process layer and transcript parser

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LisperCore/WhisperStreaming.swift`
- Create: `Tests/LisperCoreTests/WhisperStreamingTests.swift`

- [ ] **Step 1: Write the failing parser and configuration tests**

```swift
import XCTest
@testable import LisperCore

final class WhisperStreamingTests: XCTestCase {
    func testParserExtractsTranscriptLinesFromWhisperStreamOutput() {
        let parser = WhisperStreamOutputParser()

        XCTAssertEqual(
            parser.consume("[00:00:00.000 --> 00:00:01.200] hello world"),
            .transcript("hello world")
        )
    }

    func testEnvironmentOverridesDependencyResolution() throws {
        let resolver = WhisperDependencyResolver(
            environment: [
                "LISPER_WHISPER_STREAM": "/tmp/whisper-stream",
                "LISPER_WHISPER_MODEL": "/tmp/model.bin"
            ],
            fileExists: { _ in true }
        )

        XCTAssertEqual(
            try resolver.resolve(),
            WhisperDependency(streamBinary: URL(fileURLWithPath: "/tmp/whisper-stream"),
                              model: URL(fileURLWithPath: "/tmp/model.bin"))
        )
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WhisperStreamingTests`
Expected: FAIL because the whisper streaming layer does not exist yet.

- [ ] **Step 3: Implement the dependency resolver, parser, and process abstractions**

```swift
public struct WhisperDependency: Equatable {
    public let streamBinary: URL
    public let model: URL
}

public struct WhisperStreamOutputParser {
    public mutating func consume(_ line: String) -> WhisperStreamEvent? { ... }
}

public protocol WhisperStreamingSession: AnyObject {
    var updates: AsyncStream<WhisperStreamEvent> { get }
    func start() throws
    func stop()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WhisperStreamingTests`
Expected: PASS with `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/LisperCore/WhisperStreaming.swift Tests/LisperCoreTests/WhisperStreamingTests.swift
git commit -m "feat: add whisper streaming core"
```

### Task 2: Build the app state model, hotkey plumbing, and fake-backed tests

**Files:**
- Create: `Sources/LisperCore/AppModel.swift`
- Create: `Tests/LisperCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing app-model tests**

```swift
import XCTest
@testable import LisperCore

final class AppModelTests: XCTestCase {
    func testStartRecordingTransitionsToRecordingState() async throws {
        let model = LisperAppModel(...)
        try await model.startRecording()
        XCTAssertEqual(model.phase, .recording)
    }

    func testTranscriptUpdatesReplaceVisibleText() async throws {
        let model = LisperAppModel(...)
        try await model.startRecording()
        await model.handle(.transcript("hello"))
        XCTAssertEqual(model.transcriptText, "hello")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppModelTests`
Expected: FAIL because the app model does not exist yet.

- [ ] **Step 3: Implement the observable model and hotkey-facing commands**

```swift
@MainActor
public final class LisperAppModel: ObservableObject {
    @Published public private(set) var phase: AppPhase = .idle
    @Published public private(set) var transcriptText: String = ""
    @Published public private(set) var statusText: String = "Idle"

    public func startRecording() async throws { ... }
    public func stopRecording() { ... }
    public func handle(_ event: WhisperStreamEvent) async { ... }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS with `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LisperCore/AppModel.swift Tests/LisperCoreTests/AppModelTests.swift
git commit -m "feat: add app model for live transcription"
```

### Task 3: Add the real macOS app executable and manual-verification tooling

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LisperCore/WhisperProcessSession.swift`
- Create: `Sources/lisper-app/main.swift`
- Create: `Sources/lisper-app/AppSupport.swift`
- Create: `Tests/LisperCoreTests/AppExecutableSmokeTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Write the failing executable smoke tests**

```swift
import XCTest
@testable import LisperCore

final class AppExecutableSmokeTests: XCTestCase {
    func testHotkeyConstantIsDocumentedAndStable() {
        XCTAssertEqual(LisperDefaults.hotkeyDisplay, "Control + Option + Space")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppExecutableSmokeTests`
Expected: FAIL because the app executable defaults do not exist yet.

- [ ] **Step 3: Implement the SwiftUI app shell and hardcoded hotkey**

```swift
@main
struct LisperPrototypeApp: App {
    var body: some Scene {
        WindowGroup("Lisper") {
            LisperContentView(model: ...)
        }
    }
}
```

```swift
enum LisperDefaults {
    static let hotkeyDisplay = "Control + Option + Space"
}
```

- [ ] **Step 4: Run the targeted tests and manual commands**

Run: `swift test --filter AppExecutableSmokeTests`
Expected: PASS with `0 failures`.

Run: `swift build --product lisper-app`
Expected: PASS with exit code `0`.

Manual:
- launch the app
- verify the window opens
- verify the hardcoded hotkey starts/stops a real session
- verify transcript text updates in the window while speaking

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/lisper-app README.md
git commit -m "feat: add macos lisper prototype app"
```

### Task 4: Add a local developer setup script for whisper.cpp

**Files:**
- Create: `scripts/setup-whisper-local.sh`
- Modify: `README.md`

- [ ] **Step 1: Write the failing documentation/setup expectations as a smoke test or shell check**

```bash
test -f scripts/setup-whisper-local.sh
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `test -f scripts/setup-whisper-local.sh`
Expected: exit code `1`.

- [ ] **Step 3: Implement the setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# clone whisper.cpp if absent
# build whisper-stream
# download a small English model if absent
# print the env vars / resolved paths
```

- [ ] **Step 4: Run the check and document the prototype path**

Run: `test -f scripts/setup-whisper-local.sh`
Expected: exit code `0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-whisper-local.sh README.md
git commit -m "chore: add local whisper setup script"
```
