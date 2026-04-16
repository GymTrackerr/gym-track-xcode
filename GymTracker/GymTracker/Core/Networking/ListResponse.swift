//
//  ListResponse.swift
//  GymTracker
//
//  Created by Copilot on 2026-04-09.
//

import Foundation

struct ListResponse<T: Decodable>: Decodable {
    let items: [T]

    init(items: [T]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let envelope = try ListEnvelope<T>(from: decoder)
        self.items = envelope.items
    }
}

struct ListEnvelope<T: Decodable>: Decodable {
    let items: [T]

    private enum CodingKeys: String, CodingKey {
        case items
        case list
    }

    init(items: [T]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try container.decodeIfPresent([T].self, forKey: .items) {
            self.items = items
            return
        }
        if let list = try container.decodeIfPresent([T].self, forKey: .list) {
            self.items = list
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.items,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected list envelope to contain either 'items' or 'list'."
            )
        )
    }
}

enum ArrayOrEnvelopeDecoder {
    static func decode<T: Decodable>(
        _ type: [T].Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [T] {
        if let array = try? decoder.decode([T].self, from: data) {
            return array
        }

        let envelope = try decoder.decode(ListEnvelope<T>.self, from: data)
        return envelope.items
    }
}
