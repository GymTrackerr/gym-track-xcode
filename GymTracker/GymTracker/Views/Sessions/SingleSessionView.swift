//
//  SingleDayView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//
/*
import SwiftUI

struct SingleWorkoutView: View {
    @Bindable var workout: Workout
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("SplitDay: \(splitDay.name)")
                Text("Order: \(splitDay.order)")
                Text("Date: \(splitDay.timestamp.formatted(date: .numeric, time: .omitted))")
            }
            .padding()
            Spacer()
        }
        .navigationTitle(splitDay.name)
    }
}

struct SingleWorkoutLabelView: View {
    @Bindable var workout: Workout

    var body : some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(splitDay.name)
                HStack {
                    Text("Day #\(splitDay.order+1)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                    Text(splitDay.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

*/
