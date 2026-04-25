import AppKit
import SwiftUI
import LisperCore

public struct EphemeralModalView: View {
    @ObservedObject private var model: LisperAppModel

    public init(model: LisperAppModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            modalBackground

            if isListening {
                ReactiveOrbView(audioFeedback: model.audioFeedback)
                    .frame(width: 180, height: 180)
                    .transition(.scale.combined(with: .opacity))
            } else {
                resultStack
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(22)
        .frame(minWidth: 420, idealWidth: 540, maxWidth: 680, minHeight: isListening ? 260 : 420)
        .background(EphemeralWindowConfigurator())
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isListening)
    }

    private var isListening: Bool {
        model.phase == .starting || model.phase == .recording
    }

    private var modalBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .cyan.opacity(0.42),
                                .pink.opacity(0.34),
                                .purple.opacity(0.32),
                                .mint.opacity(0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .purple.opacity(0.18), radius: 30, y: 18)
    }

    private var resultStack: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lisper")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TranscriptCopyBubble(
                title: "Original",
                text: originalText,
                source: .original,
                isProcessing: false,
                onCopy: copyToPasteboard
            )

            TranscriptCopyBubble(
                title: "Enhanced",
                text: enhancedText,
                source: .enhanced,
                isProcessing: enhancedIsProcessing,
                message: enhancedMessage,
                onCopy: copyToPasteboard
            )
        }
    }

    private func copyToPasteboard(_ text: String, _ source: TranscriptTextSource) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private var originalText: String {
        let text = model.transcriptResult?.original ?? model.transcriptText
        return text.isEmpty ? "Your original transcript will appear here." : text
    }

    private var enhancedText: String {
        guard let result = model.transcriptResult else {
            return "Enhanced text will appear after processing."
        }

        switch result.cleanup {
        case .succeeded(let text):
            return text
        case .disabled:
            return result.original.isEmpty ? "Cleanup is disabled." : result.original
        case .processing:
            return "Enhancing transcript..."
        case .failed:
            return result.original
        }
    }

    private var enhancedIsProcessing: Bool {
        model.transcriptResult?.cleanup == .processing
    }

    private var enhancedMessage: String? {
        guard let cleanup = model.transcriptResult?.cleanup else {
            return nil
        }

        switch cleanup {
        case .disabled:
            return "Post-processing disabled"
        case .failed(let message):
            return message
        case .processing:
            return "Processing"
        case .succeeded:
            return nil
        }
    }
}

public struct ReactiveOrbView: View {
    let audioFeedback: AudioFeedbackModel

    private var energy: Double {
        max(0.04, min(1, audioFeedback.smoothedEnergy))
    }

    private var particleIntensity: Double {
        max(0.08, min(1, audioFeedback.particleIntensity))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(0..<24, id: \.self) { index in
                    particle(index: index, time: time)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.88),
                                .cyan.opacity(0.72),
                                .pink.opacity(0.56),
                                .purple.opacity(0.44),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 92
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.48), lineWidth: 1)
                    }
                    .scaleEffect(0.82 + energy * 0.22 + sin(time * 2.8) * 0.025)
                    .shadow(color: .cyan.opacity(0.32 + particleIntensity * 0.22), radius: 28)
                    .shadow(color: .pink.opacity(0.22), radius: 40)
            }
            .accessibilityLabel("Listening")
        }
    }

    private func particle(index: Int, time: TimeInterval) -> some View {
        let angle = Double(index) / 24 * .pi * 2 + time * (0.16 + Double(index % 5) * 0.018)
        let radius = 52 + Double(index % 7) * 7 + particleIntensity * 32
        let size = 2.2 + Double(index % 4) * 0.7 + particleIntensity * 2.4
        let x = cos(angle) * radius
        let y = sin(angle * 1.12) * radius * 0.72

        return Circle()
            .fill(
                LinearGradient(
                    colors: [.cyan.opacity(0.65), .pink.opacity(0.58), .mint.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .opacity(0.26 + particleIntensity * 0.58)
            .blur(radius: 0.4)
    }
}

public struct TranscriptCopyBubble: View {
    let title: String
    let text: String
    let source: TranscriptTextSource
    var isProcessing: Bool = false
    var message: String?
    var onCopy: (String, TranscriptTextSource) -> Bool = { _, _ in false }

    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    @State private var feedback = CopyFeedbackState()
    @State private var feedbackDismissTask: Task<Void, Never>?

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }
                if let message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button {
                if onCopy(text, source) {
                    showCopyFeedback(message: "Text copied")
                } else {
                    showCopyFeedback(message: "Copy failed")
                }
            } label: {
                bubbleContent
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty || isProcessing)

            HStack(spacing: 8) {
                Text(feedback.isVisible ? feedback.message : " ")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if feedback.isVisible {
                    CopyFeedbackShimmer(id: feedback.shimmerID)
                }
            }
            .frame(height: 16, alignment: .leading)
            .opacity(feedback.isVisible ? 1 : 0)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: feedback.isVisible)
        }
    }

    private var bubbleContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        iridescentHighlight
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    }

                Text(text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 14)
                    .padding(.leading, 14)
                    .padding(.trailing, 44)
                    .padding(.bottom, 34)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(11)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let width = max(1, geometry.size.width)
                    let height = max(1, geometry.size.height)
                    pointer = CGPoint(
                        x: min(1, max(0, location.x / width)),
                        y: min(1, max(0, location.y / height))
                    )
                case .ended:
                    pointer = CGPoint(x: 0.5, y: 0.5)
                }
            }
        }
        .frame(minHeight: 116)
    }

    private func showCopyFeedback(message: String) {
        feedback.show(message: message)
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                feedback.hide()
                feedbackDismissTask = nil
            }
        }
    }

    private var iridescentHighlight: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .cyan.opacity(0.12),
                    .pink.opacity(0.10),
                    .purple.opacity(0.08),
                    .mint.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    .white.opacity(0.34),
                    .cyan.opacity(0.22),
                    .pink.opacity(0.14),
                    .clear
                ],
                center: UnitPoint(x: pointer.x, y: pointer.y),
                startRadius: 0,
                endRadius: 170
            )
            .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

public struct CopyFeedbackState: Equatable {
    public var isVisible = false
    public var message = "Text copied"
    public var shimmerID = UUID()

    public init() {}

    public mutating func show(message: String) {
        isVisible = true
        self.message = message
        shimmerID = UUID()
    }

    public mutating func hide() {
        isVisible = false
    }
}

private struct CopyFeedbackShimmer: View {
    let id: UUID

    @State private var offset: CGFloat = -52

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, .cyan.opacity(0.7), .pink.opacity(0.65), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 72, height: 2)
            .mask(
                Capsule()
                    .offset(x: offset)
            )
            .onAppear {
                offset = -52
                withAnimation(.easeOut(duration: 0.9)) {
                    offset = 52
                }
            }
            .id(id)
    }
}

private struct EphemeralWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        if let screen = window.screen ?? NSScreen.main {
            let frame = window.frame
            let visible = screen.visibleFrame
            let origin = CGPoint(
                x: visible.midX - frame.width / 2,
                y: visible.minY + 76
            )
            window.setFrameOrigin(origin)
        }
    }
}
