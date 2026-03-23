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
import SwiftUI

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

// Model for sleep data from HealthKit
struct HealthKitSleep: Identifiable {
    let id = UUID()
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
    let sleepScore: Double? // Optional sleep analysis score
    
    var durationHours: Double {
        duration / 3600
    }
}

// Model for activity ring status
struct ActivityRingStatus: Identifiable {
    let id = UUID()
    var moveRingValue: Double
    let moveRingGoal: Double
    var exerciseRingValue: Double
    let exerciseRingGoal: Double
    var standRingValue: Int // Stand hours
    let standRingGoal: Int // Stand goal hours
    
    var moveRingPercentage: Double {
        moveRingGoal > 0 ? (moveRingValue / moveRingGoal) * 100 : 0
    }
    
    var exerciseRingPercentage: Double {
        exerciseRingGoal > 0 ? (exerciseRingValue / exerciseRingGoal) * 100 : 0
    }
    
    var standRingPercentage: Double {
        standRingGoal > 0 ? Double(standRingValue) / Double(standRingGoal) * 100 : 0
    }
}

@MainActor
class HealthKitManager: ObservableObject {
    // should change to private
    public let healthStore = HKHealthStore()
    
    @Published var weeklySteps: [Double] = []
    @Published var totalStepsWeek: Double = 0
    @Published var userWeight: Double? = 0
    @Published var workouts: [HealthKitWorkout] = []
    @Published var sleepData: [HealthKitSleep] = []
    @Published var activityRingStatus: ActivityRingStatus?
    
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    private let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
    private let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
    private let standTimeType = HKQuantityType.quantityType(forIdentifier: .appleStandTime)!

    
    @AppStorage("hkRequested") var hkRequested: Bool = false
    @Published var hkConnected: Bool = false

    func requestAuthorization() async {
//        func requestAuthorization() async {
        let toRead: Set = [ stepsType, weightType, HKObjectType.workoutType(), sleepType, activeEnergyType, restingEnergyType, exerciseTimeType, standTimeType, HKSeriesType.workoutRoute() ]
//            try? await healthStore./*requestAuthorization*/(toShare: [], read: toRead) }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: toRead)
            hkRequested = true
            await refreshConnectionState()
        } catch {
            hkRequested = false
            hkConnected = false
        }
    }

    func refreshConnectionState() async {
        // simplest: try reading step count for last 1 day
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: now)

        let ok = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: stepsType, predicate: pred, limit: 1, sortDescriptors: nil) { _, _, error in
                cont.resume(returning: error == nil)
            }
            healthStore.execute(q)
        }

        hkConnected = ok
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

    func fetchDailyAggregate(for day: Date, userId: String) async throws -> HealthKitDailyAggregateData {
        let results = try await fetchDailyAggregates(from: day, to: day, userId: userId, calendar: .current)
        guard let first = results.first else {
            let normalizer = HealthKitDateNormalizer()
            let dayStart = normalizer.startOfDay(day)
            return HealthKitDailyAggregateData(
                userId: userId,
                dayKey: normalizer.dayKey(dayStart),
                dayStart: dayStart,
                steps: 0,
                activeEnergyKcal: 0,
                restingEnergyKcal: 0,
                sleepSeconds: 0,
                bodyWeightKg: 0,
                schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
            )
        }
        return first
    }

    func fetchDailyAggregates(
        from fromDate: Date,
        to toDate: Date,
        userId: String,
        calendar: Calendar
    ) async throws -> [HealthKitDailyAggregateData] {
        let normalizer = HealthKitDateNormalizer(calendar: calendar)
        let startDay = normalizer.startOfDay(min(fromDate, toDate))
        let endDay = normalizer.startOfDay(max(fromDate, toDate))
        let dayCount = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        let days = normalizer.buildDateRange(endingOn: endDay, days: dayCount)

        async let stepsSeries = fetchQuantitySeries(
            type: HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            unit: .count(),
            from: startDay,
            to: endDay,
            calendar: calendar,
            normalizer: normalizer
        )
        async let activeSeries = fetchQuantitySeries(
            type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            unit: .kilocalorie(),
            from: startDay,
            to: endDay,
            calendar: calendar,
            normalizer: normalizer
        )
        async let restingSeries = fetchQuantitySeries(
            type: HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!,
            unit: .kilocalorie(),
            from: startDay,
            to: endDay,
            calendar: calendar,
            normalizer: normalizer
        )
        async let sleepSeries = fetchSleepSeries(
            from: startDay,
            to: endDay,
            calendar: calendar,
            normalizer: normalizer
        )
        async let weightSeries = fetchBodyMassSeries(
            from: startDay,
            to: endDay,
            calendar: calendar,
            normalizer: normalizer
        )

        let stepsByDay = await stepsSeries
        let activeByDay = await activeSeries
        let restingByDay = await restingSeries
        let sleepByDay = await sleepSeries
        let weightByDay = await weightSeries

        return days.map { dayStart in
            let dayKey = normalizer.dayKey(dayStart)
            return HealthKitDailyAggregateData(
                userId: userId,
                dayKey: dayKey,
                dayStart: dayStart,
                steps: stepsByDay[dayKey] ?? 0,
                activeEnergyKcal: activeByDay[dayKey] ?? 0,
                restingEnergyKcal: restingByDay[dayKey] ?? 0,
                sleepSeconds: sleepByDay[dayKey] ?? 0,
                bodyWeightKg: weightByDay[dayKey] ?? 0,
                schemaVersion: HealthKitDailyAggregateData.currentSchemaVersion
            )
        }
    }

    private func fetchBodyMassSeries(
        from fromDay: Date,
        to toDay: Date,
        calendar: Calendar,
        normalizer: HealthKitDateNormalizer
    ) async -> [String: Double] {
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: toDay) ?? toDay
        let predicate = HKQuery.predicateForSamples(withStart: fromDay, end: endExclusive, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: weightType,
                quantitySamplePredicate: predicate,
                options: HKStatisticsOptions.mostRecent,
                anchorDate: fromDay,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }

                var result: [String: Double] = [:]
                collection.enumerateStatistics(from: fromDay, to: endExclusive) { stats, _ in
                    guard let quantity = stats.mostRecentQuantity() else { return }
                    let dayStart = normalizer.startOfDay(stats.startDate)
                    let dayKey = normalizer.dayKey(dayStart)
                    result[dayKey] = quantity.doubleValue(for: .gramUnit(with: .kilo))
                }
                continuation.resume(returning: result)
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchQuantitySeries(
        type: HKQuantityType,
        unit: HKUnit,
        from fromDay: Date,
        to toDay: Date,
        calendar: Calendar,
        normalizer: HealthKitDateNormalizer
    ) async -> [String: Double] {
        let intervalEndExclusive = calendar.date(byAdding: .day, value: 1, to: toDay) ?? toDay
        let predicate = HKQuery.predicateForSamples(withStart: fromDay, end: intervalEndExclusive, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: fromDay,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }
                var result: [String: Double] = [:]
                collection.enumerateStatistics(from: fromDay, to: intervalEndExclusive) { stats, _ in
                    let dayStart = normalizer.startOfDay(stats.startDate)
                    let dayKey = normalizer.dayKey(dayStart)
                    let value = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                    result[dayKey] = value
                }
                continuation.resume(returning: result)
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchSleepSeries(
        from fromDay: Date,
        to toDay: Date,
        calendar: Calendar,
        normalizer: HealthKitDateNormalizer
    ) async -> [String: TimeInterval] {
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: toDay) ?? toDay
        let windowStart = calendar.date(byAdding: .hour, value: -18, to: fromDay) ?? fromDay
        let windowEnd = calendar.date(byAdding: .hour, value: 12, to: endExclusive) ?? endExclusive

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
            let query = HKSampleQuery(
                sampleType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                var totals: [String: TimeInterval] = [:]

                for sample in sleepSamples {
                    guard sample.value != HKCategoryValueSleepAnalysis.awake.rawValue else { continue }
                    guard sample.endDate >= fromDay && sample.endDate < endExclusive else { continue }

                    let dayStart = normalizer.startOfDay(sample.endDate)
                    let dayKey = normalizer.dayKey(dayStart)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    totals[dayKey, default: 0] += duration
                }

                continuation.resume(returning: totals)
            }
            self.healthStore.execute(query)
        }
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
    
    func fetchSleepData(days: Int = 7) async {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let calendar = Calendar.current
        let now = Date()

        // Night-based date range: 6 PM (days ago) to 5 PM (today)
        let startDate = calendar.date(byAdding: .day, value: -(days), to: now)!
        let startOfNight = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startDate)!
        let endOfNight = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfNight, end: endOfNight, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
            guard let samples = samples as? [HKCategorySample] else {
                // Handle no data available
                return
            }

            // Process the sleep samples
            let filteredSamples = samples.filter { sample in
                let source = sample.sourceRevision.source.bundleIdentifier
                return source.starts(with: "com.apple.health")
            }
            
            // Group samples by day for multiple days
            var sleepDataByDate: [Date: TimeInterval] = [:]
            
            for sample in filteredSamples {
                let value = sample.value
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                
                // Only count actual sleep (not awake)
                if value != HKCategoryValueSleepAnalysis.awake.rawValue {
                    let dayStart = calendar.startOfDay(for: sample.startDate)
                    sleepDataByDate[dayStart, default: 0] += duration
                }
            }
            
            // Convert to HealthKitSleep array sorted by date (newest first)
            let sleepArray = sleepDataByDate.sorted { $0.key > $1.key }.map { date, duration in
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!
                return HealthKitSleep(duration: duration, startDate: date, endDate: dayEnd, sleepScore: 0)
            }

            Task { @MainActor in
                self.sleepData = sleepArray
                print("sleepdata",self.sleepData)
            }
        }

        healthStore.execute(query)
    }
    
    /*
     // Fetch today's activity rings (default)
     await hkManager.fetchActivityRingStatus()

     let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
     await hkManager.fetchActivityRingStatus(for: yesterday)

     // Fetch activity rings for a specific date
     let specificDate = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 10))!
     await hkManager.fetchActivityRingStatus(for: specificDate)
     */
    func fetchActivityRingStatus(for date: Date? = nil) async {
        let calendar = Calendar.current
        let targetDate = date ?? Date()
        let startOfDay = calendar.startOfDay(for: targetDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay)
        
        // Fetch goals from HealthKit
        let moveGoal = await fetchActivityGoal(for: activeEnergyType) ?? 520
        let exerciseGoal = await fetchActivityGoal(for: exerciseTimeType) ?? 30
        let standGoal = Int(await fetchActivityGoal(for: standTimeType) ?? 12)
        
        var ringStatus = ActivityRingStatus(
            moveRingValue: 0,
            moveRingGoal: moveGoal,
            exerciseRingValue: 0,
            exerciseRingGoal: exerciseGoal,
            standRingValue: 0,
            standRingGoal: standGoal
        )
        
        // Use a dispatch group to wait for all queries
        let group = DispatchGroup()
        
        // Fetch Move ring (Active Energy)
        group.enter()
        let moveQuery = HKStatisticsQuery(
            quantityType: activeEnergyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let result = result {
                ringStatus.moveRingValue = result.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
            group.leave()
        }
        
        // Fetch Exercise ring (Apple Exercise Time)
        group.enter()
        let exerciseQuery = HKStatisticsQuery(
            quantityType: exerciseTimeType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            if let result = result {
                ringStatus.exerciseRingValue = result.sumQuantity()?.doubleValue(for: .minute()) ?? 0
            }
            group.leave()
        }
        
        // Fetch Stand ring (Stand Time)
        group.enter()
        let standQuery = HKSampleQuery(
            sampleType: standTimeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            if let samples = samples as? [HKQuantitySample] {
                // Count unique hours where user stood
                var uniqueHours = Set<Int>()
                
                for sample in samples {
                    let hour = calendar.component(.hour, from: sample.startDate)
                    uniqueHours.insert(hour)
                }
                
                ringStatus.standRingValue = uniqueHours.count
            }
            group.leave()
        }
        
        // Execute all queries
        healthStore.execute(moveQuery)
        healthStore.execute(exerciseQuery)
        healthStore.execute(standQuery)
        
        // Wait for all queries to complete then update UI
        group.notify(queue: .main) { [weak self] in
            self?.activityRingStatus = ringStatus
        }
    }
    
    nonisolated private func fetchActivityGoal(for quantityType: HKQuantityType) async -> Double? {
        return await withCheckedContinuation { continuation in
            // Use HKActivitySummaryQuery to get goals from today
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            
            // Create date components for today with calendar
            var todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
            todayComponents.calendar = calendar
            
            let summaryQuery = HKActivitySummaryQuery(predicate: HKQuery.predicateForActivitySummary(with: todayComponents)) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Return appropriate goal based on quantity type
                if quantityType.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue {
                    let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                    continuation.resume(returning: goal)
                } else if quantityType.identifier == HKQuantityTypeIdentifier.appleExerciseTime.rawValue {
                    let goal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
                    continuation.resume(returning: goal)
                } else if quantityType.identifier == HKQuantityTypeIdentifier.appleStandTime.rawValue {
                    let goal = summary.standHoursGoal?.doubleValue(for: .count()) ?? 12
                    continuation.resume(returning: goal)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            self.healthStore.execute(summaryQuery)
        }
    }
}
