# Lisper Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local macOS Swift demo that exercises Lisper's live/final session model, modal/focused-target output routing, and safe fallback behavior in a way that can be run and tested inside a coding agent.

**Architecture:** Use a Swift Package as the delivery vehicle so the demo is runnable with `swift run` and verifiable with `swift test`. Split responsibilities into a reusable `LisperCore` library for session orchestration and adapters, plus a `lisper-demo` executable that drives the core with a scripted streaming engine and prints a timeline of partial and final transcript events.

**Tech Stack:** Swift 6.2, Swift Package Manager, XCTest, Foundation

---

### Task 1: Scaffold the package and core session types

**Files:**
- Create: `Package.swift`
- Create: `Sources/LisperCore/Models.swift`
- Create: `Sources/LisperCore/SessionController.swift`
- Test: `Tests/LisperCoreTests/SessionControllerTests.swift`

- [ ] **Step 1: Write the failing tests for the session state machine**

```swift
import XCTest
@testable import LisperCore

final class SessionControllerTests: XCTestCase {
    func testLiveModeStreamsPartialsAndCommitsFinalTranscript() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel", "hello"], final: "hello")
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .live,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        try await controller.runSession()

        XCTAssertEqual(target.events, [
            .partial("hel"),
            .partial("hello"),
            .final("hello")
        ])
    }

    func testFinalModeSuppressesPartialsUntilFinalTranscript() async throws {
        let engine = ScriptedStreamingEngine(partials: ["hel", "hello"], final: "hello")
        let target = RecordingOutputTarget()
        let controller = SessionController(
            mode: .finalOnly,
            outputTarget: target,
            engine: engine,
            refinement: PassthroughRefinementProcessor()
        )

        try await controller.runSession()

        XCTAssertEqual(target.events, [.final("hello")])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SessionControllerTests`
Expected: FAIL because `LisperCore` types do not exist yet.

- [ ] **Step 3: Implement the minimum package and core types**

```swift
public enum TranscriptionMode {
    case live
    case finalOnly
}

public enum TranscriptEvent: Equatable {
    case partial(String)
    case final(String)
}

public protocol ASREngine {
    func transcriptEvents() -> AsyncThrowingStream<TranscriptEvent, Error>
}

public protocol OutputTarget: AnyObject {
    func handle(_ event: TranscriptEvent) async throws
}

public protocol RefinementProcessor {
    func refine(_ transcript: String) async throws -> String
}
```

```swift
public final class SessionController {
    public init(
        mode: TranscriptionMode,
        outputTarget: OutputTarget,
        engine: ASREngine,
        refinement: RefinementProcessor
    ) { ... }

    public func runSession() async throws {
        for try await event in engine.transcriptEvents() {
            switch (mode, event) {
            case (.live, .partial):
                try await outputTarget.handle(event)
            case (_, .final(let transcript)):
                let refined = try await refinement.refine(transcript)
                try await outputTarget.handle(.final(refined))
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SessionControllerTests`
Expected: PASS with `2 tests` and `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/LisperCore Tests/LisperCoreTests
git commit -m "feat: scaffold lisper core session pipeline"
```

### Task 2: Add focused-target rewrite semantics and fallback behavior

**Files:**
- Modify: `Sources/LisperCore/Models.swift`
- Modify: `Sources/LisperCore/SessionController.swift`
- Create: `Sources/LisperCore/OutputTargets.swift`
- Test: `Tests/LisperCoreTests/FocusedOutputTargetTests.swift`

- [ ] **Step 1: Write the failing tests for rewrite-span safety and fallback**

```swift
import XCTest
@testable import LisperCore

final class FocusedOutputTargetTests: XCTestCase {
    func testFocusedTargetRewritesOwnedSpanAcrossPartials() async throws {
        let sink = SimulatedTextSink(initialText: "prefix ")
        let target = FocusedTextFieldOutputTarget(sink: sink)

        try await target.handle(.partial("hel"))
        try await target.handle(.partial("hello"))
        try await target.handle(.final("hello world"))

        XCTAssertEqual(sink.text, "prefix hello world")
        XCTAssertEqual(sink.operations, [.insert("hel"), .replaceOwnedSpan(with: "hello"), .replaceOwnedSpan(with: "hello world")])
    }

    func testFocusedTargetFallsBackToAppendFinalWhenRewriteFails() async throws {
        let sink = SimulatedTextSink(initialText: "prefix ", failOnRewrite: true)
        let target = FocusedTextFieldOutputTarget(sink: sink)

        try await target.handle(.partial("hel"))
        try await target.handle(.final("hello"))

        XCTAssertEqual(sink.text, "prefix helhello")
        XCTAssertEqual(sink.didFallbackToFinalAppend, true)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FocusedOutputTargetTests`
Expected: FAIL because focused-target adapters do not exist yet.

- [ ] **Step 3: Implement the focused-target adapter and simulation sink**

```swift
public protocol TextSink: AnyObject {
    var text: String { get }
    func insert(_ text: String) async throws
    func replaceOwnedSpan(with text: String) async throws
    func appendFinal(_ text: String) async throws
}

public final class FocusedTextFieldOutputTarget: OutputTarget {
    public init(sink: TextSink) { ... }

    public func handle(_ event: TranscriptEvent) async throws {
        switch event {
        case .partial(let text):
            if hasOwnedSpan {
                do { try await sink.replaceOwnedSpan(with: text) }
                catch { try await sink.appendFinal(text) }
            } else {
                try await sink.insert(text)
                hasOwnedSpan = true
            }
        case .final(let text):
            if hasOwnedSpan {
                do { try await sink.replaceOwnedSpan(with: text) }
                catch { try await sink.appendFinal(text) }
            } else {
                try await sink.appendFinal(text)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FocusedOutputTargetTests`
Expected: PASS with `2 tests` and `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LisperCore Tests/LisperCoreTests
git commit -m "feat: add focused target rewrite and fallback simulation"
```

### Task 3: Add a runnable demo executable and end-to-end verification

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LisperCore/DemoRunner.swift`
- Create: `Sources/lisper-demo/main.swift`
- Create: `Tests/LisperCoreTests/DemoIntegrationTests.swift`
- Create: `README.md`

- [ ] **Step 1: Write the failing integration tests for the demo output**

```swift
import XCTest
@testable import LisperCore

final class DemoIntegrationTests: XCTestCase {
    func testScriptedDemoProducesLiveTimeline() async throws {
        let transcript = try await DemoRunner().run(
            mode: .live,
            targetKind: .modal,
            partials: ["Lis", "Lisper"],
            final: "Lisper demo"
        )

        XCTAssertTrue(transcript.contains("[partial] Lis"))
        XCTAssertTrue(transcript.contains("[partial] Lisper"))
        XCTAssertTrue(transcript.contains("[final] Lisper demo"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DemoIntegrationTests`
Expected: FAIL because the demo executable helpers do not exist yet.

- [ ] **Step 3: Implement the demo runner and CLI entrypoint**

```swift
@main
struct LisperDemoApp {
    static func main() async throws {
        let runner = DemoRunner()
        let output = try await runner.run(
            mode: .live,
            targetKind: .focusedTextField,
            partials: ["thi", "this is"],
            final: "this is lisper"
        )
        print(output)
    }
}
```

```swift
public struct DemoRunner {
    public func run(
        mode: TranscriptionMode,
        targetKind: DemoTargetKind,
        partials: [String],
        final: String
    ) async throws -> String { ... }
}
```

- [ ] **Step 4: Run the full test suite and the demo**

Run: `swift test`
Expected: PASS with `0 failures`.

Run: `swift run lisper-demo`
Expected: Prints a readable transcript timeline showing partial updates, final output, and the focused-target fallback or rewrite behavior.

- [ ] **Step 5: Commit**

```bash
git add README.md Sources/lisper-demo Tests/LisperCoreTests
git commit -m "feat: add lisper coding-agent demo"
```
