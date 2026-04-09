//
//  ListResponse.swift
//  GymTracker
//
//  Created by Copilot on 2026-04-09.
//

import Foundation

struct ListResponse<T: Decodable>: Decodable {
    let items: [T]
}