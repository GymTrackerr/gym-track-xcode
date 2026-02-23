//
//  SearchView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//
import SwiftUI

struct SearchView : View {
    @EnvironmentObject var splitDayService: RoutineService
    @EnvironmentObject var exerciseService: ExerciseService
    @FocusState private var isFocused: Bool
    @Binding var query: String
    @State var results: [SearchResult] = []

    var body: some View {
        VStack{
            List (results) { result in
                switch result {
                case .exercise(let e):
                    SingleExerciseLabelView(exercise: e)
                case .routine(let s):
                    SingleDayLabelView(routine: s)
                }
            }
            .onAppear() {
                performSearch()
                query = ""
            }
            .onChange(of: query) {
                performSearch()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Search")
        }
    }
    
    func performSearch() {
        print("searching")
        // Fetch exercises matching query
        let exercises = exerciseService.search(query: query)
        let routines = splitDayService.search(query: query)
        
        // Map to unified type
        results = exercises.map { SearchResult.exercise($0) } +
                  routines.map { SearchResult.routine($0) }
    }
}

enum SearchResult: Identifiable {
    case exercise(Exercise)
    case routine(Routine)
    
    var id: UUID {
        switch self {
            case .exercise(let e): return e.id
            case .routine(let s): return s.id
        }
    }
    
    var title: String {
        switch self {
            case .exercise(let e): return e.name
            case .routine(let s): return s.name
        }
    }
}
