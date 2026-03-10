//
//  API_Helper.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-11-11.
//

import Foundation

/// Local error definitions for API_Helper
enum APIHelperError: Error {
    case invalidResponse
}

//please review interact's code to adapt with tokens
class API_Helper : Observable {
    var apiData = API_Data()

    var baseAPIurl:String = "https://interact-api.novapro.net/v1"
    var errorTime:Date = Date()
    
    init() {
        self.baseAPIurl = apiData.getURL()
        print("init API_Helper")
    }
    
    func asyncRequestData<T: Decodable> (
        urlString: String,
        errorType: String = "normal",
        httpMethod: String = "GET"
    ) async throws -> T {
        //create the new url
        let url = URL(string: urlString)
        
        //create a new urlRequest passing the url
        var request = URLRequest(url: url!)
        request.httpMethod = httpMethod
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Execute the request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIHelperError.invalidResponse
            }
            
            if 200..<300 ~= httpResponse.statusCode {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                return decodedData
            } else {
                // Log the raw error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("Error response string: \(errorString)")
                }
                
                // Decode the error response
                throw APIHelperError.invalidResponse
            }
        } catch {
            throw error
        }
    }
}
