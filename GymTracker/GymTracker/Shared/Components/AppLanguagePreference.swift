//
//  AppLanguagePreference.swift
//  GymTracker
//
//  Created by OpenAI Codex on 2026-05-12.
//

import Foundation

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case enGB = "en-GB"
    case enUS = "en-US"
    case fr
    case es

    var id: String { rawValue }

    var effectiveLocale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .system:
            return LocalizedStringResource(
                "settings.language.systemDefault",
                defaultValue: "System Default",
                table: "Settings",
                comment: "Language picker option that follows the device or app system language"
            )
        case .enGB:
            return LocalizedStringResource(
                "settings.language.enGB",
                defaultValue: "English (UK)",
                table: "Settings",
                comment: "Language picker option for British English"
            )
        case .enUS:
            return LocalizedStringResource(
                "settings.language.enUS",
                defaultValue: "English (US)",
                table: "Settings",
                comment: "Language picker option for American English"
            )
        case .fr:
            return LocalizedStringResource(
                "settings.language.fr",
                defaultValue: "Français",
                table: "Settings",
                comment: "Language picker option for French"
            )
        case .es:
            return LocalizedStringResource(
                "settings.language.es",
                defaultValue: "Español",
                table: "Settings",
                comment: "Language picker option for Spanish"
            )
        }
    }
}
