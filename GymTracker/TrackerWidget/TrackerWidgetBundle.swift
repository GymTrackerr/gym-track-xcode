//
//  TrackerWidgetBundle.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import WidgetKit
import SwiftUI

@main
struct TrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeScreenWidget()
        ProgrammeWidget()
        NutritionWidget()
        CreateLogWidget()
        TrackerWidgetControl()

        TrackerWidgetLiveActivity()
    }
}
