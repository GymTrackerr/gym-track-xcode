//
//  HealthWorkoutView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-10.
//

import SwiftUI
import HealthKit

struct HealthWorkoutView: View {
    @EnvironmentObject var hkManager: HealthKitManager
    @State private var selectedFilter: WorkoutFilter = .all
    @State private var isLoading = false

    enum WorkoutFilter {
        case all
        case cardio
        case strength
        case flexibility
        
        var title: String {
            switch self {
            case .all: return "All Workouts"
            case .cardio: return "Cardio"
            case .strength: return "Strength"
            case .flexibility: return "Flexibility"
            }
        }
    }
    
    var filteredWorkouts: [HealthKitWorkout] {
        switch selectedFilter {
        case .all:
            return hkManager.workouts
        case .cardio:
            return hkManager.workouts.filter { isCardioWorkout($0.type) }
        case .strength:
            return hkManager.workouts.filter { isStrengthWorkout($0.type) }
        case .flexibility:
            return hkManager.workouts.filter { isFlexibilityWorkout($0.type) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fitness App Workouts")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(filteredWorkouts.count) workouts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach([WorkoutFilter.all, .cardio, .strength, .flexibility], id: \.self) { filter in
                        
                        FilterPill(
                            title: filter.title,
                            isSelected: selectedFilter == filter
                        )
                        .onTapGesture {
                            selectedFilter = filter
                        }
                    }
                    Spacer()
                    NavigationLink {
                        WorkoutRoutesMapView()
                    } label: {
                        Label("Map View", systemImage: "map")
                    }
//                    NavigationLink {
//                        WorkoutRoutesMapView
//                    }, label: {
//                        Text("")
//                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)

            // Workouts List
            if isLoading && filteredWorkouts.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading workouts...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else if filteredWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Workouts")
                        .font(.headline)
                    
                    Text("No \(selectedFilter.title.lowercased()) found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredWorkouts) { workout in
                        WorkoutRow(workout: workout)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            isLoading = true
            await hkManager.fetchWorkoutsIfNeeded(days: 90)
            if hkManager.workouts.isEmpty {
                await hkManager.fetchWorkouts(days: 90)
            }
            isLoading = false
        }
    }

    // Helper Methods
    func isCardioWorkout(_ type: HKWorkoutActivityType) -> Bool {
        [.running, .walking, .cycling, .swimming, .rowing, .elliptical, .stairClimbing].contains(type)
    }

    func isStrengthWorkout(_ type: HKWorkoutActivityType) -> Bool {
        [.functionalStrengthTraining, .traditionalStrengthTraining, .crossTraining].contains(type)
    }

    func isFlexibilityWorkout(_ type: HKWorkoutActivityType) -> Bool {
        [.yoga, .pilates].contains(type)
    }
}

// Workout Row Component
struct WorkoutRow: View {
    let workout: HealthKitWorkout
    
    var body: some View {
        CardRowContainer {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.typeDisplayName)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(formatDate(workout.startDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Duration
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack {
                            Text(formatDuration(workout.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Stats Row
                HStack(spacing: 16) {
                    // Calories
                    StatCard(
                        icon: "flame.fill",
                        value: workout.calories > 0 ? "\(Int(workout.calories))" : "—",
                        label: "kcal",
                        color: .orange
                    )

                    // Distance (if available)
                    if let distance = workout.distance, distance > 0 {
                        StatCard(
                            icon: "location.fill",
                            value: formatDistance(distance),
                            label: "km",
                            color: .blue
                        )
                    }

                    Spacer()
                }
            }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func formatDistance(_ meters: Double) -> String {
        let kilometers = meters / 1000
        return String(format: "%.1f", kilometers)
    }
}

// Stat Card Component
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
//        .padding(8)
    }
}

// Filter Equatable Conformance
extension HealthWorkoutView.WorkoutFilter: Equatable {
    static func == (lhs: HealthWorkoutView.WorkoutFilter, rhs: HealthWorkoutView.WorkoutFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all), (.cardio, .cardio), (.strength, .strength), (.flexibility, .flexibility):
            return true
        default:
            return false
        }
    }
}

extension HealthWorkoutView.WorkoutFilter: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:
            hasher.combine(0)
        case .cardio:
            hasher.combine(1)
        case .strength:
            hasher.combine(2)
        case .flexibility:
            hasher.combine(3)
        }
    }
}
