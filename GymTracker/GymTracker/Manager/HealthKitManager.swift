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

// Model for workouts from HealthKit
struct HealthKitWorkout: Identifiable {
    let id = UUID()
    let name: String
    let type: HKWorkoutActivityType
    let duration: TimeInterval
    let calories: Double
    let startDate: Date
    let endDate: Date
    let distance: Double?
    
    var typeDisplayName: String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .crossTraining: return "Cross Training"
        case .functionalStrengthTraining: return "Functional Strength"
        case .traditionalStrengthTraining: return "Traditional Strength"
        case .hiking: return "Hiking"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        default: return "Other Workout"
        }
    }
}

@MainActor
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var weeklySteps: [Double] = []
    @Published var totalStepsWeek: Double = 0
    @Published var userWeight: Double? = 0
    @Published var workouts: [HealthKitWorkout] = []
    
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!

    func requestAuthorization() async {
        let toRead: Set = [stepsType, weightType, HKObjectType.workoutType()]
        try? await healthStore.requestAuthorization(toShare: [], read: toRead)
    }

    func fetchWeeklySteps() async {
        let calendar = Calendar.current
        let now = Date()
        
        // Start of today
        let startOfToday = calendar.startOfDay(for: now)
        
        // 6 days ago (start of that day)
        guard let startOfRange = calendar.date(byAdding: .day, value: -6, to: startOfToday) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfRange, end: now)
        
        let query = HKStatisticsCollectionQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startOfToday, // aligns buckets to day boundaries
            intervalComponents: DateComponents(day: 1)
        )
        
        self.totalStepsWeek = 0 // reset total
        
        var results = Array(repeating: 0.0, count: 7)
        // what the query runs
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
            
            Task { @MainActor in
                self.weeklySteps = results
                self.totalStepsWeek = results.reduce(0, +)
            }
        }
        
        healthStore.execute(query)
    }

    func fetchUserWeight() async {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        // gets only 1 result, could get more
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            
            Task { @MainActor in
                self.userWeight = weightKg
            }
        }
        healthStore.execute(query)
    }
    
    nonisolated func fetchWorkouts(days: Int = 30, workoutType: HKWorkoutActivityType? = nil) async {
        let calendar = Calendar.current
        let now = Date()
        
        // Start of the day
        let startOfToday = calendar.startOfDay(for: now)
        
        // X days ago
        guard let startOfRange = calendar.date(byAdding: .day, value: -days, to: startOfToday) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfRange, end: now)
        
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let workouts = samples as? [HKWorkout] else { return }
            
            let healthKitWorkouts = workouts
                .filter { workoutType == nil || $0.workoutActivityType == workoutType }
                .map { workout -> HealthKitWorkout in
                    // Get active energy burned using statisticsForType
                    let activeEnergyType = HKQuantityType(.activeEnergyBurned)
                    let calorieStats = workout.statistics(for: activeEnergyType)
                    let calories = calorieStats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    let distance = workout.totalDistance?.doubleValue(for: .meter())
                    
//                    print("DEBUG: Workout - Type: \(workout.workoutActivityType), Duration: \(workout.duration)s, Calories: \(calories), Distance: \(distance ?? 0)m")
                    
                    return HealthKitWorkout(
                        name: "Workout",
                        type: workout.workoutActivityType,
                        duration: workout.duration,
                        calories: calories,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        distance: distance
                    )
                }
            
            Task { @MainActor in
                self.workouts = healthKitWorkouts
            }
        }
        
        self.healthStore.execute(query)
    }
}
