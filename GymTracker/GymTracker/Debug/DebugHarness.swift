#if DEBUG
import Foundation

final class DebugHarness {
    private static var hasRun = false

    private static var isEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
        let argsEnabled = processInfo.arguments.contains("--run-debug-harness")
        let envEnabled = processInfo.environment["GYMTRACKER_RUN_DEBUG_HARNESS"] == "1"
        return argsEnabled || envEnabled
    }

    static func runAll() {
        guard isEnabled else { return }
        guard !hasRun else { return }
        hasRun = true
        print("=== DEBUG start ===")
        print("=== NotesImportDebugHarness start ===")
        NotesImportParserDebug.runSamples()
        NotesImportResolverDebug.runSamples()
        NotesImportWriterDebug.runSamples()
        print("=== NotesImportDebugHarness done ===")
        ExerciseMergeDebug.runSamples()
        ExerciseBackupDebug.runSamples()
        HealthKitSmartPullDebug.runSamples()
        SessionExerciseTransferDebug.runSamples()
        AuthBootstrapDebug.runSamples()
        print("=== DEBUG done ===")
    }
}
#endif
