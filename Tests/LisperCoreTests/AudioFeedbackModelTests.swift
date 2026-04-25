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

    func testEmptySamplesDecaySmoothedEnergy() {
        var model = AudioFeedbackModel(smoothing: 0.5)
        model.apply(samples: [1.0])

        model.apply(samples: [])

        XCTAssertEqual(model.currentEnergy, 0)
        XCTAssertEqual(model.smoothedEnergy, 0.25, accuracy: 0.01)
    }

    func testPointerPositionIsClampedForCursorReactiveBubbles() {
        var state = CursorReactiveState()

        state.updatePointer(x: -0.25, y: 1.75)

        XCTAssertEqual(state.pointerX, 0)
        XCTAssertEqual(state.pointerY, 1)
    }
}
