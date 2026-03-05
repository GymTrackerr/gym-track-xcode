//
//  API_Data.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

class API_Data {
    private let prodMode:Bool = true;
    
    func getURL() -> String {
        if (prodMode != true) {
            return "http://192.168.3.21:5002/v1"
        }
        else {
            return "https://api.trackerr.ca/v1"
        }
    }
}

