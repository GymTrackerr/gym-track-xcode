#if DEBUG
import Foundation
import SwiftData

enum RoutineDeletionSafetyTests {
    static func run(context: ModelContext, userId: UUID) {
        print("=== RoutineDeletionSafetyTests start ===")

        let routineA = Routine(order: 9000, name: "Routine A", user_id: userId)
        let routineB = Routine(order: 9001, name: "Routine B", user_id: userId)
        let linkedSession = Session(timestamp: Date(), user_id: userId, routine: routineA, notes: "linked")
        let unrelatedSession = Session(timestamp: Date().addingTimeInterval(60), user_id: userId, routine: nil, notes: "unrelated")

        context.insert(routineA)
        context.insert(routineB)
        context.insert(linkedSession)
        context.insert(unrelatedSession)

        do {
            try context.save()

            let beforeCount = try context.fetch(
                FetchDescriptor<Session>(
                    predicate: #Predicate<Session> { $0.user_id == userId }
                )
            ).count

            context.delete(routineA)
            try context.save()

            let sessionsAfterDelete = try context.fetch(
                FetchDescriptor<Session>(
                    predicate: #Predicate<Session> { $0.user_id == userId }
                )
            )

            let afterCount = sessionsAfterDelete.count
            let linkedStillExists = sessionsAfterDelete.contains(where: { $0.id == linkedSession.id })
            let unrelatedStillExists = sessionsAfterDelete.contains(where: { $0.id == unrelatedSession.id })
            let linkedRoutineCleared = sessionsAfterDelete.first(where: { $0.id == linkedSession.id })?.routine == nil

            let pass = beforeCount == afterCount && linkedStillExists && unrelatedStillExists && linkedRoutineCleared
            print("[routine-delete-test] \(pass ? "PASS" : "FAIL")")
            if !pass {
                print("[routine-delete-test] before=\(beforeCount) after=\(afterCount) linkedExists=\(linkedStillExists) unrelatedExists=\(unrelatedStillExists) linkedRoutineNil=\(linkedRoutineCleared)")
            }
        } catch {
            print("[routine-delete-test] FAIL: \(error)")
            context.rollback()
        }

        print("=== RoutineDeletionSafetyTests done ===")
    }
}
#endif
