import SwiftUI

struct WorkoutStartView: View {
    private enum Phase {
        case ready
        case countdown
        case active
    }

    private let workoutName = "External Rotation"
    private let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

    @State private var phase: Phase = .ready
    @State private var countdown = 5
    @State private var showWorkoutSummary = false
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Text("Current Workout")
                        .font(.headline)
                        .foregroundColor(.gray)

                    Text(workoutName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    Circle()
                        .fill(primaryOrange.opacity(0.1))
                        .frame(width: 220, height: 220)

                    Circle()
                        .stroke(primaryOrange.opacity(0.2), lineWidth: 14)
                        .frame(width: 220, height: 220)

                    switch phase {
                    case .ready:
                        VStack(spacing: 10) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 52))
                                .foregroundColor(primaryOrange)
                            Text("Ready")
                                .font(.title2.weight(.semibold))
                        }
                    case .countdown:
                        VStack(spacing: 10) {
                            Text("\(countdown)")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .foregroundColor(primaryOrange)
                            Text("Starting Soon")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    case .active:
                        VStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 48))
                                .foregroundColor(.red)
                            Text("Workout Live")
                                .font(.title2.weight(.semibold))
                        }
                    }
                }

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button(action: handlePrimaryAction) {
                    Text(buttonTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(buttonColor)
                        .cornerRadius(16)
                }
                .disabled(phase == .countdown)
                .opacity(phase == .countdown ? 0.8 : 1)
                .padding(.horizontal)
            }
            .padding()
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Start Workout")
        }
        .sheet(isPresented: $showWorkoutSummary) {
            WorkoutView()
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    private var statusText: String {
        switch phase {
        case .ready:
            return "Press start when you're ready to begin your External Rotation workout."
        case .countdown:
            return "Get into position. Your workout begins when the countdown reaches zero."
        case .active:
            return "Your workout is in progress. Stop when you're ready to review your results."
        }
    }

    private var buttonTitle: String {
        switch phase {
        case .ready:
            return "Start Workout"
        case .countdown:
            return "Starting..."
        case .active:
            return "Stop Workout"
        }
    }

    private var buttonColor: Color {
        phase == .active ? .red : primaryOrange
    }

    private func handlePrimaryAction() {
        switch phase {
        case .ready:
            startCountdown()
        case .countdown:
            break
        case .active:
            showWorkoutSummary = true
            phase = .ready
            countdown = 5
        }
    }

    private func startCountdown() {
        phase = .countdown
        countdown = 5
        countdownTask?.cancel()
        countdownTask = Task {
            for value in stride(from: 5, through: 1, by: -1) {
                await MainActor.run {
                    countdown = value
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }

            await MainActor.run {
                phase = .active
            }
        }
    }
}

#Preview {
    WorkoutStartView()
}
