//
//  SingleExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SingleExerciseView: View {
    @Bindable var exercise: Exercise
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("Exercise: \(exercise.name)")
                Text("Alises: \(exercise.aliases?.joined(separator: ", ") ?? "")")
                Text("Muscle Groups: \(exercise.muscle_groups?.joined(separator: ", ") ?? "")")
                Text("Date: \(exercise.timestamp.formatted(date: .numeric, time: .omitted))")
            }
            .padding()
            Spacer()
        }
        .navigationTitle(exercise.name)
    }
}

struct SingleExerciseLabelView: View {
    @Bindable var exercise: Exercise
    
    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(exercise.name)
                HStack {
                    Text(exercise.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
