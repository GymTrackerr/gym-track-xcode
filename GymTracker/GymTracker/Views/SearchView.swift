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
//        NavigationStack {
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
            //            .isSea
            .navigationTitle("Search")
//            .isSearchable()
            
        }

        //        .isSearchable
        /*
         VStack {
         Text("Search")
         .searchable(text: $query)
         .toolbar {
         DefaultToolbarItem(kind: .search, placement: .bottomBar)
         
         
         }
         //            if (results.count == 0) {
         //                Text("Search for something...")
         //            } else {
         List(results) { result in
         switch result {
         case .exercise(let e):
         SingleExerciseLabelView(exercise: e)
         //                        Text("Exercise: \(e.name)")
         case .splitDay(let s):
         SingleDayView(splitDay: s)
         //                        Text("Split Day: \(s.name)")
         }
         }
         
         //            }
         
         }
         
         .navigationTitle("Search")
         //        .searchable(text: $query,/* placement: .toolbar,*/ prompt: "Search")
         //        .onChange(of: query) { _ in
         //            self.performSearch()
         //        }
         
         }
         */
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
