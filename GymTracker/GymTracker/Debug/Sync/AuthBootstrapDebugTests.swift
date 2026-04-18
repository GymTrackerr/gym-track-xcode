#if DEBUG
import Foundation

final class AuthBootstrapDebug {
    private static var hasRun = false

    static func runSamples() {
        guard !hasRun else { return }
        hasRun = true

        print("=== AuthBootstrapDebug start ===")
        let results = [
            test1DeviceIdIsStablePerUser(),
            test2SyncEligibilityPersistsPerLocalUser(),
            test3BootstrapSkipsWhenSyncIsDisabled(),
            test4BootstrapUploadsOnlyUserCreatedExercisesAndRunsOnce(),
            test5BootstrapCanRetryAfterFailure()
        ]
        let passCount = results.filter { $0 }.count
        print("=== AuthBootstrapDebug done: \(passCount)/\(results.count) passed ===")
    }

    @discardableResult
    private static func test1DeviceIdIsStablePerUser() -> Bool {
        let localUserA = UUID()
        let localUserB = UUID()

        LocalDeviceIdentityStore.shared.clearDeviceId(for: localUserA)
        LocalDeviceIdentityStore.shared.clearDeviceId(for: localUserB)

        defer {
            LocalDeviceIdentityStore.shared.clearDeviceId(for: localUserA)
            LocalDeviceIdentityStore.shared.clearDeviceId(for: localUserB)
        }

        let first = LocalDeviceIdentityStore.shared.deviceId(for: localUserA)
        let second = LocalDeviceIdentityStore.shared.deviceId(for: localUserA)
        let third = LocalDeviceIdentityStore.shared.deviceId(for: localUserB)

        let pass = check("auth-bootstrap-test1", first.isEmpty == false, "Expected non-empty device id")
            && check("auth-bootstrap-test1", first == second, "Expected stable device id for same local user")
            && check("auth-bootstrap-test1", first != third, "Expected distinct device ids across local users")

        print("[auth-bootstrap-test1] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test2SyncEligibilityPersistsPerLocalUser() -> Bool {
        let store = SyncEligibilityStateStore(
            keyPrefix: "gymtracker.test.sync-eligibility.\(UUID().uuidString.lowercased())."
        )
        let localUserA = UUID()
        let localUserB = UUID()

        let snapshotA = PersistedSyncEligibilitySnapshot(
            backendEnabled: true,
            networkAvailable: true,
            authAvailable: false,
            hasActiveLocalUser: true,
            updatedAt: Date()
        )
        let snapshotB = PersistedSyncEligibilitySnapshot(
            backendEnabled: false,
            networkAvailable: false,
            authAvailable: true,
            hasActiveLocalUser: true,
            updatedAt: Date()
        )

        store.save(snapshotA, for: localUserA)
        store.save(snapshotB, for: localUserB)

        let loadedA = store.load(for: localUserA)
        let loadedB = store.load(for: localUserB)

        var pass = true
        pass = pass && check("auth-bootstrap-test2", loadedA?.backendEnabled == true, "Expected user A backendEnabled=true")
        pass = pass && check("auth-bootstrap-test2", loadedA?.authAvailable == false, "Expected user A authAvailable=false")
        pass = pass && check("auth-bootstrap-test2", loadedB?.backendEnabled == false, "Expected user B backendEnabled=false")
        pass = pass && check("auth-bootstrap-test2", loadedB?.authAvailable == true, "Expected user B authAvailable=true")

        store.clear(for: localUserA)
        pass = pass && check("auth-bootstrap-test2", store.load(for: localUserA) == nil, "Expected clear to remove user A snapshot")
        pass = pass && check("auth-bootstrap-test2", store.load(for: localUserB) != nil, "Expected clear(user A) to keep user B snapshot")

        print("[auth-bootstrap-test2] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test3BootstrapSkipsWhenSyncIsDisabled() -> Bool {
        let localUserId = UUID()
        let accountUserId = "acct-\(UUID().uuidString.lowercased())"
        let stateStore = ExerciseBootstrapStateStore(
            keyPrefix: "gymtracker.test.bootstrap.\(UUID().uuidString.lowercased())."
        )

        let localRecord = Exercise(name: "Local Exercise", type: .weight, user_id: localUserId, isUserCreated: true)
        let localRepo = StubLocalExerciseRepository(active: [localRecord], archived: [])
        let remoteUploader = RecordingRemoteUploader()
        let coordinator = ExerciseBootstrapCoordinator(
            localRepository: localRepo,
            remoteUploader: remoteUploader,
            stateStore: stateStore
        )

        coordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: false
        )

        Thread.sleep(forTimeInterval: 0.15)
        let deviceId = LocalDeviceIdentityStore.shared.deviceId(for: localUserId)
        let state = stateStore.load(accountUserId: accountUserId, deviceId: deviceId)

        let pass = check("auth-bootstrap-test3", remoteUploader.uploadCount == 0, "Expected no upload when sync is disabled")
            && check("auth-bootstrap-test3", state == nil, "Expected no bootstrap state when sync is disabled")

        print("[auth-bootstrap-test3] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test4BootstrapUploadsOnlyUserCreatedExercisesAndRunsOnce() -> Bool {
        let localUserId = UUID()
        let accountUserId = "acct-\(UUID().uuidString.lowercased())"
        let stateStore = ExerciseBootstrapStateStore(
            keyPrefix: "gymtracker.test.bootstrap.\(UUID().uuidString.lowercased())."
        )
        let remoteUploader = RecordingRemoteUploader()

        let userExercise1 = Exercise(name: "Local Pushup", type: .weight, user_id: localUserId, isUserCreated: true)
        userExercise1.updatedAt = Date().addingTimeInterval(-100)

        let userExercise2 = Exercise(name: "Local Squat", type: .weight, user_id: localUserId, isUserCreated: true)
        userExercise2.updatedAt = Date().addingTimeInterval(-50)
        userExercise2.isArchived = true
        userExercise2.soft_deleted = true

        let catalogExercise = Exercise(name: "Catalog Press", type: .weight, user_id: localUserId, isUserCreated: false)
        catalogExercise.updatedAt = Date().addingTimeInterval(-25)

        let localRepo = StubLocalExerciseRepository(
            active: [userExercise1, catalogExercise],
            archived: [userExercise2]
        )
        let coordinator = ExerciseBootstrapCoordinator(
            localRepository: localRepo,
            remoteUploader: remoteUploader,
            stateStore: stateStore
        )

        coordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: true
        )

        let completed = waitForBootstrapState(
            status: .completed,
            store: stateStore,
            accountUserId: accountUserId,
            localUserId: localUserId
        )
        let uploadedIds = Set(remoteUploader.uploadedExerciseIds)

        var pass = true
        pass = pass && check("auth-bootstrap-test4", completed?.uploadedRecordCount == 2, "Expected completed state with 2 uploaded records")
        pass = pass && check("auth-bootstrap-test4", remoteUploader.uploadCount == 2, "Expected only user-created exercises to upload")
        pass = pass && check("auth-bootstrap-test4", uploadedIds.contains(userExercise1.id), "Expected active user-created exercise upload")
        pass = pass && check("auth-bootstrap-test4", uploadedIds.contains(userExercise2.id), "Expected archived user-created exercise upload")
        pass = pass && check("auth-bootstrap-test4", uploadedIds.contains(catalogExercise.id) == false, "Expected catalog exercise to be excluded")

        coordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: true
        )
        Thread.sleep(forTimeInterval: 0.15)
        pass = pass && check("auth-bootstrap-test4", remoteUploader.uploadCount == 2, "Expected one-time bootstrap to avoid re-upload after completion")

        print("[auth-bootstrap-test4] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    @discardableResult
    private static func test5BootstrapCanRetryAfterFailure() -> Bool {
        let localUserId = UUID()
        let accountUserId = "acct-\(UUID().uuidString.lowercased())"
        let stateStore = ExerciseBootstrapStateStore(
            keyPrefix: "gymtracker.test.bootstrap.\(UUID().uuidString.lowercased())."
        )

        let localRecord = Exercise(name: "Retry Exercise", type: .weight, user_id: localUserId, isUserCreated: true)
        let localRepo = StubLocalExerciseRepository(active: [localRecord], archived: [])
        let remoteUploader = RecordingRemoteUploader()
        remoteUploader.remainingFailures = 1

        let coordinator = ExerciseBootstrapCoordinator(
            localRepository: localRepo,
            remoteUploader: remoteUploader,
            stateStore: stateStore
        )

        coordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: true
        )

        let failed = waitForBootstrapState(
            status: .failed,
            store: stateStore,
            accountUserId: accountUserId,
            localUserId: localUserId
        )

        coordinator.triggerBootstrapIfNeeded(
            localUserId: localUserId,
            accountUserId: accountUserId,
            syncEnabled: true
        )

        let completed = waitForBootstrapState(
            status: .completed,
            store: stateStore,
            accountUserId: accountUserId,
            localUserId: localUserId
        )

        let pass = check("auth-bootstrap-test5", failed?.status == .failed, "Expected first run to fail")
            && check("auth-bootstrap-test5", completed?.status == .completed, "Expected second run to complete")
            && check("auth-bootstrap-test5", remoteUploader.uploadCount == 1, "Expected a single successful upload across retries")

        print("[auth-bootstrap-test5] \(pass ? "PASS" : "FAIL")")
        return pass
    }

    private static func waitForBootstrapState(
        status: BootstrapRunStatus,
        store: ExerciseBootstrapStateStore,
        accountUserId: String,
        localUserId: UUID,
        timeoutSeconds: TimeInterval = 2.0
    ) -> BootstrapRunState? {
        let deviceId = LocalDeviceIdentityStore.shared.deviceId(for: localUserId)
        let timeoutAt = Date().addingTimeInterval(timeoutSeconds)

        while Date() < timeoutAt {
            if let state = store.load(accountUserId: accountUserId, deviceId: deviceId), state.status == status {
                return state
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        return store.load(accountUserId: accountUserId, deviceId: deviceId)
    }

    @discardableResult
    private static func check(_ test: String, _ condition: Bool, _ message: String) -> Bool {
        if !condition {
            print("[\(test)] FAIL: \(message)")
        }
        return condition
    }
}

private enum AuthBootstrapDebugError: Error {
    case injectedFailure
}

private final class StubLocalExerciseRepository: ExerciseRepositoryProtocol {
    private let active: [Exercise]
    private let archived: [Exercise]

    init(active: [Exercise], archived: [Exercise]) {
        self.active = active
        self.archived = archived
    }

    func fetchActiveExercises(for userId: UUID) throws -> [Exercise] {
        active.filter { $0.user_id == userId }
    }

    func fetchArchivedExercises(for userId: UUID) throws -> [Exercise] {
        archived.filter { $0.user_id == userId }
    }

    func applyCatalogExercises(_ data: [ExerciseDTO], for userId: UUID, allowInsert: Bool) throws -> (inserted: Int, updated: Int, removed: Int) {
        (0, 0, 0)
    }

    func applyCatalogOverlays(_ data: [GymTrackerCatalogOverlayDTO], for userId: UUID) throws -> Int {
        0
    }

    func applyRemoteUserExercises(_ data: [GymTrackerExerciseDTO], for userId: UUID) throws -> (inserted: Int, updated: Int, removed: Int) {
        (0, 0, 0)
    }

    func createExercise(name: String, type: ExerciseType, userId: UUID) throws -> Exercise {
        Exercise(name: name, type: type, user_id: userId)
    }

    func setAliases(_ aliases: [String], for exercise: Exercise) throws {}
    func delete(_ exercise: Exercise) throws {}
    func restore(_ exercise: Exercise) throws {}
    func reinsertOrRestore(_ exercise: Exercise) throws {}
    func hideCatalogExercises(for userId: UUID) throws -> CatalogDisableResult {
        CatalogDisableResult(hiddenNpIds: [], hiddenCount: 0, deletedCount: 0)
    }
    func restoreCatalogExercises(withNpIds npIds: [String], for userId: UUID) throws -> Int { 0 }
    func willArchiveOnDelete(_ exercise: Exercise) -> Bool { false }
    func mergeExercisesWithSameNpId(for userId: UUID) throws -> ExerciseNpIdMergeReport { .init(groupsMerged: 0, duplicatesRemoved: 0) }
    func saveChanges() throws {}
}

private final class RecordingRemoteUploader: RemoteExerciseBootstrapUploading {
    private let lockQueue = DispatchQueue(label: "gymtracker.debug.bootstrap.remote-uploader")
    private var uploadedIdsStorage = [UUID]()

    var remainingFailures: Int = 0

    var uploadCount: Int {
        lockQueue.sync { uploadedIdsStorage.count }
    }

    var uploadedExerciseIds: [UUID] {
        lockQueue.sync { uploadedIdsStorage }
    }

    func upsertForBootstrap(_ exercise: Exercise) async throws {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw AuthBootstrapDebugError.injectedFailure
        }

        lockQueue.sync {
            uploadedIdsStorage.append(exercise.id)
        }
    }
}
#endif
