//
//  TimerView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-06.
//

import SwiftUI

struct TimerView: View {
    @EnvironmentObject var timerService: TimerService
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        VStack {
            Text("Workout Timer")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 10)
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 18)

                // Show progress for active timer or pending length
                if timerService.remainingTime != nil || timerService.pendingLength > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
                
                VStack(spacing: 4) {
                    Text(timerService.formattedTimerLength)
                        .foregroundColor(.gray)
                        .font(.system(size: 18, weight: .medium))

                    Text(timerService.timer == nil ? "Timer Length" : "Time Remaining")
                        .foregroundColor(.gray)
                        .font(.system(size: 18, weight: .medium))
                    
                    Text(timerService.isFinished ? "Done"
                         : timerService.timer == nil
                            ? timerService.formattedPending : timerService.formatted
                    )

                        .font(.system(size: 52, weight: .black, design: .rounded))
                }
            }
            .frame(width: 280, height: 280)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Remove 15s") { timerService.subtract(seconds: 15) }
                    .buttonStyle(SecondaryTimerButton())

                Button("Add 15s") { timerService.add(seconds: 15) }
                    .buttonStyle(SecondaryTimerButton())
            }
            .padding(.bottom, 10)
            
            if timerService.timer == nil {
                Button("Start") {
                    timerService.start()
                }
                .buttonStyle(MainTimerButton(color: Color(.blue)))

            } else if timerService.timer?.isPaused == true {
                Button("Resume") { timerService.resume() }
                    .buttonStyle(MainTimerButton(color: Color(.blue)))

            } else {
                Button("Pause") { timerService.pause() }
                    .buttonStyle(MainTimerButton(color: Color(.blue)))
            }

            
            // Cancel
            Group {
                if timerService.timer != nil {
                    Button("Cancel") {
                        timerService.stop(delete: true)
                    }
                    .foregroundColor(.gray)
                    .font(.system(size: 20, weight: .medium))
                } else {
                    // Invisible placeholder to keep height the same
                    Text("Cancel")
                        .font(.system(size: 20, weight: .medium))
                        .opacity(0)
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .appBackground()
    }
    
    // Circle progress
    private var progress: CGFloat {
        if timerService.timer == nil {
            // Show pending length as progress (0 to 1)
            let total = CGFloat(userService.currentUser?.defaultTimer ?? 90)
            let pending = CGFloat(timerService.pendingLength)
            return min(pending / total, 1.0)
        }

        guard let remaining = timerService.remainingTime else { return 1 }
        let total = CGFloat(timerService.timer?.timerLength ?? 1)
        return max(CGFloat(remaining) / total, 0)
    }
}


struct MainTimerButton: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(16)
            .shadow(
                color: colorScheme == .dark ? Color.clear : color.opacity(0.24),
                radius: 10,
                x: 0,
                y: 5
            )
            .padding(.horizontal)
    }
}

struct SecondaryTimerButton: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.62))
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.regularMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.10),
                radius: 10,
                x: 0,
                y: 4
            )
            .opacity(configuration.isPressed ? 0.74 : 1)
    }
}
