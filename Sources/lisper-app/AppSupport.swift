import AppKit
import Combine
import Carbon
import Foundation
import SwiftUI
import LisperCore

@MainActor
public final class LisperAppCoordinator: ObservableObject {
    public let model: LisperAppModel

    private let dependencyResolver: any WhisperDependencyResolving
    private let diagnosticsLogger = LisperDiagnosticsLogger()
    private let hotkeyRouter = LisperHotkeyRouter()
    private lazy var hotkeyMonitor = LisperHotkeyMonitor(
        onKeyDown: { [hotkeyRouter] in
            hotkeyRouter.handleKeyDown()
        },
        onKeyUp: { [hotkeyRouter] in
            hotkeyRouter.handleKeyUp()
        }
    )

    private var transcriptionTask: Task<Void, Never>?
    private var holdStartTask: Task<Void, Never>?
    private var hotkeyIsPressed = false
    private var recordingInteraction: RecordingInteraction = .idle
    private var activeSessionToken: AppSessionToken?
    private var supportsMomentaryHotkey = false
    private var stopRequestedDuringStart = false
    private var cancellables: Set<AnyCancellable> = []
    private var audioCaptureService: AudioCaptureService?
    private var transcriber: WhisperLibraryTranscriber?

    public init(
        dependencyResolver: any WhisperDependencyResolving = WhisperDependencyResolver(),
        sessionFactory: WhisperProcessSessionFactory = WhisperProcessSessionFactory()
    ) {
        _ = sessionFactory
        self.dependencyResolver = dependencyResolver
        self.model = LisperAppModel(
            dependencyResolver: dependencyResolver,
            sessionFactory: sessionFactory
        )
        hotkeyRouter.coordinator = self
        bindLogging()

        supportsMomentaryHotkey = hotkeyMonitor.start()
        diagnosticsLogger.log("App launched. Diagnostics log: \(LisperDiagnosticsLogger.logURL.path)")
        if !supportsMomentaryHotkey {
            model.reportDiagnostic("Global hotkey release monitoring unavailable; falling back to tap-to-toggle only.")
        }
    }

    private func bindLogging() {
        model.$statusText
            .removeDuplicates()
            .sink { [diagnosticsLogger] status in
                diagnosticsLogger.log("status: \(status)")
            }
            .store(in: &cancellables)

        model.$diagnosticsText
            .removeDuplicates()
            .sink { [diagnosticsLogger] diagnostics in
                guard !diagnostics.isEmpty else {
                    return
                }
                diagnosticsLogger.log("diagnostics: \(diagnostics)")
            }
            .store(in: &cancellables)

        model.$transcriptText
            .removeDuplicates()
            .sink { [diagnosticsLogger] transcript in
                guard !transcript.isEmpty else {
                    return
                }
                diagnosticsLogger.log("transcript: \(transcript)")
            }
            .store(in: &cancellables)
    }

    fileprivate func handleHotkeyDown() async {
        guard isLisperHotkeyActive else {
            return
        }

        if !supportsMomentaryHotkey {
            if recordingInteraction == .startingLatched || recordingInteraction == .startingMomentary {
                stopRequestedDuringStart = true
            } else if model.phase == .idle {
                beginLatchedRecording()
            } else {
                stopRecording()
            }
            return
        }

        hotkeyIsPressed = true

        guard recordingInteraction == .idle else {
            return
        }

        holdStartTask?.cancel()
        holdStartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.beginMomentaryRecordingIfStillPressed()
        }
    }

    fileprivate func handleHotkeyUp() async {
        guard isLisperHotkeyActive else {
            return
        }

        guard supportsMomentaryHotkey else {
            return
        }

        hotkeyIsPressed = false
        holdStartTask?.cancel()
        holdStartTask = nil

        switch recordingInteraction {
        case .idle:
            if model.phase == .idle {
                beginLatchedRecording()
            }
        case .startingLatched:
            stopRequestedDuringStart = true
        case .startingMomentary:
            stopRequestedDuringStart = true
        case .latched:
            stopRecording()
        case .momentary:
            stopRecording()
        }
    }

    private func beginLatchedRecording() {
        recordingInteraction = .startingLatched
        stopRequestedDuringStart = false

        Task { [weak self] in
            guard let self else {
                return
            }

            let token = self.model.beginInProcessRecording()
            self.activeSessionToken = token

            do {
                try await self.startInProcessRecording(using: token)
                guard self.recordingInteraction == .startingLatched else {
                    return
                }

                if self.stopRequestedDuringStart {
                    self.stopRecording()
                    return
                }

                self.recordingInteraction = .latched
            } catch {
                self.model.failRecording(for: token, message: error.localizedDescription)
                self.activeSessionToken = nil
                self.stopRequestedDuringStart = false
                self.recordingInteraction = .idle
            }
        }
    }

    private func beginMomentaryRecordingIfStillPressed() async {
        guard hotkeyIsPressed, recordingInteraction == .idle, model.phase == .idle else {
            return
        }

        recordingInteraction = .startingMomentary
        stopRequestedDuringStart = false

        do {
            let token = model.beginInProcessRecording()
            activeSessionToken = token
            try await startInProcessRecording(using: token)
            guard recordingInteraction == .startingMomentary else {
                return
            }

            if stopRequestedDuringStart || !hotkeyIsPressed {
                stopRecording()
            } else {
                activeSessionToken = token
                recordingInteraction = .momentary
            }
        } catch {
            if let activeSessionToken {
                model.failRecording(for: activeSessionToken, message: error.localizedDescription)
            }
            activeSessionToken = nil
            stopRequestedDuringStart = false
            recordingInteraction = .idle
        }
    }

    private func stopRecording() {
        holdStartTask?.cancel()
        holdStartTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        audioCaptureService?.stop()
        audioCaptureService = nil
        transcriber = nil
        if let activeSessionToken {
            model.finishRecording(for: activeSessionToken)
        }
        activeSessionToken = nil
        recordingInteraction = .idle
        stopRequestedDuringStart = false
    }

    private func startInProcessRecording(using sessionToken: AppSessionToken) async throws {
        let dependency = try dependencyResolver.resolve()
        let configuration = WhisperLibraryTranscriber.Configuration(modelURL: dependency.model)
        let transcriber = try WhisperLibraryTranscriber(configuration: configuration)
        let audioCaptureService = AudioCaptureService(
            maxSamples: configuration.sampleRate * Int(configuration.windowDurationSeconds)
        )

        self.transcriber = transcriber
        self.audioCaptureService = audioCaptureService

        diagnosticsLogger.log("Using in-process libwhisper model: \(dependency.model.path)")
        diagnosticsLogger.log("libwhisper version: \(WhisperLibraryTranscriber.libraryVersion)")

        try await audioCaptureService.start()
        model.markRecordingActive(for: sessionToken)

        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self, transcriber, audioCaptureService] in
            while !Task.isCancelled {
                let samples = audioCaptureService.snapshot()
                if !samples.isEmpty {
                    await MainActor.run {
                        self?.model.applyAudioSamples(samples)
                    }
                    do {
                        let transcript = try await Task.detached(priority: .userInitiated) {
                            try transcriber.transcribe(samples: samples)
                        }.value
                        if !transcript.isEmpty {
                            self?.model.applyLiveTranscript(transcript, from: sessionToken)
                        }
                    } catch {
                        self?.model.reportDiagnostic(error.localizedDescription)
                    }
                }

                try? await Task.sleep(nanoseconds: UInt64(configuration.updateIntervalSeconds * 1_000_000_000))
            }
        }
    }

    private var isLisperHotkeyActive: Bool {
        true
    }

    private enum RecordingInteraction {
        case idle
        case startingLatched
        case startingMomentary
        case latched
        case momentary
    }
}

private final class LisperDiagnosticsLogger {
    static let logURL: URL = {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lisper", isDirectory: true)
        return logsDirectory.appendingPathComponent("diagnostics.log", isDirectory: false)
    }()

    private let lock = NSLock()
    private let iso8601Formatter = ISO8601DateFormatter()

    init() {
        let logsDirectory = Self.logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.logURL.path) {
            FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        }
    }

    func log(_ message: String) {
        let timestamp = iso8601Formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        lock.lock()
        defer { lock.unlock() }

        guard let data = line.data(using: .utf8) else {
            return
        }

        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}

private final class LisperHotkeyRouter {
    weak var coordinator: LisperAppCoordinator?

    func handleKeyDown() {
        guard let coordinator else {
            return
        }

        Task {
            await coordinator.handleHotkeyDown()
        }
    }

    func handleKeyUp() {
        guard let coordinator else {
            return
        }

        Task {
            await coordinator.handleHotkeyUp()
        }
    }
}

private final class LisperHotkeyMonitor {
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    init(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    @discardableResult
    func start() -> Bool {
        stop()

        registerCarbonHotKey()
        return installReleaseEventTap()
    }

    func stop() {
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func registerCarbonHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C495350), id: 1)
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        ]

        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData,
                  let monitor = Unmanaged<LisperHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue() as LisperHotkeyMonitor? else {
                return noErr
            }

            monitor.onKeyDown()
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )

        guard status == noErr else {
            return
        }

        let registrationStatus = RegisterEventHotKey(
            LisperDefaults.hotkeyKeyCode,
            LisperDefaults.hotkeyCarbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registrationStatus != noErr {
            stop()
        }
    }

    private func installReleaseEventTap() -> Bool {
        let eventMask = 1 << CGEventType.keyUp.rawValue
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo,
                  let monitor = Unmanaged<LisperHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue() as LisperHotkeyMonitor? else {
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            case .keyUp:
                monitor.handleKeyUpEvent(event)
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func handleKeyUpEvent(_ event: CGEvent) {
        guard isLisperHotkeyRelease(event) else {
            return
        }

        onKeyUp()
    }

    private func isLisperHotkeyRelease(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(LisperDefaults.hotkeyKeyCode) else {
            return false
        }

        let flags = event.flags
        return flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
    }
}
