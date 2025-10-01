//
//  TrackerManager.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-10-01.
//

import SwiftUI
import SwiftData
import Combine
internal import CoreData

//@Observable
class TrackerManager : ObservableObject {
    @ObservationIgnored
    private var modelContext: ModelContext
    
    @ObservedObject var SDS: SplitDayService

    init(context: ModelContext) {
        self.modelContext = context
        
        self.SDS = SplitDayService(context: context)
   }
}
