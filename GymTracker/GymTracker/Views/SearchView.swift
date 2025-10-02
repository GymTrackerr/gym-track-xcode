//
//  SearchView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//
import SwiftUI

struct SearchView : View {
    @EnvironmentObject var splitDayService: SplitDayService
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
                case .splitDay(let s):
                    SingleDayLabelView(splitDay: s)
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
            .navigationTitle("Search")
        }
    }
    
    func performSearch() {
        print("searching")
        // Fetch exercises matching query
        let exercises = exerciseService.search(query: query)
        let splitDays = splitDayService.search(query: query)
        
        // Map to unified type
        results = exercises.map { SearchResult.exercise($0) } +
                  splitDays.map { SearchResult.splitDay($0) }
    }
}
