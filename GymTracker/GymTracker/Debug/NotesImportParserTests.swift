#if DEBUG
import Foundation

final class NotesImportParserDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NotesImportParserDebug start ===")

        let results = [
            test1(),
            test2(),
            test3(),
            test4()
        ]

        let passCount = results.filter { $0 }.count
        let total = results.count
        print("=== NotesImportParserDebug done: \(passCount)/\(total) passed ===")
    }

    @discardableResult
    private static func test1() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 15, 2025, Legs
        13:05-14:12
        1. Back Squat, 2x10, 205lbs, 1x10, 225lbs, 1:30m rest
        2. Barbell Lunge, 1x8, 35kg per side, 20kg bar
        3. Treadmill Run, 5km, 29min, 9:36av
        """

        let batch = parser.parseBatch(from: input, defaultWeightUnit: .lb)
        guard let draft = batch.drafts.first else {
            return fail("test1", "No draft parsed")
        }

        var ok = true
        ok = ok && check("test1", batch.drafts.count == 1, "Expected 1 draft")
        ok = ok && check("test1", draft.parsedDate != nil, "Expected parsed date")
        ok = ok && check("test1", draft.startTime != nil && draft.endTime != nil, "Expected parsed time range")
        ok = ok && check("test1", draft.routineNameRaw == "Legs", "Expected routine name 'Legs', got \(draft.routineNameRaw ?? "nil")")
        ok = ok && check("test1", draft.items.count == 3, "Expected 3 parsed items, got \(draft.items.count)")
        ok = ok && check("test1", !draft.importHash.isEmpty, "Expected non-empty importHash")

        if case .strength(let strength)? = draft.items.first {
            ok = ok && check("test1", strength.sets.count == 3, "Expected 3 strength sets from 2x10 + 1x10")
            ok = ok && check("test1", strength.sets.first?.restSeconds == 90, "Expected restSeconds=90")
        } else {
            ok = false
            print("[test1] Expected first item to be strength")
        }

        if draft.items.count > 1, case .strength(let perSideStrength) = draft.items[1] {
            let set = perSideStrength.sets.first
            ok = ok && check("test1", set?.isPerSide == true, "Expected isPerSide=true")
            ok = ok && check("test1", set?.baseWeight == 20, "Expected baseWeight=20")
            ok = ok && check("test1", set?.perSideWeight == 35, "Expected perSideWeight=35")
            ok = ok && check("test1", set?.weight == 90, "Expected total weight=90")
        } else {
            ok = false
            print("[test1] Expected second item to be strength per-side")
        }

        if draft.items.count > 2, case .cardio(let cardio) = draft.items[2] {
            let set = cardio.sets.first
            ok = ok && check("test1", set?.distance == 5, "Expected cardio distance=5")
            ok = ok && check("test1", set?.distanceUnit == .km, "Expected distance unit km")
            ok = ok && check("test1", set?.durationSeconds == 1740, "Expected durationSeconds=1740")
            ok = ok && check("test1", set?.paceSeconds == 576, "Expected paceSeconds=576")
        } else {
            ok = false
            print("[test1] Expected third item to be cardio")
        }

        print("[test1] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test2() -> Bool {
        let parser = NotesImportParser()
        let input = """
        Nov 15, 2022, Pull
        08:10-09:00
        Deadlift, 3 sets of 5, 180kg

        December 16, 2025, Cardio
        22:30-00:10
        Run, 20min, 2km
        """

        let batch = parser.parseBatch(from: input, defaultWeightUnit: .kg)

        var ok = true
        ok = ok && check("test2", batch.drafts.count == 2, "Expected 2 drafts")

        if batch.drafts.count == 2 {
            let first = batch.drafts[0]
            let second = batch.drafts[1]

            ok = ok && check("test2", first.routineNameRaw == "Pull", "Expected first routine Pull")
            ok = ok && check("test2", second.routineNameRaw == "Cardio", "Expected second routine Cardio")
            ok = ok && check("test2", first.importHash != second.importHash, "Expected different hashes for different drafts")

            if let start = second.startTime, let end = second.endTime {
                ok = ok && check("test2", end > start, "Expected cross-midnight end time > start time")
            } else {
                ok = false
                print("[test2] Missing start/end for cross-midnight sample")
            }
        }

        print("[test2] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test3() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 20, 2025, Misc
        Started watch workout
        Bench Press, 3x10
        Weird unparseable line
        Bike, 1km, 5:15min
        """

        let batch = parser.parseBatch(from: input, defaultWeightUnit: .lb)
        guard let draft = batch.drafts.first else {
            return fail("test3", "No draft parsed")
        }

        var ok = true
        ok = ok && check("test3", draft.items.count == 2, "Expected 2 parsed items")
        ok = ok && check("test3", draft.unknownLines.contains("Started watch workout"), "Expected unknown line to retain started-watch text")
        ok = ok && check("test3", draft.unknownLines.contains("Weird unparseable line"), "Expected unknown line to be preserved")

        if case .strength(let strength)? = draft.items.first {
            ok = ok && check("test3", strength.sets.count == 3, "Expected 3 sets from '3x10'")
            ok = ok && check("test3", strength.sets.allSatisfy { $0.weight == nil }, "Expected nil weight when omitted")
            ok = ok && check("test3", strength.sets.allSatisfy { $0.weightUnit == .lb }, "Expected default weight unit .lb")
        } else {
            ok = false
            print("[test3] Expected first item to be strength")
        }

        print("[test3] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test4() -> Bool {
        let parser = NotesImportParser()
        let inputA = """
        December 31, 2025, Push
        11:00-12:00
        Incline Press, 2x8, 80kg
        """

        let inputB = """
        december 31 2025 push
        11:00-12:00
        Incline Press, 2x8, 80kg
        """

        let draftA = parser.parseSingleSession(from: inputA, defaultWeightUnit: .kg)
        let draftB = parser.parseSingleSession(from: inputB, defaultWeightUnit: .kg)

        var ok = true
        ok = ok && check("test4", draftA.importHash == draftB.importHash, "Expected hash to match after canonical normalization")
        ok = ok && check("test4", draftA.parsedDate != nil, "Expected valid date parse for inputA")
        ok = ok && check("test4", draftB.parsedDate == nil, "Expected invalid date parse for inputB missing comma")
        ok = ok && check("test4", !draftB.warnings.isEmpty, "Expected warning for unparsed date in inputB")

        print("[test4] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func check(_ test: String, _ condition: Bool, _ message: String) -> Bool {
        if !condition {
            print("[\(test)] FAIL: \(message)")
        }
        return condition
    }

    @discardableResult
    private static func fail(_ test: String, _ message: String) -> Bool {
        print("[\(test)] FAIL: \(message)")
        return false
    }
}
#endif
