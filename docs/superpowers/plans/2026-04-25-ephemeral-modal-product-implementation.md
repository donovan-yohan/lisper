# Ephemeral Modal Product Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Lisper's ephemeral modal dictation workflow with reactive voice feedback, stacked raw/enhanced results, copy feedback, configurable models, and settings-backed automation.

**Architecture:** Ship as stacked PRs. First establish the current SwiftPM prototype as a tracked baseline, then add core state/services, then add the modal/settings UI, then wire hotkey/session automation end to end. Keep model/config/copy/audio-feedback logic in `LisperCore`; keep AppKit/SwiftUI windows and views in `Sources/lisper-app`.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit, AVFoundation, Carbon hotkeys, XCTest, macOS 15.

---

## Stack Order

1. `dy/ephemeral-modal-spec` -> `main`
   - Product spec and this implementation plan.
2. `dy/ephemeral-modal-baseline` -> `dy/ephemeral-modal-spec`
   - Track the current SwiftPM prototype and verify it builds/tests.
3. `dy/ephemeral-modal-core` -> `dy/ephemeral-modal-baseline`
   - Core settings, audio feedback, result selection, model slot testing, and copy/paste services.
4. `dy/ephemeral-modal-ui` -> `dy/ephemeral-modal-core`
   - Ephemeral modal, reactive orb, copy bubbles, and settings UI.
5. `dy/ephemeral-modal-integration` -> `dy/ephemeral-modal-ui`
   - Hotkey tap/hold semantics, app coordination, auto-copy/auto-paste, verification, README updates.

## File Structure

- `Sources/LisperCore/AppModel.swift`: session state, transcript assembly, result state, automation decisions.
- `Sources/LisperCore/AppSettings.swift`: persisted settings data types and defaults.
- `Sources/LisperCore/AudioFeedbackModel.swift`: deterministic audio-level smoothing for orb/particle UI.
- `Sources/LisperCore/TranscriptResult.swift`: raw/enhanced result state and preferred-output rules.
- `Sources/LisperCore/ModelConfiguration.swift`: local/remote model slot config and test result types.
- `Sources/LisperCore/ClipboardServices.swift`: clipboard and active-field paste protocols plus test fakes.
- `Sources/lisper-app/AppSupport.swift`: app coordinator, hotkey monitor, diagnostics.
- `Sources/lisper-app/EphemeralModalView.swift`: listening/processing/result modal UI.
- `Sources/lisper-app/SettingsView.swift`: persistent settings UI.
- `Tests/LisperCoreTests/*`: deterministic unit coverage for core behavior.

## Task 1: Commit The Current SwiftPM Prototype Baseline

**Branch:** `dy/ephemeral-modal-baseline`

**Files:**
- Create/track: `Package.swift`
- Create/track: `README.md`
- Create/track: `Sources/**`
- Create/track: `Tests/**`
- Create/track: `scripts/setup-whisper-local.sh`
- Create/track: existing `docs/superpowers/specs/2026-04-18-*.md`
- Create/track: existing `docs/superpowers/specs/2026-04-19-*.md`
- Create/track: existing `docs/superpowers/plans/2026-04-17-*.md`
- Create/track: existing `docs/superpowers/plans/2026-04-18-*.md`
- Create/track: existing `docs/superpowers/plans/2026-04-19-*.md`

- [ ] **Step 1: Create the stack branch**

```bash
git switch -c dy/ephemeral-modal-baseline dy/ephemeral-modal-spec
```

- [ ] **Step 2: Verify build before staging**

```bash
swift build --product lisper-app
```

Expected: `Build of product 'lisper-app' complete`.

- [ ] **Step 3: Run the focused baseline tests**

```bash
swift test --filter 'AppModelTests|AudioCaptureServiceTests|AppExecutableSmokeTests'
```

Expected: all selected tests pass.

- [ ] **Step 4: Stage only source/docs/scripts, not generated artifacts**

```bash
git add Package.swift README.md Sources Tests scripts docs/superpowers/specs/2026-04-18-lisper-modal-first-prototype-design.md docs/superpowers/specs/2026-04-18-lisper-whisper-library-integration-design.md docs/superpowers/specs/2026-04-19-lisper-append-only-transcript-design.md docs/superpowers/plans/2026-04-17-lisper-demo-implementation.md docs/superpowers/plans/2026-04-18-lisper-modal-first-prototype-implementation.md docs/superpowers/plans/2026-04-18-lisper-whisper-library-integration-implementation.md docs/superpowers/plans/2026-04-19-lisper-append-only-transcript-implementation.md
git diff --cached --stat
```

Expected: source, tests, scripts, and historical docs only.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: add SwiftPM Lisper prototype baseline"
```

## Task 2: Add Core Settings And Result Semantics

**Branch:** `dy/ephemeral-modal-core`

**Files:**
- Create: `Sources/LisperCore/AppSettings.swift`
- Create: `Sources/LisperCore/TranscriptResult.swift`
- Create: `Sources/LisperCore/ModelConfiguration.swift`
- Modify: `Sources/LisperCore/AppModel.swift`
- Test: `Tests/LisperCoreTests/AppSettingsTests.swift`
- Test: `Tests/LisperCoreTests/TranscriptResultTests.swift`
- Test: `Tests/LisperCoreTests/AppModelTests.swift`

- [ ] **Step 1: Create the branch**

```bash
git switch -c dy/ephemeral-modal-core dy/ephemeral-modal-baseline
```

- [ ] **Step 2: Add failing tests for preferred result selection**

Create `Tests/LisperCoreTests/TranscriptResultTests.swift`:

```swift
import XCTest
@testable import LisperCore

final class TranscriptResultTests: XCTestCase {
    func testPreferredTextUsesEnhancedWhenCleanupSucceeds() {
        let result = TranscriptResult(original: "raw text", cleanup: .succeeded("Clean text."))
        XCTAssertEqual(result.preferredText, "Clean text.")
        XCTAssertEqual(result.preferredSource, .enhanced)
    }

    func testPreferredTextUsesOriginalWhenCleanupDisabled() {
        let result = TranscriptResult(original: "raw text", cleanup: .disabled)
        XCTAssertEqual(result.preferredText, "raw text")
        XCTAssertEqual(result.preferredSource, .original)
    }

    func testPreferredTextUsesOriginalWhenCleanupFails() {
        let result = TranscriptResult(original: "raw text", cleanup: .failed("timeout"))
        XCTAssertEqual(result.preferredText, "raw text")
        XCTAssertEqual(result.preferredSource, .original)
    }
}
```

Run:

```bash
swift test --filter TranscriptResultTests
```

Expected: fail because `TranscriptResult` does not exist.

- [ ] **Step 3: Implement transcript result types**

Create `Sources/LisperCore/TranscriptResult.swift`:

```swift
import Foundation

public enum TranscriptTextSource: Equatable {
    case original
    case enhanced
}

public enum CleanupState: Equatable {
    case disabled
    case processing
    case succeeded(String)
    case failed(String)
}

public struct TranscriptResult: Equatable {
    public var original: String
    public var cleanup: CleanupState

    public init(original: String, cleanup: CleanupState) {
        self.original = original
        self.cleanup = cleanup
    }

    public var enhancedText: String? {
        if case .succeeded(let text) = cleanup {
            return text
        }
        return nil
    }

    public var preferredText: String {
        enhancedText ?? original
    }

    public var preferredSource: TranscriptTextSource {
        enhancedText == nil ? .original : .enhanced
    }
}
```

- [ ] **Step 4: Add settings defaults tests**

Create `Tests/LisperCoreTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import LisperCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchMVPPolicy() {
        let settings = LisperSettings.defaults

        XCTAssertTrue(settings.automation.postProcessingEnabled)
        XCTAssertFalse(settings.automation.autoCopyEnabled)
        XCTAssertFalse(settings.automation.autoPasteEnabled)
        XCTAssertEqual(settings.hotkey.displayName, "Right Option")
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.speechToTextModel.kind, .local)
        XCTAssertEqual(settings.cleanupModel.kind, .local)
    }
}
```

Run:

```bash
swift test --filter AppSettingsTests
```

Expected: fail because settings types do not exist.

- [ ] **Step 5: Implement settings and model slot configuration**

Create `Sources/LisperCore/AppSettings.swift` and `Sources/LisperCore/ModelConfiguration.swift` with `Equatable`, `Sendable` value types:

```swift
import Foundation

public struct LisperSettings: Equatable, Sendable {
    public var hotkey: HotkeySettings
    public var automation: AutomationSettings
    public var appearance: AppearanceSettings
    public var speechToTextModel: ModelSlotConfiguration
    public var cleanupModel: ModelSlotConfiguration

    public static let defaults = LisperSettings(
        hotkey: .rightOption,
        automation: .defaults,
        appearance: .system,
        speechToTextModel: .local(slot: .speechToText),
        cleanupModel: .local(slot: .cleanupText)
    )
}

public struct HotkeySettings: Equatable, Sendable {
    public var displayName: String
    public var keyCode: Int
    public var modifierFlags: UInt64

    public static let rightOption = HotkeySettings(displayName: "Right Option", keyCode: 61, modifierFlags: 0)
}

public struct AutomationSettings: Equatable, Sendable {
    public var postProcessingEnabled: Bool
    public var autoCopyEnabled: Bool
    public var autoPasteEnabled: Bool

    public static let defaults = AutomationSettings(
        postProcessingEnabled: true,
        autoCopyEnabled: false,
        autoPasteEnabled: false
    )
}

public enum AppearanceSettings: String, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark
}
```

```swift
import Foundation

public enum ModelSlot: String, Equatable, Sendable, CaseIterable {
    case speechToText
    case cleanupText
}

public enum ModelSlotKind: Equatable, Sendable {
    case local
    case remote
}

public struct ModelSlotConfiguration: Equatable, Sendable {
    public var slot: ModelSlot
    public var kind: ModelSlotKind
    public var endpointURL: String
    public var apiKeyReference: String?

    public static func local(slot: ModelSlot) -> ModelSlotConfiguration {
        ModelSlotConfiguration(slot: slot, kind: .local, endpointURL: "", apiKeyReference: nil)
    }
}
```

- [ ] **Step 6: Extend `LisperAppModel` with settings and final result state**

Add published properties:

```swift
@Published public private(set) var settings: LisperSettings = .defaults
@Published public private(set) var transcriptResult: TranscriptResult?
```

Update reset/finish/fail paths so `transcriptResult` is `nil` on new session and becomes `TranscriptResult(original: transcriptText, cleanup: settings.automation.postProcessingEnabled ? .processing : .disabled)` when a recording finishes.

- [ ] **Step 7: Verify**

```bash
swift test --filter 'TranscriptResultTests|AppSettingsTests|AppModelTests'
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/LisperCore/AppSettings.swift Sources/LisperCore/ModelConfiguration.swift Sources/LisperCore/TranscriptResult.swift Sources/LisperCore/AppModel.swift Tests/LisperCoreTests/AppSettingsTests.swift Tests/LisperCoreTests/TranscriptResultTests.swift Tests/LisperCoreTests/AppModelTests.swift
git commit -m "feat: add modal result and settings core"
```

## Task 3: Add Audio Feedback, Copy/Paste, And Model Testing Services

**Branch:** continue on `dy/ephemeral-modal-core`

**Files:**
- Create: `Sources/LisperCore/AudioFeedbackModel.swift`
- Create: `Sources/LisperCore/ClipboardServices.swift`
- Create: `Sources/LisperCore/ModelTesting.swift`
- Test: `Tests/LisperCoreTests/AudioFeedbackModelTests.swift`
- Test: `Tests/LisperCoreTests/ClipboardServicesTests.swift`
- Test: `Tests/LisperCoreTests/ModelTestingTests.swift`

- [ ] **Step 1: Add failing audio feedback tests**

Create `Tests/LisperCoreTests/AudioFeedbackModelTests.swift`:

```swift
import XCTest
@testable import LisperCore

final class AudioFeedbackModelTests: XCTestCase {
    func testEnergyUsesRootMeanSquareAndSmoothing() {
        var model = AudioFeedbackModel(smoothing: 0.5)
        model.apply(samples: [0, 0.5, -0.5, 1.0])

        XCTAssertEqual(model.currentEnergy, 0.612, accuracy: 0.01)
        XCTAssertEqual(model.smoothedEnergy, 0.306, accuracy: 0.01)
        XCTAssertTrue(model.particleIntensity > 0)
    }

    func testPointerPositionIsStoredForCursorReactiveBubbles() {
        var state = CursorReactiveState()
        state.updatePointer(x: 0.25, y: 0.75)

        XCTAssertEqual(state.pointerX, 0.25)
        XCTAssertEqual(state.pointerY, 0.75)
    }
}
```

- [ ] **Step 2: Implement audio feedback model**

Create `Sources/LisperCore/AudioFeedbackModel.swift`:

```swift
import Foundation

public struct AudioFeedbackModel: Equatable, Sendable {
    public private(set) var currentEnergy: Double = 0
    public private(set) var smoothedEnergy: Double = 0
    public var smoothing: Double

    public init(smoothing: Double = 0.18) {
        self.smoothing = smoothing
    }

    public var particleIntensity: Double {
        min(1, smoothedEnergy * 1.8)
    }

    public mutating func apply(samples: [Float]) {
        guard !samples.isEmpty else {
            currentEnergy = 0
            smoothedEnergy *= 1 - smoothing
            return
        }

        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        currentEnergy = sqrt(meanSquare)
        smoothedEnergy = smoothedEnergy + (currentEnergy - smoothedEnergy) * smoothing
    }
}

public struct CursorReactiveState: Equatable, Sendable {
    public private(set) var pointerX: Double = 0.5
    public private(set) var pointerY: Double = 0.5

    public init() {}

    public mutating func updatePointer(x: Double, y: Double) {
        pointerX = min(1, max(0, x))
        pointerY = min(1, max(0, y))
    }
}
```

- [ ] **Step 3: Add copy/paste service tests and implementation**

Create `Sources/LisperCore/ClipboardServices.swift`:

```swift
import Foundation

public enum CopyPasteError: Error, Equatable {
    case copyFailed
    case pasteUnavailable
}

public protocol ClipboardWriting {
    func copy(_ text: String) throws
}

public protocol ActiveFieldPasting {
    func paste(_ text: String) async throws
}

public struct CopyPasteCoordinator {
    public var clipboard: any ClipboardWriting
    public var activeField: (any ActiveFieldPasting)?

    public init(clipboard: any ClipboardWriting, activeField: (any ActiveFieldPasting)?) {
        self.clipboard = clipboard
        self.activeField = activeField
    }

    public func copy(_ text: String) throws {
        try clipboard.copy(text)
    }

    public func pasteIfEnabled(_ text: String, enabled: Bool) async throws {
        guard enabled else { return }
        guard let activeField else { throw CopyPasteError.pasteUnavailable }
        try await activeField.paste(text)
    }
}
```

Create `Tests/LisperCoreTests/ClipboardServicesTests.swift` with fake clipboard/field implementations that assert copy succeeds, disabled paste is a no-op, and enabled paste without an active field throws `pasteUnavailable`.

- [ ] **Step 4: Add model test result contracts**

Create `Sources/LisperCore/ModelTesting.swift`:

```swift
import Foundation

public enum ModelTestStatus: Equatable, Sendable {
    case idle
    case testing
    case succeeded(String)
    case failed(String)
}

public protocol ModelSlotTesting {
    func test(configuration: ModelSlotConfiguration) async -> ModelTestStatus
}
```

Create `Tests/LisperCoreTests/ModelTestingTests.swift` with a fake tester that returns `.succeeded("OK")` for a remote config with non-empty endpoint and `.failed("Missing endpoint")` for an empty remote endpoint.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter 'AudioFeedbackModelTests|ClipboardServicesTests|ModelTestingTests'
git add Sources/LisperCore/AudioFeedbackModel.swift Sources/LisperCore/ClipboardServices.swift Sources/LisperCore/ModelTesting.swift Tests/LisperCoreTests/AudioFeedbackModelTests.swift Tests/LisperCoreTests/ClipboardServicesTests.swift Tests/LisperCoreTests/ModelTestingTests.swift
git commit -m "feat: add modal support services"
```

## Task 4: Build The Ephemeral Modal And Settings UI

**Branch:** `dy/ephemeral-modal-ui`

**Files:**
- Create: `Sources/lisper-app/EphemeralModalView.swift`
- Create: `Sources/lisper-app/SettingsView.swift`
- Modify: `Sources/lisper-app/AppSupport.swift`
- Modify: `Sources/lisper-app/main.swift`
- Test: `Tests/LisperCoreTests/AppExecutableSmokeTests.swift`

- [ ] **Step 1: Create the branch**

```bash
git switch -c dy/ephemeral-modal-ui dy/ephemeral-modal-core
```

- [ ] **Step 2: Extract modal views from `AppSupport.swift`**

Create `Sources/lisper-app/EphemeralModalView.swift` containing:

- `EphemeralModalView`
- `ReactiveOrbView`
- `TranscriptCopyBubble`
- `CopyFeedbackState`

Required behavior:

- listening state shows only orb plus particles
- processing/result state shows stacked original/enhanced blocks
- whole text bubble is clickable
- copy icon is bottom-right inside the bubble
- `Text copied` row has fixed height
- cursor position updates iridescent highlight state

- [ ] **Step 3: Add settings views**

Create `Sources/lisper-app/SettingsView.swift` containing:

- `LisperSettingsView`
- `HotkeySettingsPane`
- `ModelSettingsPane`
- `AutomationSettingsPane`
- `AppearanceSettingsPane`

Required controls:

- current hotkey display
- endpoint URL and API key secure field for both model slots
- `Test` button for both model slots
- post-processing toggle
- auto-copy toggle
- auto-paste toggle defaulting off
- appearance segmented control

- [ ] **Step 4: Update app scene**

Modify `Sources/lisper-app/main.swift` so the app exposes:

- an ephemeral modal window or window group for daily workflow
- a settings scene for persistent options

Keep the current prototype window available only if needed for diagnostics; the primary user-facing flow should be the modal.

- [ ] **Step 5: Verify compile**

```bash
swift build --product lisper-app
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/lisper-app/EphemeralModalView.swift Sources/lisper-app/SettingsView.swift Sources/lisper-app/AppSupport.swift Sources/lisper-app/main.swift Tests/LisperCoreTests/AppExecutableSmokeTests.swift
git commit -m "feat: add ephemeral modal and settings UI"
```

## Task 5: Wire End-To-End Hotkey, Cleanup, Auto-Copy, And Auto-Paste

**Branch:** `dy/ephemeral-modal-integration`

**Files:**
- Modify: `Sources/LisperCore/AppModel.swift`
- Modify: `Sources/lisper-app/AppSupport.swift`
- Modify: `Sources/lisper-app/EphemeralModalView.swift`
- Modify: `Sources/lisper-app/SettingsView.swift`
- Modify: `README.md`
- Test: `Tests/LisperCoreTests/AppModelTests.swift`
- Test: `Tests/LisperCoreTests/AudioCaptureServiceTests.swift`

- [ ] **Step 1: Create the branch**

```bash
git switch -c dy/ephemeral-modal-integration dy/ephemeral-modal-ui
```

- [ ] **Step 2: Implement hotkey tap/hold policy**

Update `LisperAppCoordinator` so:

- Right Option is the default hotkey.
- short press toggles listening
- hold starts push-to-talk after the configured threshold
- release stops only a push-to-talk session

Keep stale session token checks intact.

- [ ] **Step 3: Feed microphone samples into `AudioFeedbackModel`**

Use `AudioCaptureService.onSamples` to update the model-facing audio feedback state on the main actor. The UI should receive energy/particle state without reading raw audio samples directly.

- [ ] **Step 4: Implement cleanup completion path**

When recording finishes:

- build `TranscriptResult(original: transcriptText, cleanup: .processing)` if post-processing is enabled
- run cleanup service
- update result to `.succeeded(enhanced)` or `.failed(message)`
- preserve original text in all cases

For MVP local cleanup, use a deterministic lightweight cleanup implementation that trims whitespace, capitalizes the first character, and appends terminal punctuation when missing. Remote cleanup can be represented through the model slot test/config path until a concrete provider schema is selected.

- [ ] **Step 5: Implement auto-copy and auto-paste**

When result resolution completes:

- if auto-copy is enabled, copy `TranscriptResult.preferredText`
- trigger copy feedback on `.preferredSource`
- if auto-paste is enabled, paste `TranscriptResult.preferredText`
- if paste fails, show non-destructive diagnostics and leave modal visible

- [ ] **Step 6: Update README**

Document:

- default Right Option hotkey
- tap versus hold behavior
- settings surface
- model overrides and test buttons
- auto-copy and auto-paste defaults
- setup/build/test commands

- [ ] **Step 7: Verify**

```bash
swift test --filter 'AppModelTests|AudioCaptureServiceTests|TranscriptResultTests|AudioFeedbackModelTests|ClipboardServicesTests|ModelTestingTests|AppSettingsTests'
swift build --product lisper-app
```

Expected: tests and build pass.

- [ ] **Step 8: Commit**

```bash
git add Sources README.md Tests
git commit -m "feat: wire ephemeral modal workflow"
```

## Task 6: Final Stack Verification And PRs

**Files:**
- No new files expected unless verification reveals a focused fix.

- [ ] **Step 1: Run full test suite on top branch**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build app on top branch**

```bash
swift build --product lisper-app
```

Expected: build succeeds.

- [ ] **Step 3: Push stacked branches**

```bash
git push -u origin dy/ephemeral-modal-spec
git push -u origin dy/ephemeral-modal-baseline
git push -u origin dy/ephemeral-modal-core
git push -u origin dy/ephemeral-modal-ui
git push -u origin dy/ephemeral-modal-integration
```

- [ ] **Step 4: Open stacked PRs**

```bash
gh pr create --base main --head dy/ephemeral-modal-spec --title "docs: specify ephemeral modal product flow" --body-file /tmp/lisper-pr-spec.md
gh pr create --base dy/ephemeral-modal-spec --head dy/ephemeral-modal-baseline --title "feat: add SwiftPM Lisper prototype baseline" --body-file /tmp/lisper-pr-baseline.md
gh pr create --base dy/ephemeral-modal-baseline --head dy/ephemeral-modal-core --title "feat: add ephemeral modal core services" --body-file /tmp/lisper-pr-core.md
gh pr create --base dy/ephemeral-modal-core --head dy/ephemeral-modal-ui --title "feat: add ephemeral modal and settings UI" --body-file /tmp/lisper-pr-ui.md
gh pr create --base dy/ephemeral-modal-ui --head dy/ephemeral-modal-integration --title "feat: wire ephemeral modal workflow" --body-file /tmp/lisper-pr-integration.md
```

Each PR body should include:

- stack position
- base branch
- summary
- verification run
- known follow-ups

## Plan Self-Review

- Spec coverage: covered modal, orb feedback, copy bubbles, copy feedback, cursor-reactive iridescence, settings, model overrides, auto-copy, auto-paste, and failure behavior.
- Placeholder scan: no `TBD` or `TODO` placeholders.
- Type consistency: core types introduced in Tasks 2 and 3 are consumed by UI/integration tasks.
- Stack consistency: each branch bases on the previous branch and can be reviewed independently.
