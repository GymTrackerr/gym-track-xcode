//
//  AppAppearancePreference.swift
//  GymTracker
//
//  Created by Codex on 2026-05-09.
//

import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .system:
            return LocalizedStringResource(
                "settings.appearance.system",
                defaultValue: "System",
                table: "Settings",
                comment: "Appearance picker option that follows the system appearance"
            )
        case .light:
            return LocalizedStringResource(
                "settings.appearance.light",
                defaultValue: "Light",
                table: "Settings",
                comment: "Appearance picker option for light mode"
            )
        case .dark:
            return LocalizedStringResource(
                "settings.appearance.dark",
                defaultValue: "Dark",
                table: "Settings",
                comment: "Appearance picker option for dark mode"
            )
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
