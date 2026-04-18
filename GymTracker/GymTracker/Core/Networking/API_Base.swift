//
//  API_Base.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation
import Combine

class API_Base {
    @Published var apiHelper: API_Helper
    
    var apiData = API_Data()
    var baseAPIurl: String {
        apiData.getURL()
    }

    init(apiHelper: API_Helper) {
        self.apiHelper = apiHelper
    }
}
