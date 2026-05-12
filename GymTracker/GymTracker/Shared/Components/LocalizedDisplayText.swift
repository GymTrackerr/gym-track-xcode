//
//  LocalizedDisplayText.swift
//  GymTracker
//
//  Created by Codex on 2026-05-12.
//

import SwiftUI

struct LocalizedDisplayText: Identifiable {
    enum Storage {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let id: String
    let storage: Storage

    init(resource: LocalizedStringResource, id: String = UUID().uuidString) {
        self.id = id
        storage = .localized(resource)
    }

    static func localized(
        _ value: String.LocalizationValue,
        table: String? = nil,
        id: String = UUID().uuidString
    ) -> LocalizedDisplayText {
        if let table {
            return LocalizedDisplayText(resource: LocalizedStringResource(value, table: table), id: id)
        }

        return LocalizedDisplayText(resource: LocalizedStringResource(value), id: id)
    }

    static func verbatim(_ value: String, id: String = UUID().uuidString) -> LocalizedDisplayText {
        LocalizedDisplayText(id: id, storage: .verbatim(value))
    }

    private init(id: String, storage: Storage) {
        self.id = id
        self.storage = storage
    }
}

struct LocalizedDisplayTextView: View {
    let text: LocalizedDisplayText

    init(_ text: LocalizedDisplayText) {
        self.text = text
    }

    @ViewBuilder
    var body: some View {
        switch text.storage {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }
}
