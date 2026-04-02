import SwiftUI
import WatchKit

struct WorkoutControlView: View {

    private enum WorkoutPhase {
        case idle
        case stabilizing      // collecting baseline, waiting for watch to be still
        case active           // workout in progress
        case stopping         // writing + transferring CSV
    }

    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(WatchMotionManager.self) private var motion

    @State private var phase: WorkoutPhase = .idle
    @State private var workoutName = "External Rotation"
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer? = nil
    @State private var stabilityProgress = 0.0
    @State private var stabilityTimer: Timer? = nil

    private let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .idle:      idleView
            case .stabilizing: stabilizingView
            case .active:    activeView
            case .stopping:  stoppingView
            }
        }
        .onChange(of: connectivity.pendingCommand) { _, command in
            guard let command else { return }
            connectivity.pendingCommand = nil
            handlePhoneCommand(command)
        }
        .onChange(of: motion.isStable) { _, stable in
            // When real stability detection fires and we're in the stabilizing phase,
            // advance immediately — bypassing the simulated timer.
            if stable && phase == .stabilizing {
                stabilityTimer?.invalidate()
                stabilityTimer = nil
                beginActiveWorkout()
            }
        }
    }

    // MARK: - Phase views

    private var idleView: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36))
                .foregroundColor(primaryOrange)

            Text("FormFit")
                .font(.headline)
                .foregroundColor(.white)

            Button {
                beginStabilityPhase()
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(primaryOrange)
        }
        .padding()
    }

    private var stabilizingView: some View {
        VStack(spacing: 12) {
            ProgressView(value: stabilityProgress)
                .tint(primaryOrange)
                .padding(.horizontal)

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28))
                .foregroundColor(.yellow)

            Text("Hold still")
                .font(.headline)
                .foregroundColor(.white)

            Text("Detecting stable position…")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var activeView: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28))
                .foregroundColor(.red)

            Text(formattedTime(elapsedSeconds))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("\(motion.sampleCount) samples")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button {
                stopWorkout()
            } label: {
                Text("Stop")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }

    private var stoppingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(primaryOrange)
            Text("Saving…")
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Phase logic

    private func handlePhoneCommand(_ command: WatchPendingCommand) {
        switch command {
        case .startWorkout(let name):
            workoutName = name
            beginStabilityPhase()
        case .stopWorkout:
            stopWorkout()
        }
    }

    /// Start motion collection and a simulated stability countdown.
    /// Real stability detection runs in parallel via WatchMotionManager.isStable.
    private func beginStabilityPhase() {
        guard phase == .idle else { return }
        phase = .stabilizing
        stabilityProgress = 0.0
        motion.startCollecting()
        connectivity.sendStabilityReady()

        // Simulated 2.5-second stability window.
        // If real stability fires first (via onChange above), this timer is cancelled.
        var elapsed = 0.0
        let duration = 2.5
        stabilityTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            elapsed += 0.1
            self.stabilityProgress = min(elapsed / duration, 1.0)
            if elapsed >= duration {
                t.invalidate()
                self.stabilityTimer = nil
                self.beginActiveWorkout()
            }
        }
    }

    private func beginActiveWorkout() {
        guard phase == .stabilizing else { return }
        WKInterfaceDevice.current().play(.start)  // haptic buzz
        connectivity.sendWorkoutStarted()
        phase = .active
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.elapsedSeconds += 1
        }
    }

    private func stopWorkout() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        stabilityTimer?.invalidate(); stabilityTimer = nil
        phase = .stopping

        // Stop motion collection and transfer the CSV file to the phone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let csvURL = self.motion.stopCollecting() {
                self.connectivity.transferCSV(at: csvURL)
            }
            self.connectivity.sendWorkoutStopped()
            WKInterfaceDevice.current().play(.stop)
            self.phase = .idle
        }
    }

    private func formattedTime(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}
