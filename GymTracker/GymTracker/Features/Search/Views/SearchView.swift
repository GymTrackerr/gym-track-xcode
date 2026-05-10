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
            List {
                if results.isEmpty {
                    EmptyStateView(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        message: "No exercises or routines match your search."
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                } else {
                    ForEach(results) { result in
                        switch result {
                        case .exercise(let e):
                            SingleExerciseLabelView(exercise: e)
                                .cardListRowContentPadding()
                        case .routine(let s):
                            SingleDayLabelView(routine: s)
                                .cardListRowContentPadding()
                        }
                    }
                }
            }
            .onAppear() {
                performSearch()
                query = ""
            }
            .onChange(of: query) {
                performSearch()
            }
            .cardListScreen()
            .navigationTitle("Search")
        }
        .appBackground()
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
