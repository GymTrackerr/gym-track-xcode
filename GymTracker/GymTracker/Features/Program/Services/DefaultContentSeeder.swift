import Foundation
import SwiftData
import Combine

final class DefaultContentSeeder: ServiceBase, ObservableObject {
    private var didSeedThisLaunch = false

    override func loadFeature() {
        guard !didSeedThisLaunch else { return }
        guard let userId = currentUser?.id else { return }

        didSeedThisLaunch = true
        seedDefaultContent(for: userId)
    }

    private func seedDefaultContent(for userId: UUID) {
        let profileByKey = seedBuiltInProgressionProfiles(userId: userId)
        seedBuiltInRoutines(userId: userId)
        seedBuiltInPrograms(userId: userId, profileByKey: profileByKey)
        try? modelContext.save()
    }

    private func seedBuiltInProgressionProfiles(userId: UUID) -> [String: ProgressionProfile] {
        let builtIns: [BuiltInProgressionProfileDefinition] = [
            .init(
                key: "builtin.progression.linear",
                name: "Linear Progression",
                type: .linear,
                requiredSuccessSessions: 1,
                incrementValue: 5,
                incrementUnit: .pounds,
                successPolicy: .allTargetsMet,
                defaultRepsTarget: 8,
                defaultRepsLow: nil,
                defaultRepsHigh: nil
            ),
            .init(
                key: "builtin.progression.double",
                name: "Double Progression",
                type: .doubleProgression,
                requiredSuccessSessions: 1,
                incrementValue: 5,
                incrementUnit: .pounds,
                successPolicy: .allTargetsMet,
                defaultRepsTarget: nil,
                defaultRepsLow: 8,
                defaultRepsHigh: 12
            ),
            .init(
                key: "builtin.progression.two_success",
                name: "Two Success Progression",
                type: .linear,
                requiredSuccessSessions: 2,
                incrementValue: 5,
                incrementUnit: .pounds,
                successPolicy: .allTargetsMet,
                defaultRepsTarget: 8,
                defaultRepsLow: nil,
                defaultRepsHigh: nil
            ),
            .init(
                key: "builtin.progression.three_success",
                name: "Three Success Progression",
                type: .linear,
                requiredSuccessSessions: 3,
                incrementValue: 5,
                incrementUnit: .pounds,
                successPolicy: .allTargetsMet,
                defaultRepsTarget: 8,
                defaultRepsLow: nil,
                defaultRepsHigh: nil
            )
        ]

        var map: [String: ProgressionProfile] = [:]
        for definition in builtIns {
            let profile = upsertProgressionProfile(definition: definition, userId: userId)
            map[definition.key] = profile
        }
        return map
    }

    private func upsertProgressionProfile(
        definition: BuiltInProgressionProfileDefinition,
        userId: UUID
    ) -> ProgressionProfile {
        if let existing = fetchBuiltInProgressionProfile(userId: userId, key: definition.key, fallbackName: definition.name) {
            existing.name = definition.name
            existing.type = definition.type.rawValue
            existing.requiredSuccessSessions = definition.requiredSuccessSessions
            existing.incrementValue = definition.incrementValue
            existing.incrementUnit = definition.incrementUnit.rawValue
            existing.successPolicy = definition.successPolicy.rawValue
            existing.defaultRepsTarget = definition.defaultRepsTarget
            existing.defaultRepsLow = definition.defaultRepsLow
            existing.defaultRepsHigh = definition.defaultRepsHigh
            existing.isBuiltIn = true
            existing.builtInKey = definition.key
            existing.isArchived = false
            return existing
        }

        let created = ProgressionProfile(
            user_id: userId,
            name: definition.name,
            type: definition.type,
            requiredSuccessSessions: definition.requiredSuccessSessions,
            incrementValue: definition.incrementValue,
            incrementUnit: definition.incrementUnit,
            successPolicy: definition.successPolicy,
            defaultRepsTarget: definition.defaultRepsTarget,
            defaultRepsLow: definition.defaultRepsLow,
            defaultRepsHigh: definition.defaultRepsHigh,
            isBuiltIn: true,
            builtInKey: definition.key,
            isArchived: false
        )
        modelContext.insert(created)
        return created
    }

    private func fetchBuiltInProgressionProfile(userId: UUID, key: String, fallbackName: String) -> ProgressionProfile? {
        let descriptor = FetchDescriptor<ProgressionProfile>(
            predicate: #Predicate<ProgressionProfile> { profile in
                profile.user_id == userId
                && profile.isBuiltIn == true
                && (profile.builtInKey == key || profile.name == fallbackName)
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first
    }

    private func seedBuiltInPrograms(userId: UUID, profileByKey: [String: ProgressionProfile]) {
        let builtIns: [BuiltInProgramDefinition] = [
            beginnerFullBodyProgram(profileByKey: profileByKey),
            pushPullLegsProgram(profileByKey: profileByKey)
        ]

        for definition in builtIns {
            let program = upsertProgram(definition: definition, userId: userId)
            upsertProgramDays(program: program, definition: definition, userId: userId)
        }
    }

    private func seedBuiltInRoutines(userId: UUID) {
        let builtIns: [BuiltInRoutineDefinition] = [
            .init(
                key: "builtin.routine.full_body_a",
                name: "Full Body A",
                order: 0,
                aliases: [],
                exercises: [
                    .named("Barbell Squat"),
                    .named("Dumbbell Bench Press"),
                    .named("Lying T-Bar Row")
                ]
            ),
            .init(
                key: "builtin.routine.full_body_b",
                name: "Full Body B",
                order: 1,
                aliases: [],
                exercises: [
                    .named("Deadlift"),
                    .named("Barbell Shoulder Press"),
                    .named("Wide-Grip Lat Pulldown")
                ]
            ),
            .init(
                key: "builtin.routine.full_body_c",
                name: "Full Body C",
                order: 2,
                aliases: [],
                exercises: [
                    .named("Barbell Squat"),
                    .named("Dumbbell Bench Press"),
                    .named("Lying T-Bar Row")
                ]
            ),
            .init(
                key: "builtin.routine.push",
                name: "Push",
                order: 3,
                aliases: [],
                exercises: [
                    .named("Bench Press"),
                    .named("Barbell Shoulder Press"),
                    .named("Triceps Pushdown")
                ]
            ),
            .init(
                key: "builtin.routine.pull",
                name: "Pull",
                order: 4,
                aliases: [],
                exercises: [
                    .named("Barbell Rear Delt Row"),
                    .named("Wide-Grip Lat Pulldown"),
                    .named("Barbell Curl")
                ]
            ),
            .init(
                key: "builtin.routine.legs",
                name: "Legs",
                order: 5,
                aliases: [],
                exercises: [
                    .named("Barbell Squat"),
                    .named("Romanian Deadlift"),
                    .named("Leg Press")
                ]
            )
        ]

        for definition in builtIns {
            let routine = upsertBuiltInRoutine(definition: definition, userId: userId)
            upsertBuiltInRoutineExercises(routine: routine, definition: definition, userId: userId)
        }
    }

    private func upsertBuiltInRoutine(definition: BuiltInRoutineDefinition, userId: UUID) -> Routine {
        if let existing = fetchBuiltInRoutine(userId: userId, key: definition.key, fallbackName: definition.name) {
            existing.name = definition.name
            existing.order = definition.order
            existing.aliases = definition.aliases
            existing.isArchived = false
            existing.isBuiltIn = true
            existing.builtInKey = definition.key
            return existing
        }

        let created = Routine(
            order: definition.order,
            name: definition.name,
            user_id: userId,
            isBuiltIn: true,
            builtInKey: definition.key
        )
        created.aliases = definition.aliases
        modelContext.insert(created)
        return created
    }

    private func fetchBuiltInRoutine(userId: UUID, key: String, fallbackName: String) -> Routine? {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId
                && routine.isBuiltIn == true
                && (routine.builtInKey == key || routine.name == fallbackName)
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first
    }

    private func upsertBuiltInRoutineExercises(
        routine: Routine,
        definition: BuiltInRoutineDefinition,
        userId: UUID
    ) {
        let existingByOrder = Dictionary(uniqueKeysWithValues: routine.exerciseSplits.map { ($0.order, $0) })

        for (index, exerciseRef) in definition.exercises.enumerated() {
            guard let resolvedExercise = resolveExercise(reference: exerciseRef, userId: userId) else {
                continue
            }

            if let existing = existingByOrder[index] {
                existing.exercise = resolvedExercise
            } else {
                let created = ExerciseSplitDay(order: index, routine: routine, exercise: resolvedExercise)
                modelContext.insert(created)
                routine.exerciseSplits.append(created)
            }
        }
    }

    private func upsertProgram(definition: BuiltInProgramDefinition, userId: UUID) -> Program {
        if let existing = fetchBuiltInProgram(userId: userId, key: definition.key, fallbackName: definition.name) {
            existing.name = definition.name
            existing.notes = definition.notes
            existing.isActive = definition.isActive
            existing.startDate = definition.startDate
            existing.isArchived = false
            existing.isBuiltIn = true
            existing.builtInKey = definition.key
            return existing
        }

        let created = Program(
            user_id: userId,
            name: definition.name,
            notes: definition.notes,
            isArchived: false,
            isActive: definition.isActive,
            isBuiltIn: true,
            builtInKey: definition.key,
            startDate: definition.startDate
        )
        modelContext.insert(created)
        return created
    }

    private func fetchBuiltInProgram(userId: UUID, key: String, fallbackName: String) -> Program? {
        let descriptor = FetchDescriptor<Program>(
            predicate: #Predicate<Program> { program in
                program.user_id == userId
                && program.isBuiltIn == true
                && (program.builtInKey == key || program.name == fallbackName)
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.sorted(by: { $0.id.uuidString < $1.id.uuidString }).first
    }

    private func upsertProgramDays(program: Program, definition: BuiltInProgramDefinition, userId: UUID) {
        let existingByOrder = Dictionary(uniqueKeysWithValues: program.programDays.map { ($0.order, $0) })

        for dayDefinition in definition.days {
            let programDay: ProgramDay
            if let existing = existingByOrder[dayDefinition.order] {
                programDay = existing
                programDay.title = dayDefinition.title
                programDay.weekIndex = dayDefinition.weekIndex
                programDay.dayIndex = dayDefinition.dayIndex
                programDay.blockIndex = dayDefinition.blockIndex
                programDay.order = dayDefinition.order
                programDay.routine = resolveBuiltInRoutine(key: dayDefinition.routineBuiltInKey, userId: userId)
            } else {
                let created = ProgramDay(
                    user_id: userId,
                    program: program,
                    routine: resolveBuiltInRoutine(key: dayDefinition.routineBuiltInKey, userId: userId),
                    weekIndex: dayDefinition.weekIndex,
                    dayIndex: dayDefinition.dayIndex,
                    blockIndex: dayDefinition.blockIndex,
                    title: dayDefinition.title,
                    order: dayDefinition.order
                )
                modelContext.insert(created)
                program.programDays.append(created)
                programDay = created
            }

            upsertOverrides(programDay: programDay, definitions: dayDefinition.overrides, userId: userId)
        }
    }

    private func upsertOverrides(programDay: ProgramDay, definitions: [BuiltInOverrideDefinition], userId: UUID) {
        let existingByOrder = Dictionary(uniqueKeysWithValues: programDay.exerciseOverrides.map { ($0.order, $0) })

        for overrideDefinition in definitions {
            let resolvedExercise = resolveExercise(reference: overrideDefinition.exerciseRef, userId: userId)

            if let existing = existingByOrder[overrideDefinition.order] {
                existing.exercise = resolvedExercise
                existing.progression = overrideDefinition.progression
                existing.setsTarget = overrideDefinition.setsTarget
                existing.repsTarget = overrideDefinition.repsTarget
                existing.repsLow = overrideDefinition.repsLow
                existing.repsHigh = overrideDefinition.repsHigh
                existing.notes = overrideDefinition.notes
            } else {
                let created = ProgramDayExerciseOverride(
                    user_id: userId,
                    programDay: programDay,
                    exercise: resolvedExercise,
                    progression: overrideDefinition.progression,
                    setsTarget: overrideDefinition.setsTarget,
                    repsTarget: overrideDefinition.repsTarget,
                    repsLow: overrideDefinition.repsLow,
                    repsHigh: overrideDefinition.repsHigh,
                    notes: overrideDefinition.notes,
                    order: overrideDefinition.order
                )
                modelContext.insert(created)
                programDay.exerciseOverrides.append(created)
            }
        }
    }

    private func resolveBuiltInRoutine(key: String, userId: UUID) -> Routine? {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.user_id == userId
                && routine.isBuiltIn == true
                && routine.builtInKey == key
                && routine.isArchived == false
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func resolveExercise(reference: BuiltInExerciseReference, userId: UUID) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { exercise in
                exercise.user_id == userId && exercise.isArchived == false
            }
        )

        let exercises = (try? modelContext.fetch(descriptor)) ?? []

        // 1) npId
        if let npId = reference.npId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !npId.isEmpty,
           let byNpId = exercises.first(where: { ($0.npId ?? "").lowercased() == npId }) {
            return byNpId
        }

        // 2) exact case-insensitive name
        if let byName = exercises.first(where: { $0.name.compare(reference.name, options: .caseInsensitive) == .orderedSame }) {
            return byName
        }

        // 3) alias contains
        for exercise in exercises {
            let aliases = exercise.aliases ?? []
            if aliases.contains(where: { $0.range(of: reference.name, options: .caseInsensitive) != nil }) {
                return exercise
            }
        }

        return nil
    }

    private func beginnerFullBodyProgram(profileByKey: [String: ProgressionProfile]) -> BuiltInProgramDefinition {
        BuiltInProgramDefinition(
            key: "builtin.program.beginner_full_body",
            name: "Beginner Full Body",
            notes: "Simple full-body starter template with manageable volume.",
            isActive: false,
            startDate: nil,
            days: [
                BuiltInProgramDayDefinition(
                    order: 0,
                    title: "Full Body A",
                    weekIndex: 0,
                    dayIndex: 0,
                    blockIndex: nil,
                    routineBuiltInKey: "builtin.routine.full_body_a",
                    overrides: [
                        .init(order: 0, exerciseRef: .named("Barbell Squat"), progression: profileByKey["builtin.progression.linear"], setsTarget: 3, repsTarget: 5, repsLow: nil, repsHigh: nil, notes: ""),
                        .init(order: 1, exerciseRef: .named("Bench Press"), progression: profileByKey["builtin.progression.linear"], setsTarget: 3, repsTarget: 5, repsLow: nil, repsHigh: nil, notes: ""),
                        .init(order: 2, exerciseRef: .named("Barbell Row"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 3, repsTarget: 8, repsLow: nil, repsHigh: nil, notes: "")
                    ]
                ),
                BuiltInProgramDayDefinition(
                    order: 1,
                    title: "Full Body B",
                    weekIndex: 0,
                    dayIndex: 1,
                    blockIndex: nil,
                    routineBuiltInKey: "builtin.routine.full_body_b",
                    overrides: [
                        .init(order: 0, exerciseRef: .named("Deadlift"), progression: profileByKey["builtin.progression.linear"], setsTarget: 1, repsTarget: 5, repsLow: nil, repsHigh: nil, notes: ""),
                        .init(order: 1, exerciseRef: .named("Overhead Press"), progression: profileByKey["builtin.progression.linear"], setsTarget: 3, repsTarget: 5, repsLow: nil, repsHigh: nil, notes: ""),
                        .init(order: 2, exerciseRef: .named("Lat Pulldown"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 3, repsTarget: nil, repsLow: 8, repsHigh: 12, notes: "")
                    ]
                )
            ]
        )
    }

    private func pushPullLegsProgram(profileByKey: [String: ProgressionProfile]) -> BuiltInProgramDefinition {
        BuiltInProgramDefinition(
            key: "builtin.program.push_pull_legs",
            name: "Push Pull Legs",
            notes: "Classic 3-day split with balanced volume.",
            isActive: false,
            startDate: nil,
            days: [
                BuiltInProgramDayDefinition(
                    order: 0,
                    title: "Push",
                    weekIndex: 0,
                    dayIndex: 0,
                    blockIndex: nil,
                    routineBuiltInKey: "builtin.routine.push",
                    overrides: [
                        .init(order: 0, exerciseRef: .named("Bench Press"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 4, repsTarget: nil, repsLow: 6, repsHigh: 8, notes: ""),
                        .init(order: 1, exerciseRef: .named("Overhead Press"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 3, repsTarget: nil, repsLow: 8, repsHigh: 10, notes: ""),
                        .init(order: 2, exerciseRef: .named("Triceps Pushdown"), progression: profileByKey["builtin.progression.double"], setsTarget: 3, repsTarget: nil, repsLow: 10, repsHigh: 15, notes: "")
                    ]
                ),
                BuiltInProgramDayDefinition(
                    order: 1,
                    title: "Pull",
                    weekIndex: 0,
                    dayIndex: 1,
                    blockIndex: nil,
                    routineBuiltInKey: "builtin.routine.pull",
                    overrides: [
                        .init(order: 0, exerciseRef: .named("Barbell Row"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 4, repsTarget: nil, repsLow: 6, repsHigh: 8, notes: ""),
                        .init(order: 1, exerciseRef: .named("Lat Pulldown"), progression: profileByKey["builtin.progression.double"], setsTarget: 3, repsTarget: nil, repsLow: 8, repsHigh: 12, notes: ""),
                        .init(order: 2, exerciseRef: .named("Barbell Curl"), progression: profileByKey["builtin.progression.double"], setsTarget: 3, repsTarget: nil, repsLow: 10, repsHigh: 15, notes: "")
                    ]
                ),
                BuiltInProgramDayDefinition(
                    order: 2,
                    title: "Legs",
                    weekIndex: 0,
                    dayIndex: 2,
                    blockIndex: nil,
                    routineBuiltInKey: "builtin.routine.legs",
                    overrides: [
                        .init(order: 0, exerciseRef: .named("Barbell Squat"), progression: profileByKey["builtin.progression.three_success"], setsTarget: 4, repsTarget: nil, repsLow: 5, repsHigh: 8, notes: ""),
                        .init(order: 1, exerciseRef: .named("Romanian Deadlift"), progression: profileByKey["builtin.progression.two_success"], setsTarget: 3, repsTarget: nil, repsLow: 8, repsHigh: 10, notes: ""),
                        .init(order: 2, exerciseRef: .named("Leg Press"), progression: profileByKey["builtin.progression.double"], setsTarget: 3, repsTarget: nil, repsLow: 10, repsHigh: 15, notes: "")
                    ]
                )
            ]
        )
    }
}

private struct BuiltInProgressionProfileDefinition {
    let key: String
    let name: String
    let type: ProgressionType
    let requiredSuccessSessions: Int
    let incrementValue: Double
    let incrementUnit: ProgressionIncrementUnit
    let successPolicy: ProgressionSuccessPolicy
    let defaultRepsTarget: Int?
    let defaultRepsLow: Int?
    let defaultRepsHigh: Int?
}

private struct BuiltInProgramDefinition {
    let key: String
    let name: String
    let notes: String
    let isActive: Bool
    let startDate: Date?
    let days: [BuiltInProgramDayDefinition]
}

private struct BuiltInProgramDayDefinition {
    let order: Int
    let title: String
    let weekIndex: Int
    let dayIndex: Int
    let blockIndex: Int?
    let routineBuiltInKey: String
    let overrides: [BuiltInOverrideDefinition]
}

private struct BuiltInRoutineDefinition {
    let key: String
    let name: String
    let order: Int
    let aliases: [String]
    let exercises: [BuiltInExerciseReference]
}

private struct BuiltInOverrideDefinition {
    let order: Int
    let exerciseRef: BuiltInExerciseReference
    let progression: ProgressionProfile?
    let setsTarget: Int?
    let repsTarget: Int?
    let repsLow: Int?
    let repsHigh: Int?
    let notes: String

    init(
        order: Int,
        exerciseRef: BuiltInExerciseReference,
        progression: ProgressionProfile?,
        setsTarget: Int?,
        repsTarget: Int?,
        repsLow: Int?,
        repsHigh: Int?,
        notes: String
    ) {
        self.order = order
        self.exerciseRef = exerciseRef
        self.progression = progression
        self.setsTarget = setsTarget
        self.repsTarget = repsTarget
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.notes = notes
    }
}

private struct BuiltInExerciseReference {
    let npId: String?
    let name: String

    static func named(_ name: String) -> BuiltInExerciseReference {
        BuiltInExerciseReference(npId: nil, name: name)
    }
}
