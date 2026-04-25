public final class SessionController {
    private let mode: TranscriptionMode
    private let outputTarget: OutputTarget
    private let engine: ASREngine
    private let refinement: RefinementProcessor

    public init(
        mode: TranscriptionMode,
        outputTarget: OutputTarget,
        engine: ASREngine,
        refinement: RefinementProcessor
    ) {
        self.mode = mode
        self.outputTarget = outputTarget
        self.engine = engine
        self.refinement = refinement
    }

    public func runSession() async throws {
        for try await event in engine.transcriptEvents() {
            switch (mode, event) {
            case (.live, .partial):
                try await outputTarget.handle(event)
            case (.live, .final(let transcript)):
                let refined = try await refinement.refine(transcript)
                try await outputTarget.handle(.final(refined))
            case (.finalOnly, .partial):
                continue
            case (.finalOnly, .final(let transcript)):
                let refined = try await refinement.refine(transcript)
                try await outputTarget.handle(.final(refined))
            }
        }
    }
}
