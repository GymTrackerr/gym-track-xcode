#if DEBUG
import Foundation

final class NotesImportDebugHarness {
    private static var hasRun = false

    static func runAll() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NotesImportDebugHarness start ===")
        NotesImportParserDebug.runSamples()
        NotesImportResolverDebug.runSamples()
        NotesImportWriterDebug.runSamples()
        print("=== NotesImportDebugHarness done ===")
    }
}
#endif
