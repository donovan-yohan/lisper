import Foundation
import Carbon

public enum LisperDefaults {
    public static let hotkeyDisplay = "Control + Option + Space"
    public static let hotkeyKeyCode: UInt32 = 49
    public static let hotkeyCarbonModifiers: UInt32 = UInt32(controlKey | optionKey)
    public static let whisperStepMilliseconds = 1000
    public static let whisperLengthMilliseconds = 5000
    public static let whisperKeepMilliseconds = 200
    public static let whisperCaptureID = 0
    public static let diagnosticsDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lisper", isDirectory: true)
    }()
    public static let whisperTranscriptLogURL: URL = diagnosticsDirectoryURL
        .appendingPathComponent("whisper-stream.txt", isDirectory: false)
}

public protocol WhisperProcessLaunching: AnyObject {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var currentDirectoryURL: URL? { get set }
    var standardOutput: Pipe? { get set }
    var standardError: Pipe? { get set }
    var terminationHandler: ((Int32) -> Void)? { get set }
    var isRunning: Bool { get }

    func run() throws
    func terminate()
}

private final class FoundationProcessLauncher: WhisperProcessLaunching, @unchecked Sendable {
    private let process = Process()

    var executableURL: URL? {
        get { process.executableURL }
        set { process.executableURL = newValue }
    }

    var arguments: [String]? {
        get { process.arguments }
        set { process.arguments = newValue }
    }

    var currentDirectoryURL: URL? {
        get { process.currentDirectoryURL }
        set { process.currentDirectoryURL = newValue }
    }

    var standardOutput: Pipe? {
        get { process.standardOutput as? Pipe }
        set { process.standardOutput = newValue }
    }

    var standardError: Pipe? {
        get { process.standardError as? Pipe }
        set { process.standardError = newValue }
    }

    var terminationHandler: ((Int32) -> Void)?

    var isRunning: Bool {
        process.isRunning
    }

    init() {
        process.terminationHandler = { [weak self] process in
            self?.terminationHandler?(process.terminationStatus)
        }
    }

    func run() throws {
        try process.run()
    }

    func terminate() {
        process.terminate()
    }
}

public final class WhisperProcessSession: WhisperStreamingSession, @unchecked Sendable {
    public let updates: AsyncStream<WhisperStreamEvent>

    private let continuation: AsyncStream<WhisperStreamEvent>.Continuation
    private let dependency: WhisperDependency
    private let processFactory: () -> any WhisperProcessLaunching
    private let lock = NSLock()

    private var process: (any WhisperProcessLaunching)?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var started = false
    private var finished = false
    private var stopRequested = false

    public init(
        dependency: WhisperDependency,
        processFactory: @escaping () -> any WhisperProcessLaunching
    ) {
        self.dependency = dependency
        self.processFactory = processFactory

        var continuation: AsyncStream<WhisperStreamEvent>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public convenience init(dependency: WhisperDependency) {
        self.init(dependency: dependency, processFactory: { FoundationProcessLauncher() })
    }

    public func start() throws {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        let process = processFactory()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        try? FileManager.default.createDirectory(
            at: LisperDefaults.diagnosticsDirectoryURL,
            withIntermediateDirectories: true
        )
        try? Data().write(to: LisperDefaults.whisperTranscriptLogURL, options: .atomic)

        let captureID = ProcessInfo.processInfo.environment["LISPER_CAPTURE_ID"]
            .flatMap(Int.init) ?? LisperDefaults.whisperCaptureID
        let arguments = [
            "-m", dependency.model.path,
            "-c", String(captureID),
            "--step", String(LisperDefaults.whisperStepMilliseconds),
            "--length", String(LisperDefaults.whisperLengthMilliseconds),
            "--keep", String(LisperDefaults.whisperKeepMilliseconds),
            "-kc",
            "-l", "en",
            "-f", LisperDefaults.whisperTranscriptLogURL.path,
            "-sa"
        ]

        process.executableURL = dependency.streamBinary
        process.arguments = arguments
        process.currentDirectoryURL = LisperDefaults.diagnosticsDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] status in
            self?.handleTermination(status: status)
        }

        storeProcess(process)

        stdoutTask = makeStreamTask(pipe: stdoutPipe, streamStderr: false)
        stderrTask = makeStreamTask(pipe: stderrPipe, streamStderr: true)

        do {
            try process.run()
        } catch {
            finish(with: .failed(error.localizedDescription))
            throw error
        }

        emit(.info("Launching whisper-stream: \(dependency.streamBinary.path) \(arguments.joined(separator: " "))"))
        emit(.info("whisper-stream working directory: \(LisperDefaults.diagnosticsDirectoryURL.path)"))
        emit(.started)
    }

    public func stop() {
        lock.lock()
        stopRequested = true
        let currentProcess = process
        let alreadyFinished = finished
        lock.unlock()

        guard !alreadyFinished else {
            return
        }

        currentProcess?.terminate()
    }

    private func makeStreamTask(pipe: Pipe, streamStderr: Bool) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                if streamStderr {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        self?.emit(.stderr(line.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                } else {
                    var parser = WhisperStreamOutputParser()
                    var chunkBuffer = Data()

                    for try await byte in pipe.fileHandleForReading.bytes {
                        if byte == 0x0A || byte == 0x0D {
                            if let event = self?.emitChunk(from: &chunkBuffer, parser: &parser) {
                                self?.emit(event)
                            }
                        } else {
                            chunkBuffer.append(contentsOf: [byte])
                        }
                    }

                    if let event = self?.emitChunk(from: &chunkBuffer, parser: &parser) {
                        self?.emit(event)
                    }
                }
            } catch {
                self?.emit(.stderr(error.localizedDescription))
            }
        }
    }

    private func emitChunk(
        from buffer: inout Data,
        parser: inout WhisperStreamOutputParser
    ) -> WhisperStreamEvent? {
        guard !buffer.isEmpty else {
            return nil
        }

        let chunk = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return parser.consume(chunk)
    }

    private func handleTermination(status: Int32) {
        lock.lock()
        let shouldTreatAsStop = stopRequested || status == 0
        lock.unlock()

        if shouldTreatAsStop {
            finish(with: .stopped)
        } else {
            finish(with: .failed("whisper-stream exited with status \(status)"))
        }
    }

    private func emit(_ event: WhisperStreamEvent) {
        lock.lock()
        let shouldEmit = !finished
        lock.unlock()

        guard shouldEmit else {
            return
        }

        continuation.yield(event)
    }

    private func storeProcess(_ process: any WhisperProcessLaunching) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    private func finish(with event: WhisperStreamEvent) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        process = nil
        let stdoutTask = stdoutTask
        let stderrTask = stderrTask
        self.stdoutTask = nil
        self.stderrTask = nil
        lock.unlock()

        continuation.yield(event)
        continuation.finish()
        stdoutTask?.cancel()
        stderrTask?.cancel()
    }
}

public final class WhisperProcessSessionFactory: WhisperStreamingSessionFactory {
    private let processFactory: () -> any WhisperProcessLaunching

    public private(set) var lastSession: WhisperProcessSession?

    public init(
        processFactory: @escaping () -> any WhisperProcessLaunching
    ) {
        self.processFactory = processFactory
    }

    public convenience init() {
        self.init(processFactory: { FoundationProcessLauncher() })
    }

    public func makeSession(using dependency: WhisperDependency) -> any WhisperStreamingSession {
        let session = WhisperProcessSession(
            dependency: dependency,
            processFactory: processFactory
        )
        lastSession = session
        return session
    }
}
