//
//  ExerciseBootstrapCoordinator.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import Foundation

enum BootstrapRunStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
}

struct BootstrapRunState: Codable {
    let accountUserId: String
    let deviceId: String
    var status: BootstrapRunStatus
    var lastAttemptAt: Date
    var completedAt: Date?
    var uploadedRecordCount: Int
    var lastErrorMessage: String?
}

final class ExerciseBootstrapStateStore {
    static let shared = ExerciseBootstrapStateStore()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "gymtracker.bootstrap.exercise."
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    func load(accountUserId: String, deviceId: String) -> BootstrapRunState? {
        guard let data = defaults.data(forKey: key(accountUserId: accountUserId, deviceId: deviceId)) else {
            return nil
        }
        return try? JSONDecoder().decode(BootstrapRunState.self, from: data)
    }

    func markInProgress(accountUserId: String, deviceId: String, at date: Date = Date()) {
        var state = load(accountUserId: accountUserId, deviceId: deviceId)
            ?? BootstrapRunState(
                accountUserId: accountUserId,
                deviceId: deviceId,
                status: .notStarted,
                lastAttemptAt: date,
                completedAt: nil,
                uploadedRecordCount: 0,
                lastErrorMessage: nil
            )

        state.status = .inProgress
        state.lastAttemptAt = date
        state.lastErrorMessage = nil
        save(state)
    }

    func markCompleted(
        accountUserId: String,
        deviceId: String,
        uploadedRecordCount: Int,
        at date: Date = Date()
    ) {
        let state = BootstrapRunState(
            accountUserId: accountUserId,
            deviceId: deviceId,
            status: .completed,
            lastAttemptAt: date,
            completedAt: date,
            uploadedRecordCount: uploadedRecordCount,
            lastErrorMessage: nil
        )
        save(state)
    }

    func markFailed(
        accountUserId: String,
        deviceId: String,
        message: String,
        at date: Date = Date()
    ) {
        var state = load(accountUserId: accountUserId, deviceId: deviceId)
            ?? BootstrapRunState(
                accountUserId: accountUserId,
                deviceId: deviceId,
                status: .notStarted,
                lastAttemptAt: date,
                completedAt: nil,
                uploadedRecordCount: 0,
                lastErrorMessage: nil
            )

        state.status = .failed
        state.lastAttemptAt = date
        state.lastErrorMessage = message
        save(state)
    }

    private func save(_ state: BootstrapRunState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(accountUserId: state.accountUserId, deviceId: state.deviceId))
    }

    private func key(accountUserId: String, deviceId: String) -> String {
        let normalizedAccountUserId = accountUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(keyPrefix)\(normalizedAccountUserId).\(normalizedDeviceId)"
    }
}

protocol AccountBootstrapCoordinating: AnyObject {
    func triggerBootstrapIfNeeded(localUserId: UUID, accountUserId: String, syncEnabled: Bool)
}

protocol RemoteExerciseBootstrapUploading {
    func upsertForBootstrap(_ exercise: Exercise) async throws
}

final class ExerciseBootstrapCoordinator: AccountBootstrapCoordinating {
    private let localRepository: ExerciseRepositoryProtocol
    private let remoteUploader: RemoteExerciseBootstrapUploading
    private let stateStore: ExerciseBootstrapStateStore

    private let inFlightQueue = DispatchQueue(label: "gymtracker.bootstrap.exercise.inflight")
    private var inFlightRunKeys = Set<String>()

    init(
        localRepository: ExerciseRepositoryProtocol,
        remoteUploader: RemoteExerciseBootstrapUploading,
        stateStore: ExerciseBootstrapStateStore = .shared
    ) {
        self.localRepository = localRepository
        self.remoteUploader = remoteUploader
        self.stateStore = stateStore
    }

    convenience init(
        localRepository: ExerciseRepositoryProtocol,
        remoteRepository: RemoteExerciseRepository,
        stateStore: ExerciseBootstrapStateStore = .shared
    ) {
        self.init(
            localRepository: localRepository,
            remoteUploader: remoteRepository,
            stateStore: stateStore
        )
    }

    func triggerBootstrapIfNeeded(localUserId: UUID, accountUserId: String, syncEnabled: Bool) {
        guard syncEnabled else { return }

        let normalizedAccountUserId = accountUserId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAccountUserId.isEmpty == false else { return }

        let deviceId = LocalDeviceIdentityStore.shared.deviceId(for: localUserId)
        let runKey = "\(normalizedAccountUserId):\(deviceId.lowercased())"

        if stateStore.load(accountUserId: normalizedAccountUserId, deviceId: deviceId)?.status == .completed {
            return
        }

        guard reserveRun(for: runKey) else { return }

        stateStore.markInProgress(accountUserId: normalizedAccountUserId, deviceId: deviceId)

        Task.detached(priority: .utility) { [weak self] in
            await self?.runBootstrap(
                localUserId: localUserId,
                accountUserId: normalizedAccountUserId,
                deviceId: deviceId,
                runKey: runKey
            )
        }
    }

    private func runBootstrap(
        localUserId: UUID,
        accountUserId: String,
        deviceId: String,
        runKey: String
    ) async {
        defer { releaseRun(for: runKey) }

        do {
            let localRecords = try await MainActor.run {
                try fetchLocalBootstrapExercises(for: localUserId)
            }
            for exercise in localRecords {
                try await remoteUploader.upsertForBootstrap(exercise)
            }

            await MainActor.run {
                stateStore.markCompleted(
                    accountUserId: accountUserId,
                    deviceId: deviceId,
                    uploadedRecordCount: localRecords.count
                )
            }
        } catch {
            await MainActor.run {
                stateStore.markFailed(
                    accountUserId: accountUserId,
                    deviceId: deviceId,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func fetchLocalBootstrapExercises(for localUserId: UUID) throws -> [Exercise] {
        let active = try localRepository.fetchActiveExercises(for: localUserId)
        let archived = try localRepository.fetchArchivedExercises(for: localUserId)

        var dedupedById = [String: Exercise]()
        for exercise in (active + archived) where exercise.isUserCreated {
            dedupedById[exercise.id.uuidString.lowercased()] = exercise
        }

        return dedupedById.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    private func reserveRun(for runKey: String) -> Bool {
        inFlightQueue.sync {
            if inFlightRunKeys.contains(runKey) {
                return false
            }
            inFlightRunKeys.insert(runKey)
            return true
        }
    }

    private func releaseRun(for runKey: String) {
        inFlightQueue.sync {
            inFlightRunKeys.remove(runKey)
        }
    }
}
