#if DEBUG
import Foundation

final class NotesImportDebugHarness {
    private static var hasRun = false
    
    static let sampleCleanValidImport = """
    December 15, 2025, Push
    13:05-14:12
    1. Bench Press, 3x8, 185lbs, 1:30m rest
    2. Incline Dumbbell Press, 3x10, 70lbs
    3. Treadmill Run, 5km, 29min, 5:48av
    """
    
    static let sampleMissingDateAndUnknownLines = """
    Tuesday upper body maybe
    Started watch workout
    1. Bench Press, 3x8
    Weird random line that parser should keep
    Bike, 20min, 6km
    """
    
    static let sampleDuplicateExerciseNames = """
    Nov 15, 2022, Legs
    Squat, 3x5, 225lbs
    squat, 2x8, 185lbs
    SQUAT, 1x12, 135lbs
    """

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
