import Foundation

public struct AudioFeedbackModel: Equatable, Sendable {
    public private(set) var currentEnergy: Double = 0
    public private(set) var smoothedEnergy: Double = 0
    public var smoothing: Double

    public init(smoothing: Double = 0.18) {
        self.smoothing = min(1, max(0, smoothing))
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
        smoothedEnergy += (currentEnergy - smoothedEnergy) * smoothing
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
