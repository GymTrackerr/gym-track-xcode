#if DEBUG
import Foundation

final class NotesImportParserDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== NotesImportParserDebug start ===")

        let results = [
            test1_HeaderPrefixDate(),
            test2_HeaderSuffixDate(),
            test3_BarDefaultWeight(),
            test4_ChainedSegmentsAndFractionalReps(),
            test5_BatchSplitAndCrossMidnight(),
            test6_UnknownLinesPreserved(),
            test7_CardioTelemetrySample(),
            test8_HeaderNormalizationFormats(),
            test9_StrictTimeRangeFormats(),
            test10_DropSetSegments()
        ]

        let passCount = results.filter { $0 }.count
        let total = results.count
        print("=== NotesImportParserDebug done: \(passCount)/\(total) passed ===")
    }

    @discardableResult
    private static func test1_HeaderPrefixDate() -> Bool {
        let parser = NotesImportParser()
        let input = """
        Pull, February 20, 2025
        08:10-09:00
        Deadlift, 3x5, 180kg
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .kg)
        printDraftSummary("test1", draft)

        var ok = true
        ok = ok && check("test1", draft.parsedDate != nil, "Expected parsed date")
        ok = ok && check("test1", draft.routineNameRaw == "Pull", "Expected routine 'Pull', got \(draft.routineNameRaw ?? "nil")")
        ok = ok && check("test1", draft.items.count == 1, "Expected 1 parsed item")

        print("[test1] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test2_HeaderSuffixDate() -> Bool {
        let parser = NotesImportParser()
        let input = """
        September 30, 2025 - Back and bicep
        18:30-19:25
        Lat pull, 3x10, 130 pounds
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .lb)
        printDraftSummary("test2", draft)

        var ok = true
        ok = ok && check("test2", draft.parsedDate != nil, "Expected parsed date")
        ok = ok && check("test2", draft.routineNameRaw == "Back and bicep", "Expected routine 'Back and bicep', got \(draft.routineNameRaw ?? "nil")")
        ok = ok && check("test2", draft.startTime != nil && draft.endTime != nil, "Expected parsed time range")

        print("[test2] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test3_BarDefaultWeight() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 15, 2025, Legs
        Back Squat, 2x5, bar
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .lb)
        printDraftSummary("test3", draft)

        var ok = true
        if case .strength(let strength)? = draft.items.first {
            let firstSet = strength.sets.first
            ok = ok && check("test3", strength.sets.count == 2, "Expected 2 sets")
            ok = ok && check("test3", firstSet?.baseWeight == 45, "Expected default bar baseWeight=45 for lb")
            ok = ok && check("test3", firstSet?.weight == 45, "Expected total weight=45 when only bar is provided")
            ok = ok && check("test3", firstSet?.weightUnit == .lb, "Expected weight unit lb")
        } else {
            ok = false
            print("[test3] FAIL: Expected first item to be strength")
        }

        print("[test3] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test4_ChainedSegmentsAndFractionalReps() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 15, 2025, Push
        Chest press, 1x5, 130 pounds, 1x6.5, 2x5, 110pounds (1:30m rest)
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .lb)
        printDraftSummary("test4", draft)

        var ok = true
        if case .strength(let strength)? = draft.items.first {
            ok = ok && check("test4", strength.sets.count == 4, "Expected 4 total sets")
            let reps = strength.sets.map(\.reps)
            ok = ok && check("test4", reps == [5, 6, 5, 5], "Expected reps [5,6,5,5], got \(reps)")

            let weights = strength.sets.map { Int($0.weight ?? -1) }
            ok = ok && check("test4", weights == [130, 110, 110, 110], "Expected nearest-following weight grouping [130,110,110,110], got \(weights)")
            ok = ok && check("test4", strength.sets.allSatisfy { $0.restSeconds == 90 }, "Expected restSeconds=90 for all sets")
            ok = ok && check("test4", !draft.warnings.isEmpty, "Expected warning for fractional reps")
        } else {
            ok = false
            print("[test4] FAIL: Expected first item to be strength")
        }

        print("[test4] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test5_BatchSplitAndCrossMidnight() -> Bool {
        let parser = NotesImportParser()
        let input = """
        Nov 15, 2022, Pull
        08:10-09:00
        Deadlift, 3 sets of 5, 180kg

        Pull, February 20, 2025
        22:30-00:10
        Indoor cycle, 20min, 10km
        """

        let batch = parser.parseBatch(from: input, defaultWeightUnit: .kg)
        for (index, draft) in batch.drafts.enumerated() {
            printDraftSummary("test5-draft\(index + 1)", draft)
        }

        var ok = true
        ok = ok && check("test5", batch.drafts.count == 2, "Expected 2 drafts")

        if batch.drafts.count == 2,
           let start = batch.drafts[1].startTime,
           let end = batch.drafts[1].endTime {
            ok = ok && check("test5", end > start, "Expected cross-midnight end > start")
        } else {
            ok = false
            print("[test5] FAIL: Missing second draft time range")
        }

        print("[test5] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test6_UnknownLinesPreserved() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 20, 2025, Misc
        Started watch workout
        Bench Press, 3x10
        Weird unparseable line
        Bike, 1km, 5:15min
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .lb)
        printDraftSummary("test6", draft)

        var ok = true
        ok = ok && check("test6", draft.items.count == 2, "Expected 2 parsed items")
        ok = ok && check("test6", draft.unknownLines.contains("Started watch workout"), "Expected unknown line to preserve watch text")
        ok = ok && check("test6", draft.unknownLines.contains("Weird unparseable line"), "Expected unknown line to be preserved")

        print("[test6] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test7_CardioTelemetrySample() -> Bool {
        let parser = NotesImportParser()
        let input = """
        January 22, 2025, Cardio
        1. Indoor cycle, 181W, 71RPM, 34.1KM/H, level 50, 4:01m, 2.25km
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .kg)
        printDraftSummary("test7", draft)

        var ok = true
        if case .cardio(let cardio)? = draft.items.first {
            let set = cardio.sets.first
            ok = ok && check("test7", set?.durationSeconds == 241, "Expected durationSeconds=241")
            ok = ok && check("test7", set?.distance == 2.25, "Expected distance=2.25")
            ok = ok && check("test7", set?.distanceUnit == .km, "Expected distance unit km")

            let notes = cardio.notes ?? ""
            ok = ok && check("test7", notes.contains("Power: 181W"), "Expected power telemetry in notes")
            ok = ok && check("test7", notes.contains("Cadence: 71 RPM"), "Expected cadence telemetry in notes")
            ok = ok && check("test7", notes.contains("Speed: 34.1 km/h"), "Expected speed telemetry in notes")
            ok = ok && check("test7", notes.contains("Level: 50"), "Expected level telemetry in notes")
        } else {
            ok = false
            print("[test7] FAIL: Expected first item to be cardio")
        }

        print("[test7] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test8_HeaderNormalizationFormats() -> Bool {
        let parser = NotesImportParser()

        let sample1 = parser.parseSingleSession(
            from: """
            Push, January, 22, 2025
            Bench Press, 3x8, 185lbs
            """,
            defaultWeightUnit: .lb
        )

        let sample2 = parser.parseSingleSession(
            from: """
            January, 22, 2025
            Push day
            Bench Press, 3x8, 185lbs
            """,
            defaultWeightUnit: .lb
        )

        let sample3 = parser.parseSingleSession(
            from: """
            September 30, 2025 - Back and bicep
            Lat pull, 3x10, 130 pounds
            """,
            defaultWeightUnit: .lb
        )

        printDraftSummary("test8-1", sample1)
        printDraftSummary("test8-2", sample2)
        printDraftSummary("test8-3", sample3)

        var ok = true
        ok = ok && check("test8", sample1.parsedDate != nil, "Expected date parse for comma-heavy header")
        ok = ok && check("test8", sample1.routineNameRaw == "Push", "Expected routine 'Push' from comma-heavy header")

        ok = ok && check("test8", sample2.parsedDate != nil, "Expected date parse for 'January, 22, 2025'")
        ok = ok && check("test8", sample2.routineNameRaw == "Push day", "Expected fallback routine 'Push day'")

        ok = ok && check("test8", sample3.parsedDate != nil, "Expected date parse for suffix routine header")
        ok = ok && check("test8", sample3.routineNameRaw == "Back and bicep", "Expected routine extraction for suffix header")

        print("[test8] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test9_StrictTimeRangeFormats() -> Bool {
        let parser = NotesImportParser()
        var ok = true
        let accepted12 = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            11:40am-1:00pm
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )
        let accepted12CrossMidnight = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            11:40 PM - 1:00 AM
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )
        let accepted24CrossMidnight = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            23:10-00:40
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )

        let rejectedMissingMeridiemLeft = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            11:40-1:00pm
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )
        let rejectedMissingMeridiemRight = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            11:40am-1:00
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )
        let rejectedNoMeridiem = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            11:40-1:00
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )
        let rejectedMixed = parser.parseSingleSession(
            from: """
            February 20, 2025, Pull
            23:10-1:00pm
            Deadlift, 3x5, 180kg
            """,
            defaultWeightUnit: .kg
        )

        printDraftSummary("test9-accepted12", accepted12)
        printDraftSummary("test9-accepted12-xm", accepted12CrossMidnight)
        printDraftSummary("test9-accepted24-xm", accepted24CrossMidnight)
        printDraftSummary("test9-reject-left", rejectedMissingMeridiemLeft)
        printDraftSummary("test9-reject-right", rejectedMissingMeridiemRight)
        printDraftSummary("test9-reject-none", rejectedNoMeridiem)
        printDraftSummary("test9-reject-mixed", rejectedMixed)

        ok = ok && check("test9", accepted12.startTime != nil && accepted12.endTime != nil, "Expected 12-hour format to parse")
        ok = ok && check("test9", accepted12CrossMidnight.startTime != nil && accepted12CrossMidnight.endTime != nil, "Expected AM/PM cross-midnight to parse")
        ok = ok && check("test9", accepted24CrossMidnight.startTime != nil && accepted24CrossMidnight.endTime != nil, "Expected 24-hour cross-midnight to parse")

        if let start = accepted12CrossMidnight.startTime, let end = accepted12CrossMidnight.endTime {
            ok = ok && check("test9", end > start, "Expected AM/PM cross-midnight end > start")
        } else {
            ok = false
            print("[test9] FAIL: Missing parsed times for AM/PM cross-midnight")
        }

        if let start = accepted24CrossMidnight.startTime, let end = accepted24CrossMidnight.endTime {
            ok = ok && check("test9", end > start, "Expected 24-hour cross-midnight end > start")
        } else {
            ok = false
            print("[test9] FAIL: Missing parsed times for 24-hour cross-midnight")
        }

        ok = ok && check("test9", rejectedMissingMeridiemLeft.startTime == nil && rejectedMissingMeridiemLeft.endTime == nil, "Expected reject for missing AM/PM on left side")
        ok = ok && check("test9", rejectedMissingMeridiemRight.startTime == nil && rejectedMissingMeridiemRight.endTime == nil, "Expected reject for missing AM/PM on right side")
        ok = ok && check("test9", rejectedNoMeridiem.startTime == nil && rejectedNoMeridiem.endTime == nil, "Expected reject for missing AM/PM on both sides")
        ok = ok && check("test9", rejectedMixed.startTime == nil && rejectedMixed.endTime == nil, "Expected reject for mixed 24h + AM/PM format")

        print("[test9] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    @discardableResult
    private static func test10_DropSetSegments() -> Bool {
        let parser = NotesImportParser()
        let input = """
        December 15, 2025, Pull
        Barbell Row, 2x6 25kg +3 22.5kg
        """

        let draft = parser.parseSingleSession(from: input, defaultWeightUnit: .kg)
        printDraftSummary("test10", draft)

        var ok = true
        if case .strength(let strength)? = draft.items.first {
            ok = ok && check("test10", strength.sets.count == 2, "Expected exactly 2 top-level sets")
            for (index, set) in strength.sets.enumerated() {
                ok = ok && check("test10", set.repSegments.count == 2, "Set \(index + 1) should have 2 rep segments")
                if set.repSegments.count == 2 {
                    let first = set.repSegments[0]
                    let second = set.repSegments[1]
                    ok = ok && check("test10", first.reps == 6 && first.weight == 25, "Expected first segment 6 reps @ 25kg")
                    ok = ok && check("test10", second.reps == 3 && second.weight == 22.5, "Expected drop segment 3 reps @ 22.5kg")
                }
            }
        } else {
            ok = false
            print("[test10] FAIL: Expected first item to be strength")
        }

        print("[test10] \(ok ? "PASS" : "FAIL")")
        return ok
    }

    private static func printDraftSummary(_ test: String, _ draft: NotesImportDraft) {
        print("[\(test)] header routine=\(draft.routineNameRaw ?? "nil") date=\(draft.parsedDate?.formatted(date: .abbreviated, time: .omitted) ?? "nil") items=\(draft.items.count) warnings=\(draft.warnings.count) unknown=\(draft.unknownLines.count)")

        for item in draft.items {
            switch item {
            case .strength(let strength):
                let setDescription = strength.sets.map { "\($0.reps)x @\($0.weight.map { String($0) } ?? "nil") \($0.weightUnit.name)" }.joined(separator: " | ")
                print("[\(test)] strength \(strength.exerciseNameRaw): \(setDescription)")
            case .cardio(let cardio):
                let setDescription = cardio.sets.map { set in
                    "dur=\(set.durationSeconds.map { String($0) } ?? "nil") dist=\(set.distance.map { String($0) } ?? "nil") \(set.distanceUnit.rawValue) pace=\(set.paceSeconds.map { String($0) } ?? "nil")"
                }.joined(separator: " | ")
                print("[\(test)] cardio \(cardio.exerciseNameRaw): \(setDescription) notes=\(cardio.notes ?? "nil")")
            }
        }
    }

    @discardableResult
    private static func check(_ test: String, _ condition: Bool, _ message: String) -> Bool {
        if !condition {
            print("[\(test)] FAIL: \(message)")
        }
        return condition
    }
}
#endif
