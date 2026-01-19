//
//  DummyDataManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-01-19.
//
//import SwiftUI
//import SwiftData
//import Combine
//
//struct DummyDataManager {
//
//    static func populate(
//        context: ModelContext,
//        exercises: [Exercise]
//    ) {
//        let calendar = Calendar.current
//        let now = Date()
//
//        for week in 0..<8 {
//            let date = calendar.date(byAdding: .day, value: -(week * 3), to: now)!
//
//            let session = Session(
//                id: UUID(),
//                date: date,
//                title: "Demo Workout",
//                exercises: makeExercises(from: exercises)
//            )
//
//            context.insert(session)
//        }
//
//        try? context.save()
//    }
//}
