//
//  ServiceBase.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftData
import Combine
import Foundation

class ServiceBase {
    var modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
        loadFeature()
    }
    
    func loadFeature() {
        
    }
}

extension ServiceBase {
    func fetchSplitDay(id: UUID) -> SplitDay? {
        let descriptor = FetchDescriptor<SplitDay>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }
}

enum SearchResult: Identifiable {
    case exercise(Exercise)
    case splitDay(SplitDay)
    
    var id: UUID {
        switch self {
            case .exercise(let e): return e.id
            case .splitDay(let s): return s.id
        }
    }
    
    var title: String {
        switch self {
            case .exercise(let e): return e.name
            case .splitDay(let s): return s.name
        }
    }
}

