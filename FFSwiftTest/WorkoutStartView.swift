import SwiftUI
import SwiftData

struct WorkoutStartView: View {

    private enum Phase {
        case ready
        case stabilizing      // watch connected — waiting for it to be still
        case countdown        // phone-only fallback when no watch paired
        case active
        case stopping         // receiving CSV from watch
    }

    private let workoutName = "External Rotation"
    private let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

    @Environment(PhoneConnectivityManager.self) private var connectivity
    @Environment(\.modelContext) private var modelContext

    @State private var phase: Phase = .ready
    @State private var countdown = 5
    @State private var countdownTask: Task<Void, Never>?
    @State private var showWorkoutSummary = false

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

                // Main status circle
                ZStack {
                    Circle()
                        .fill(primaryOrange.opacity(0.1))
                        .frame(width: 220, height: 220)
                    Circle()
                        .stroke(primaryOrange.opacity(0.2), lineWidth: 14)
                        .frame(width: 220, height: 220)

                    circleContent
                }

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Watch stability indicator (only while stabilizing)
                if phase == .stabilizing {
                    watchStabilityBanner
                }

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
                .disabled(phase == .countdown || phase == .stabilizing || phase == .stopping)
                .opacity((phase == .countdown || phase == .stabilizing || phase == .stopping) ? 0.6 : 1)
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
        // Transition from stabilizing → active when watch confirms it started
        .onChange(of: connectivity.watchWorkoutState) { _, state in
            if state == .active && phase == .stabilizing {
                phase = .active
            }
        }
        // When the watch CSV arrives, import it and show summary
        .onChange(of: connectivity.latestReceivedCSVURL) { _, url in
            guard let url, phase == .stopping else { return }
            importCSVAndShowSummary(url)
        }
    }

    // MARK: - Circle content per phase

    @ViewBuilder
    private var circleContent: some View {
        switch phase {
        case .ready:
            VStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 52))
                    .foregroundColor(primaryOrange)
                Text("Ready")
                    .font(.title2.weight(.semibold))
            }

        case .stabilizing:
            VStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.yellow)
                    .symbolEffect(.pulse)
                Text("Hold Still")
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

        case .stopping:
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("Saving…")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Watch stability banner

    private var watchStabilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .foregroundColor(.yellow)
            Text("Hold your watch still to begin tracking")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }

    // MARK: - Computed properties

    private var statusText: String {
        switch phase {
        case .ready:
            return connectivity.isWatchReachable
                ? "Watch connected. Tap Start and hold your watch steady."
                : "Press start when you're ready to begin your \(workoutName) workout."
        case .stabilizing:
            return "Tracking will begin as soon as your watch detects a stable position."
        case .countdown:
            return "Get into position. Your workout begins when the countdown reaches zero."
        case .active:
            return "Your workout is in progress. Stop when you're ready to review your results."
        case .stopping:
            return "Receiving motion data from your watch…"
        }
    }

    private var buttonTitle: String {
        switch phase {
        case .ready:      return "Start Workout"
        case .stabilizing: return "Waiting for Watch…"
        case .countdown:  return "Starting…"
        case .active:     return "Stop Workout"
        case .stopping:   return "Saving…"
        }
    }

    private var buttonColor: Color {
        phase == .active ? .red : primaryOrange
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        switch phase {
        case .ready:
            if connectivity.isWatchReachable {
                connectivity.sendStartWorkout(name: workoutName)
                phase = .stabilizing
            } else {
                startCountdown()
            }
        case .active:
            if connectivity.isWatchReachable {
                connectivity.sendStopWorkout()
                phase = .stopping
                // Give watch time to send the file; fall through to summary if no file arrives
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    if phase == .stopping {
                        await MainActor.run {
                            phase = .ready
                            showWorkoutSummary = true
                        }
                    }
                }
            } else {
                showWorkoutSummary = true
                phase = .ready
            }
        default:
            break
        }
    }

    private func startCountdown() {
        phase = .countdown
        countdown = 5
        countdownTask?.cancel()
        countdownTask = Task {
            for value in stride(from: 5, through: 1, by: -1) {
                await MainActor.run { countdown = value }
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch { return }
            }
            await MainActor.run { phase = .active }
        }
    }

    private func importCSVAndShowSummary(_ url: URL) {
        do {
            _ = try WorkoutSessionImporter.importCSV(
                at: url,
                exerciseName: workoutName,
                in: modelContext
            )
        } catch {
            print("[WorkoutStartView] CSV import error: \(error)")
        }
        phase = .ready
        showWorkoutSummary = true
    }
}

#Preview {
    WorkoutStartView()
        .modelContainer(for: [WorkoutSession.self, WorkoutRepetition.self, WorkoutMotionSample.self],
                        inMemory: true)
}
