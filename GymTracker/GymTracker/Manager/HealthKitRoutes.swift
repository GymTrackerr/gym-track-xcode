//
//  HealthKitRoutes.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-30.
//


import CoreLocation
import MapKit
import HealthKit

struct WorkoutRouteModel: Identifiable {
    let id: UUID
    let workout: HealthKitWorkout
    let locations: [CLLocation]

    var polyline: MKPolyline {
        MKPolyline(coordinates: locations.map(\.coordinate), count: locations.count)
    }
}

extension HealthKitManager {

    /// Fetch workouts + routes, then filter locally in the UI.
    nonisolated func fetchWorkoutRoutes(
        days: Int = 30,
        workoutType: HKWorkoutActivityType? = nil
    ) async -> [WorkoutRouteModel] {

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfRange = calendar.date(byAdding: .day, value: -days, to: startOfToday) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: startOfRange, end: now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // 1) fetch workouts
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(q)
        }
        
        let filteredWorkouts = workouts.filter { workoutType == nil || $0.workoutActivityType == workoutType }

        // 2) for each workout, fetch its HKWorkoutRoute samples, then load CLLocation points
        var results: [WorkoutRouteModel] = []
        results.reserveCapacity(filteredWorkouts.count)

        for w in filteredWorkouts {
            guard let routes = await fetchRoutes(for: w), !routes.isEmpty else { continue }

            // load all route segments for this workout (sometimes there can be >1)
            var allLocations: [CLLocation] = []
            for r in routes {
                let locs = await loadLocations(for: r)
                allLocations.append(contentsOf: locs)
            }
            guard !allLocations.isEmpty else { continue }

            // build your HealthKitWorkout (same logic you already use)
            let activeEnergyType = HKQuantityType(.activeEnergyBurned)
            let calories = w.statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0
            let distance = w.totalDistance?.doubleValue(for: .meter())

            let hkWorkout = HealthKitWorkout(
                name: "Workout",
                type: w.workoutActivityType,
                duration: w.duration,
                calories: calories,
                startDate: w.startDate,
                endDate: w.endDate,
                distance: distance
            )

            results.append(
                WorkoutRouteModel(
                    id: w.uuid, // stable per workout
                    workout: hkWorkout,
                    locations: allLocations
                )
            )
        }

        return results
    }

    nonisolated private func fetchRoutes(for workout: HKWorkout) async -> [HKWorkoutRoute]? {
        await withCheckedContinuation { continuation in
            let routeType = HKSeriesType.workoutRoute()
            let pred = HKQuery.predicateForObjects(from: workout)

            let q = HKSampleQuery(sampleType: routeType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkoutRoute])
            }
            healthStore.execute(q)
        }
    }

    nonisolated private func loadLocations(for route: HKWorkoutRoute) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            var collected: [CLLocation] = []

            let q = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                if let locations { collected.append(contentsOf: locations) }
                if done { continuation.resume(returning: collected) }
            }
            healthStore.execute(q)
        }
    }
}
