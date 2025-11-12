//
//  ExerciseService.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

class ExerciseService : ServiceBase, ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var editingContent: String = ""
    @Published var editingExercise: Bool = false
    @Published var selectedExerciseType: ExerciseType = ExerciseType.weight
    
    // for api data

    @Published var apiExercises: [ExerciseDTO] = []

    override func loadFeature() {
        self.loadExercises()
        
        Task {
           await self.loadApiExercises()
       }
    }
    
    func loadExercises() {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])

        do {
            exercises = try modelContext.fetch(descriptor)
            // verify exercises
            for exercise in exercises {
                print("\(exercise.name) \(exercise.type)")
            }
        } catch {
            exercises = []
        }
    }
    
    func loadApiExercises() async {
        do {
            let data = try await exerciseApi.getExercises()

            // Preload all current IDs once
            let existing = Set(exercises.compactMap { $0.npId?.lowercased() })
            var inserted = 0

            // Insert only missing exercises
            for exercise in data where !existing.contains(exercise.id.lowercased()) {
                modelContext.insert(Exercise(from: exercise))
                inserted += 1
            }

            // Save once at the end
            if inserted > 0 {
                try modelContext.save()
                await MainActor.run { self.loadExercises() }
            }

            
            // TODO, only cache on launch
            
            Task {
            // Prefetch media in background
//            Task.detached(priority: .background) { [weak self] in
//                guard let self else { return }

                for exercise in self.exercises {
                    if (exercise.images == nil) {continue}
                    if (exercise.cachedMedia == true) {continue}
                    
                    async let thumb = self.cacheThumbnail(for: exercise)
                    async let gif = self.cacheGIF(for: exercise)
                    _ = await (thumb, gif)
                    
                    exercise.cachedMedia = true
                    try? self.modelContext.save()
                }
                
                print("📦 Cached all non-user exercise thumbnails and GIFs.")
            }
            print("Loaded \(data.count) exercises from API (\(inserted) new)")
        } catch {
            print("Error loading API exercises: \(error)")
        }
    }
    
    func search(query: String) -> [Exercise] {
        print("searching exercise \(query)")
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func addExercise() -> Exercise? {
        print("Adding")
        let trimmedName = editingContent.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        
        let newItem = Exercise(name: trimmedName, type: selectedExerciseType)
        var failed = false
        
        withAnimation {
            modelContext.insert(newItem)
            
            do {
                try modelContext.save()
                // Clear and dismiss sheet after successful save
                editingExercise = false
                editingContent = ""
                loadExercises()
                selectedExerciseType = .weight

            } catch {
                print("Failed to save new split day: \(error)")
                failed=true
            }
        }
        
        if (failed==true) {
            return nil
        }
        return newItem;
    }
    
    func removeExercise(offsets: IndexSet) {
        print("not activating")
        withAnimation {
            for index in offsets {
                // TODO: crashed here, EXC_BAD_ACESS
                modelContext.delete(exercises[index])
            }

            do {
                try modelContext.save()
                loadExercises()
                
            } catch {
                print("Failed to save after deletion: \(error)")
            }
        }
    }
}


extension ExerciseService {
    func thumbnailURL(for exercise: Exercise) -> URL? {
        guard
            let first = exercise.images?.first,
            let baseURL = URL(string: apiHelper.apiData.getURL().replacingOccurrences(of: "/v1", with: "")),
            let url = URL(string: first, relativeTo: baseURL)
        else {
            print("Missing or invalid thumbnail URL for \(exercise.name)")
            return nil
        }

        print("Thumbnail for \(exercise.name) → \(url.absoluteString)")
        return url
    }

    func gifURL(for exercise: Exercise) -> URL? {
        guard
            let last = exercise.images?.last,
            let baseURL = URL(string: apiHelper.apiData.getURL().replacingOccurrences(of: "/v1", with: "")),
            let url = URL(string: last, relativeTo: baseURL)
        else {
            print("⚠️ Missing or invalid GIF URL for \(exercise.name)")
            return nil
        }

        print("GIF for \(exercise.name) → \(url.absoluteString)")
        return url
    }

    /// Caches the thumbnail (.first image)
    func cacheThumbnail(for exercise: Exercise) async -> URL? {
        guard let url = self.thumbnailURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url)
        } catch {
            print("⚠️ Failed to cache thumbnail for \(exercise.name): \(error)")
            return nil
        }
    }

    /// Caches the GIF (.last image)
    func cacheGIF(for exercise: Exercise) async -> URL? {
        guard let url = self.gifURL(for: exercise) else { return nil }
        do {
            return try await MediaCache.shared.fetch(url)
        } catch {
            print("⚠️ Failed to cache GIF for \(exercise.name): \(error)")
            return nil
        }
    }

    /// Checks if either thumbnail or GIF is already cached
    func hasCachedMedia(for exercise: Exercise) async -> (thumbnail: Bool, gif: Bool) {
        var result = (thumbnail: false, gif: false)
        
        if let thumbURL = self.thumbnailURL(for: exercise),
           await MediaCache.shared.cachedFile(for: thumbURL) != nil {
            result.thumbnail = true
        }
        
        if let gifURL = self.gifURL(for: exercise),
           await MediaCache.shared.cachedFile(for: gifURL) != nil {
            result.gif = true
        }
        
        return result
    }
}

