//
//  SplitDayService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class SplitDayService : ServiceBase, ObservableObject {
    @Published var splitDays: [SplitDay] = []

    @Published var editingContent: String = ""
    @Published var editingSplit: Bool = false
    
    override func loadFeature() {
        self.loadSplitDays()
    }
    
    func loadSplitDays() {
        let descriptor = FetchDescriptor<SplitDay>(sortBy: [SortDescriptor(\.order)])

        do {
            splitDays = try modelContext.fetch(descriptor)
        } catch {
            splitDays = []
        }
    }
    
    func search(query: String) -> [SplitDay] {
        print("searching split days \(query)")

        guard !query.isEmpty else { return splitDays }
        return splitDays.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func addSplitDay() {
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        withAnimation {
            let newItem = SplitDay(order: splitDays.count, name: trimmedName)
            modelContext.insert(newItem)
            do {
                try modelContext.save()
                editingSplit = false
                editingContent = ""
                loadSplitDays()
            } catch {
                print("Failed to save new split day: \(error)")
            }
        }
    }
    
    func removeSplitDay(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(splitDays[index])
            }
            try? modelContext.save()
            loadSplitDays()
            renumberSplitDays()
        }
    }
    
    func clearSplitDays() {
        let descriptor = FetchDescriptor<SplitDay>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items { modelContext.delete(item) }
            try? modelContext.save()
        }
        loadSplitDays()
    }

    func printSplitDays() {
        let descriptor = FetchDescriptor<SplitDay>()
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
            splitDays.move(fromOffsets: source, toOffset: destination)
            renumberSplitDays()
        }
    }
    
    func renumberSplitDays() {
        for (i, day) in splitDays.enumerated() {
            day.order = i
        }
        try? modelContext.save()
    }
}
