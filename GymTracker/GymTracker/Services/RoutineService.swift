//
//  RoutineService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class RoutineService : ServiceBase, ObservableObject {
    @Published var routines: [Routine] = []

    @Published var editingContent: String = ""
    @Published var editingSplit: Bool = false
    
    @Published var editingNotes: String = ""
    
    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)])

        do {
            routines = try modelContext.fetch(descriptor)
        } catch {
            routines = []
        }
    }
    
    func search(query: String) -> [Routine] {
        print("searching split days \(query)")

        guard !query.isEmpty else { return routines }
        return routines.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func addSplitDay() -> Routine? {
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        guard let userId = currentUser?.id else { return nil }
        
        let nextOrder = (routines.map { $0.order }.max() ?? -1) + 1
        let newItem = Routine(order: nextOrder, name: trimmedName, user_id: userId)
        var failedAdd = false
        withAnimation {
//            let newItem = Routine(order: routines.count, name: trimmedName)
            modelContext.insert(newItem)
            do {
                try modelContext.save()
                editingSplit = false
                editingContent = ""
                loadSplitDays()
            } catch {
                print("Failed to save new split day: \(error)")
                failedAdd = true
            }
        }
        
        if (failedAdd) { return nil }
        return newItem
    }
    
    func removeSplitDay(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(routines[index])
            }
            try? modelContext.save()
            loadSplitDays()
            renumberSplitDays()
        }
    }
    
    func clearSplitDays() {
        let descriptor = FetchDescriptor<Routine>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items { modelContext.delete(item) }
            try? modelContext.save()
        }
        loadSplitDays()
    }

    func printSplitDays() {
        let descriptor = FetchDescriptor<Routine>()
        do {
            let items = try modelContext.fetch(descriptor)
            print("SplitDays count: \(items.count)")
            for item in items {
                print("id: \(item.id), name: \(item.name), order: \(item.order), timestamp: \(item.timestamp)")
            }
        } catch {
            print("Failed to fetch SplitDays: \(error)")
        }
    }

    func moveSplitDay(from source: IndexSet, to destination: Int) {
        withAnimation {
            routines.move(fromOffsets: source, toOffset: destination)
            renumberSplitDays()
        }
    }
    
    func renumberSplitDays() {
        for (i, day) in routines.enumerated() {
            day.order = i
        }
        try? modelContext.save()
    }
}
