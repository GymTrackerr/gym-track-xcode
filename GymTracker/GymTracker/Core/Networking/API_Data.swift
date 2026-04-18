//
//  API_Data.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

enum APIBaseURLKind {
    case backend
    case exerciseDB
}

final class API_Data {
    enum Environment {
        case development
        case production
    }

    private enum OverrideKey {
        static let backendBaseURL = "gymtracker.api.base-url.override"
        static let exerciseDBBaseURL = "gymtracker.api.exercisedb-base-url.override"
    }

    private let environment: Environment
    private let defaults: UserDefaults

    init(
        environment: Environment = .production,
        defaults: UserDefaults = .standard
    ) {
        self.environment = environment
        self.defaults = defaults
    }

    private var defaultHostURLString: String {
        switch environment {
        case .development:
            return "http://127.0.0.1:5002"
        case .production:
            return "https://api.trackerr.ca"
        }
    }

    private func overrideBaseURLString(for kind: APIBaseURLKind) -> String? {
        let key: String
        switch kind {
        case .backend:
            key = OverrideKey.backendBaseURL
        case .exerciseDB:
            key = OverrideKey.exerciseDBBaseURL
        }

        guard let rawValue = defaults.string(forKey: key) else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func baseURLString(for kind: APIBaseURLKind = .backend) -> String {
        overrideBaseURLString(for: kind) ?? (defaultHostURLString + "/v1")
    }

    func hostURLString(for kind: APIBaseURLKind = .backend) -> String {
        if let overrideBaseURL = overrideBaseURLString(for: kind) {
            guard let url = URL(string: overrideBaseURL) else {
                return defaultHostURLString
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = ""
            components?.query = nil
            components?.fragment = nil
            return components?.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? defaultHostURLString
        }

        return defaultHostURLString
    }

    static func backendBaseURLOverride() -> String? {
        UserDefaults.standard.string(forKey: OverrideKey.backendBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func exerciseDBBaseURLOverride() -> String? {
        UserDefaults.standard.string(forKey: OverrideKey.exerciseDBBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func setBackendBaseURLOverride(_ value: String?) {
        setOverride(value, forKey: OverrideKey.backendBaseURL)
    }

    static func setExerciseDBBaseURLOverride(_ value: String?) {
        setOverride(value, forKey: OverrideKey.exerciseDBBaseURL)
    }

    private static func setOverride(_ value: String?, forKey key: String) {
        let defaults = UserDefaults.standard
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }

    func getURL() -> String {
        baseURLString(for: .backend)
    }

    func getHostURL() -> String {
        hostURLString(for: .backend)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
