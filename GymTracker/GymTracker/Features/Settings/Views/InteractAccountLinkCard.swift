//
//  InteractAccountLinkCard.swift
//  GymTracker
//
//  Created by Codex on 2026-04-16.
//

import SwiftUI

struct InteractAccountLinkCard: View {
    @EnvironmentObject private var backendAuthService: BackendAuthService
    @EnvironmentObject private var exerciseService: ExerciseService
    @EnvironmentObject private var userService: UserService

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var statusMessage: String?

    private var isLinked: Bool {
        guard let accessToken = backendAuthService.sessionSnapshot?.accessToken else {
            return false
        }
        return accessToken.isEmpty == false
    }

    private var linkButtonDisabled: Bool {
        isSubmitting ||
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interact Account", tableName: "Settings")
                .font(.headline)

            if userService.currentUser?.isDemo == true {
                Text("Account linking is disabled while using Demo mode.", tableName: "Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if isLinked {
                    linkedStateView
                } else {
                    unlinkedStateView
                }
            }

            if let statusMessage, statusMessage.isEmpty == false {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var linkedStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let username = backendAuthService.currentBackendUser?.username, username.isEmpty == false {
                Text("Linked as @\(username)", tableName: "Settings")
                    .font(.subheadline)
            } else if let accountUserId = backendAuthService.sessionSnapshot?.accountUserId {
                Text("Linked account: \(accountUserId)", tableName: "Settings")
                    .font(.subheadline)
            } else {
                Text("Account linked", tableName: "Settings")
                    .font(.subheadline)
            }

            if let bootstrapSummary = bootstrapSummaryText {
                Text(bootstrapSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    refreshSession()
                } label: {
                    Text("Refresh Session", tableName: "Settings")
                }
                .buttonStyle(.bordered)
                .disabled(isSubmitting)

                Button {
                    logout()
                } label: {
                    Text("Unlink", tableName: "Settings")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
    }

    private var unlinkedStateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link an Interact account to enable optional cloud sync. You can keep using GymTracker without linking.", tableName: "Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Interact username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            SecureField("Interact password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button {
                login()
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("Link Interact Account", tableName: "Settings")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(linkButtonDisabled)
        }
    }

    private var bootstrapSummaryText: String? {
        guard
            let localUserId = userService.currentUser?.id,
            let accountUserId = backendAuthService.sessionSnapshot?.accountUserId
        else {
            return nil
        }

        let deviceId = LocalDeviceIdentityStore.shared.deviceId(for: localUserId)
        guard let state = ExerciseBootstrapStateStore.shared.load(accountUserId: accountUserId, deviceId: deviceId) else {
            return nil
        }

        switch state.status {
        case .completed:
            return "Bootstrap completed (\(state.uploadedRecordCount) user exercises uploaded)."
        case .inProgress:
            return "Bootstrap is in progress."
        case .failed:
            return "Bootstrap last attempt failed: \(state.lastErrorMessage ?? "Unknown error")."
        case .notStarted:
            return "Bootstrap has not started yet."
        }
    }

    private func login() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else { return }

        isSubmitting = true
        statusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isSubmitting = false
                }
            }

            do {
                _ = try await backendAuthService.loginInteract(username: trimmedUsername, password: password)
                _ = try? await backendAuthService.refreshCurrentSession()
                _ = try? await backendAuthService.fetchCurrentUser()
                exerciseService.sync()

                await MainActor.run {
                    password = ""
                    statusMessage = "Account linked successfully."
                }
            } catch {
                await MainActor.run {
                    statusMessage = errorMessage(from: error)
                }
            }
        }
    }

    private func refreshSession() {
        isSubmitting = true
        statusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isSubmitting = false
                }
            }

            do {
                _ = try await backendAuthService.refreshCurrentSession()
                _ = try? await backendAuthService.fetchCurrentUser()
                exerciseService.sync()
                await MainActor.run {
                    statusMessage = "Session refreshed."
                }
            } catch {
                await MainActor.run {
                    statusMessage = errorMessage(from: error)
                }
            }
        }
    }

    private func logout() {
        isSubmitting = true
        statusMessage = nil

        Task {
            defer {
                Task { @MainActor in
                    isSubmitting = false
                }
            }

            do {
                try await backendAuthService.logoutCurrentSession()
                await MainActor.run {
                    statusMessage = "Account unlinked."
                }
            } catch {
                await MainActor.run {
                    statusMessage = errorMessage(from: error)
                }
            }
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let apiError = error as? APIHelperError {
            switch apiError {
            case .httpError(let statusCode, _, let message, let details):
                return message ?? details ?? "Request failed with status \(statusCode)."
            case .missingAccessToken:
                return "Missing access token. Please link your account again."
            case .invalidResponse:
                return "Invalid response from the backend."
            }
        }

        return error.localizedDescription
    }
}
