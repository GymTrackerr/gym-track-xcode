//
//  ContentView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
//    @Query private var items: [Item]
//    @State private var manager: TrackerManager?
//    private var manager: TrackerManager

//    init() {
////        modelContext = context
//        self.manager = TrackerManager(context: modelContext)
//    }
    @State var query: String = ""
//
    @State var localSelected:Int = 0

    var body: some View {
//            if (localSelected == 0) {
//                NavigationStack {
//                    ExercisesView()
//                }
//            } else if (localSelected == 1) {
//                NavigationStack {
//                    SplitDaysView()
//                }
//                
//            } else if (localSelected == 2) {
//                SearchView()
//                
//            } else {
//                EmptyView()
//            }
            
        TabView (selection: $localSelected) {
            Tab("Exercises", systemImage: "tray.and.arrow.down.fill", value: 0) {
                NavigationStack {
                    ExercisesView()
                }
            }
            
            
            Tab("Splits", systemImage: "tray.and.arrow.up.fill", value: 1) {
                NavigationStack {
                    SplitDaysView()
                }
            }
            
            Tab("Search", systemImage: "magnifyingglass", value: 2, role: .search) {
                NavigationStack {
                    SearchView(query: $query)
                }
            }
        }
        .searchable(text: $query)

        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollDown)
        .tabBarMinimizeBehavior(TabBarMinimizeBehavior.onScrollUp)

    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
