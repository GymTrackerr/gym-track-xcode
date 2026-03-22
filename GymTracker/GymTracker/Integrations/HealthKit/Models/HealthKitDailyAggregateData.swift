import Foundation

struct HealthKitDailyAggregateData: Identifiable, Sendable {
    let userId: String
    let dayKey: String
    let dayStart: Date
    let steps: Double
    let activeEnergyKcal: Double
    let restingEnergyKcal: Double
    let sleepSeconds: TimeInterval

    var id: String { "\(userId)|\(dayKey)" }
}
