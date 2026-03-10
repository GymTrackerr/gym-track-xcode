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
    var baseAPIurl:String = "https://interact-api.novapro.net/v1"

    init(apiHelper: API_Helper) {
        self.apiHelper = apiHelper
        self.baseAPIurl = apiData.getURL()
    }
}
