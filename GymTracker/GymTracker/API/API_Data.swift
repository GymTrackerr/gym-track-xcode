//
//  API_Data.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

class API_Data {
    private let prodMode:Bool = false;
    
    func getURL() -> String {
        if (prodMode != true) {
            return "http://localhost:3002/v1"
        }
        else {
            return "https://interact-api.novapro.net/v1"
        }
    }
}

