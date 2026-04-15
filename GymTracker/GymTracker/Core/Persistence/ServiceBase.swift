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

    init(context: ModelContext) {
        self.modelContext = context
    }
    
    // guard currentUser != nil else { return }
    func loadFeature() { }

    // Optional per-service startup sync hook.
    func sync() { }
    
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
