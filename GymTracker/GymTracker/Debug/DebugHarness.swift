#if DEBUG
import Foundation

final class DebugHarness {
    private static var hasRun = false

    static func runAll() {
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
        SessionExerciseTransferDebug.runSamples()
        Phase9HardeningDebug.runSamples()
        print("=== DEBUG done ===")
    }
}
#endif
