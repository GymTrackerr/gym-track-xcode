//
//  HealthKitManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-08.
//

// https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
// https://developer.apple.com/videos/play/wwdc2021/10009/

// TODO: healthkit
// UI should not display healthkit if not allowed
// onboarding should request permission

import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var weeklySteps: [Double] = []
    @Published var totalStepsWeek: Double = 0
    @Published var userWeight: Double? = 0
    
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!

    func requestAuthorization() async {
        let toRead: Set = [stepsType, weightType]
        try? await healthStore.requestAuthorization(toShare: [], read: toRead)
    }

    func fetchWeeklySteps() async {
        let now = Date()
        guard let startOfWeek = Calendar.current.date(byAdding: .day, value: -6, to: now) else { return }

        var results: [Double] = Array(repeating: 0, count: 7)
        let predicate = HKQuery.predicateForSamples(withStart: startOfWeek, end: now)

        let query = HKStatisticsCollectionQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startOfWeek,
            intervalComponents: DateComponents(day: 1)
        )

        query.initialResultsHandler = { _, collection, _ in
            collection?.enumerateStatistics(from: startOfWeek, to: now) { stats, _ in
                let dayIndex = Calendar.current.dateComponents([.day], from: startOfWeek, to: stats.startDate).day ?? 0
                if dayIndex >= 0 && dayIndex < 7 {
                    results[dayIndex] = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    DispatchQueue.main.async {
                        
                        self.totalStepsWeek += results[dayIndex]
                    }
                }
            }
            DispatchQueue.main.async {
                self.weeklySteps = results
            }
        }

        healthStore.execute(query)
    }

    func fetchUserWeight() async {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            DispatchQueue.main.async {
                self.userWeight = weightKg
            }
        }
        healthStore.execute(query)
    }
}
