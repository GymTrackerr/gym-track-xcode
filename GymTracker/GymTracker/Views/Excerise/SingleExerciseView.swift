//
//  SingleExerciseView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SingleExerciseView: View {
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                if (orderInSplit != nil) {
                    Text("Order in Split: \(orderInSplit ?? 0)")
                }
                Text("Exercise: \(exercise.name)")
                Text("Alises: \(exercise.aliases?.joined(separator: ", ") ?? "")")
                Text("Muscle Groups: \(exercise.muscle_groups?.joined(separator: ", ") ?? "")")
                Text("Date: \(exercise.timestamp.formatted(date: .numeric, time: .omitted))")
                Text("Exercise Type: \(exercise.exerciseType.name)")
            }
            .padding()
            Spacer()
        }
        .navigationTitle(exercise.name)
    }
}

struct SingleExerciseLabelView: View {
    @Bindable var exercise: Exercise
    @State var orderInSplit: Int? = nil

    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(exercise.name)
                HStack {
                    if (orderInSplit != nil) {
                        Text("Order \(orderInSplit ?? 0)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    Text(exercise.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
