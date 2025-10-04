//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI

struct SingleSessionView: View {
    @Bindable var session: Session
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                if let splitDay = session.splitDay {
                    Text("SplitDay: \(splitDay.name)")
                }
                if let notes = session.notes {
                    Text("Notes: \(notes)")
                }
                Text("Date: \(session.timestamp.formatted(date: .numeric, time: .standard))")
            }
            .padding()
//            Spacer()
            if let splitDay = session.splitDay {
                List {
                    // TODO: TO BE EDITED, USE NEW MODEL FOR EXERCISES BASED ON SESSION
                    ForEach(splitDay.exerciseSplits.sorted { $0.order < $1.order }, id: \.id) { exerciseSplit in
                        NavigationLink {
                            SingleExerciseView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                        } label: {
                            SingleExerciseLabelView(exercise: exerciseSplit.exercise, orderInSplit: exerciseSplit.order)
                                .id(exerciseSplit.order)
                        }
                    }
                    // .onDelete(perform: removeExercise)
                    // .onMove(perform: moveExercise)
                }
            }

        }
        .navigationTitle("Session \(session.timestamp.formatted(date: .numeric, time: .omitted))")
    }
}

struct SingleSessionLabelView: View {
    @Bindable var session: Session

    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                if let splitDay = session.splitDay {
                    Text("SplitDay: \(splitDay.name)")
                }
                HStack {
                    if let splitDay = session.splitDay {
                        Text("Day #\(splitDay.order+1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(session.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

