//
//  WidgetUtils.swift
//  TrackerWidget
//
//  Created by Daniel Kravec on 2025-12-07.
//

import Foundation

func timeString(_ seconds: Int) -> String {
    let s = seconds % 60
    let m = (seconds / 60) % 60
    return String(format: "%02d:%02d", m, s)
}
