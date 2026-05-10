//
//  TimerFeedbackSettingsView.swift
//  GymTracker
//
//  Created by Codex on 2026-03-09.
//

import SwiftUI

struct TimerFeedbackSettingsView: View {
    @EnvironmentObject var userService: UserService

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderView(title: "Notifications")
                    ConnectedCardSection {
                        ConnectedCardRow {
                            Toggle("Enable Timer Notifications", isOn: Binding(
                                get: { userService.currentUser?.timerNotificationsEnabled ?? true },
                                set: { userService.setTimerNotificationsEnabled($0) }
                            ))
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            Toggle("Timer Finished", isOn: Binding(
                                get: { userService.currentUser?.timerFinishedNotificationEnabled ?? true },
                                set: { userService.setTimerFinishedNotificationEnabled($0) }
                            ))
                            .disabled(!(userService.currentUser?.timerNotificationsEnabled ?? true))
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            Toggle("Away Too Long Reminder", isOn: Binding(
                                get: { userService.currentUser?.awayTooLongEnabled ?? false },
                                set: { userService.setAwayTooLongEnabled($0) }
                            ))
                            .disabled(!(userService.currentUser?.timerNotificationsEnabled ?? true))
                        }

                        if (userService.currentUser?.awayTooLongEnabled ?? false) && (userService.currentUser?.timerNotificationsEnabled ?? true) {
                            ConnectedCardDivider()

                            ConnectedCardRow {
                                Stepper(
                                    value: Binding(
                                        get: { max(userService.currentUser?.awayTooLongMinutes ?? 10, 1) },
                                        set: { userService.setAwayTooLongMinutes($0) }
                                    ),
                                    in: 1...60
                                ) {
                                    Text("Away Reminder Delay: \(max(userService.currentUser?.awayTooLongMinutes ?? 10, 1)) min")
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeaderView(title: "Haptics")
                    ConnectedCardSection {
                        ConnectedCardRow {
                            Toggle("Enable Countdown Haptics", isOn: Binding(
                                get: { userService.currentUser?.countdownHapticsEnabled ?? true },
                                set: { userService.setCountdownHapticsEnabled($0) }
                            ))
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            Toggle("Haptic at 30s", isOn: Binding(
                                get: { userService.currentUser?.hapticAt30 ?? true },
                                set: { userService.setHapticAt30($0) }
                            ))
                            .disabled(!(userService.currentUser?.countdownHapticsEnabled ?? true))
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            Toggle("Haptic at 15s", isOn: Binding(
                                get: { userService.currentUser?.hapticAt15 ?? true },
                                set: { userService.setHapticAt15($0) }
                            ))
                            .disabled(!(userService.currentUser?.countdownHapticsEnabled ?? true))
                        }

                        ConnectedCardDivider()

                        ConnectedCardRow {
                            Toggle("Haptic at 5s", isOn: Binding(
                                get: { userService.currentUser?.hapticAt5 ?? true },
                                set: { userService.setHapticAt5($0) }
                            ))
                            .disabled(!(userService.currentUser?.countdownHapticsEnabled ?? true))
                        }
                    }
                }
            }
            .screenContentPadding()
        }
        .appBackground()
        .navigationTitle("Timer Feedback")
    }
}
