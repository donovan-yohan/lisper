public enum TranscriptionMode: Equatable {
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
