//
//  ServiceBase.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftData
import Combine
import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

class ServiceBase {
    @Published var currentUser: User?

    var modelContext: ModelContext
    var cancellables = Set<AnyCancellable>()

    var apiHelper: API_Helper
    var exerciseApi: ExerciseApi

    init(context: ModelContext) {
        self.modelContext = context
        
        let apiHelper = API_Helper()
        self.apiHelper = apiHelper
        self.exerciseApi = ExerciseApi(apiHelper: apiHelper)
        
        loadFeature()
    }
    
    // guard currentUser != nil else { return }
    func loadFeature() { }
    
    func bind(to userService: UserService) {
        userService.$currentUser
            .sink { [weak self] user in
                self?.currentUser = user
                self?.loadFeature()
            }
            .store(in: &cancellables)
    }
    
    func hapticPress() {
//        if (self.currentUser.haptic?.isEnabled == true) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
//        }
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

