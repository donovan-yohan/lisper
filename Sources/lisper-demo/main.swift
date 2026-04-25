import Foundation
import Darwin
import LisperCore

@main
struct LisperDemoApp {
    static func main() async throws {
        do {
            let configuration = try DemoArgumentParser().parse(Array(CommandLine.arguments.dropFirst()))
            let runner = DemoRunner()
            let (partials, final) = demoScript(for: configuration.targetKind, behavior: configuration.focusedTargetBehavior)

            let transcript = try await runner.run(
                mode: configuration.mode,
                targetKind: configuration.targetKind,
                focusedTargetBehavior: configuration.focusedTargetBehavior,
                partials: partials,
                final: final
            )

            print(transcript)
        } catch {
            FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!)
            exit(2)
        }
    }

    private static func demoScript(for targetKind: DemoTargetKind, behavior: DemoFocusedTargetBehavior) -> ([String], String) {
        switch targetKind {
        case .modal:
            return (["Lis", "Lisper"], "Lisper demo")
        case .focusedTextField:
            switch behavior {
            case .rewriteSuccess:
                return (["thi", "this is"], "this is lisper")
            case .fallback:
                return (["thi", "this is"], "this is lisper")
            }
        }
    }
}
