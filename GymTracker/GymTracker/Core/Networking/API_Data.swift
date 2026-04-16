//
//  API_Data.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

final class API_Data {
    enum Environment {
        case development
        case production
    }

    private let environment: Environment

    init(environment: Environment = .development) {
        self.environment = environment
    }

    var hostURLString: String {
        switch environment {
        case .development:
            return "http://127.0.0.1:5002"
        case .production:
            return "https://api.trackerr.ca"
        }
    }

    var baseURLString: String {
        hostURLString + "/v1"
    }

    func getURL() -> String {
        baseURLString
    }

    func getHostURL() -> String {
        hostURLString
    }
}

