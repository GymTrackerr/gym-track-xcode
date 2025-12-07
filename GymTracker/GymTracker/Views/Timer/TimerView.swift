//
//  TimerView.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2025-12-06.
//

import SwiftUI

//struct DefaultTimerView: View {
//    @EnvironmentObject var userService: UserService
//    
//    var body: some View {
//
//
//    }
//}
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

                // Show progress only if countdown
                if let _ = timerService.remainingTime {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 18, lineCap: .round))
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
//                    let length = userService.currentUser?.defaultTimer ?? 90
                    timerService.start()
                }
                .buttonStyle(MainTimerButton(color: Color(.green)))

            } else if timerService.timer?.isPaused == true {
                Button("Resume") { timerService.resume() }
                    .buttonStyle(MainTimerButton(color: Color(.green)))

            } else {
                Button("Pause") { timerService.pause() }
                    .buttonStyle(MainTimerButton(color: Color(.green)))
            }

            
            // MARK: Cancel
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
    }
    
    // MARK: Circle progress
    private var progress: CGFloat {
        if timerService.timer == nil {
            let total = CGFloat(userService.currentUser?.defaultTimer ?? 1)
            return CGFloat(timerService.pendingLength) / total
        }

        guard let remaining = timerService.remainingTime else { return 1 }
        let total = CGFloat(timerService.timer?.timerLength ?? 1)
        return max(CGFloat(remaining) / total, 0)
    }
}


struct MainTimerButton: ButtonStyle {
    var color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(16)
            .padding(.horizontal)
    }
}

struct SecondaryTimerButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.35).opacity(configuration.isPressed ? 0.6 : 1))
            .cornerRadius(14)
    }
}
