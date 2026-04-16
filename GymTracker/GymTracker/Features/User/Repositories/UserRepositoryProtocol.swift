//
//  UserRepositoryProtocol.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

protocol UserRepositoryProtocol {
    func fetchAccounts() throws -> [User]
    func createUser(name: String, isDemo: Bool) throws -> User
    func delete(_ user: User) throws
    func saveChanges(for user: User) throws
}
