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
        let calendar = Calendar.current
        let now = Date()
        
        // Start of today
        let startOfToday = calendar.startOfDay(for: now)
        
        // 6 days ago (start of that day)
        guard let startOfRange = calendar.date(byAdding: .day, value: -6, to: startOfToday) else { return }
        
        var results = Array(repeating: 0.0, count: 7)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfRange, end: now)
        
        let query = HKStatisticsCollectionQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startOfToday, // aligns buckets to day boundaries
            intervalComponents: DateComponents(day: 1)
        )
        
        self.totalStepsWeek = 0 // reset total
        
        query.initialResultsHandler = { _, collection, _ in
            guard let collection = collection else { return }
            
            collection.enumerateStatistics(from: startOfRange, to: now) { stats, _ in
                let dayStart = calendar.startOfDay(for: stats.startDate)
                if let dayIndex = calendar.dateComponents([.day], from: startOfRange, to: dayStart).day,
                   dayIndex >= 0 && dayIndex < 7 {
                    let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    results[dayIndex] = steps
                }
            }
            
            DispatchQueue.main.async {
                self.weeklySteps = results
                self.totalStepsWeek = results.reduce(0, +)
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
