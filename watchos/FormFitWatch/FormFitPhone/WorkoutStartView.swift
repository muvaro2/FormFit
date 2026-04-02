import SwiftUI

struct WorkoutStartView: View {
    private enum DisplayState {
        case ready
        case countdown
        case preparing
        case collecting
        case captured
    }

    private let workoutName = "External Rotation"

    @ObservedObject private var connectivity = PhoneConnectivityManager.shared
    @State private var countdown = 5
    @State private var isCountdownActive = false
    @State private var showWorkoutSummary = false
    @State private var countdownTask: Task<Void, Never>?
    @State private var importMarker: String?

    private var displayState: DisplayState {
        if isCountdownActive {
            return .countdown
        }

        if connectivity.isCollecting {
            return .collecting
        }

        if connectivity.isPreparingCollection {
            return .preparing
        }

        if connectivity.watchBufferCount > 0 {
            return .captured
        }

        return .ready
    }

    private var remoteControlAvailable: Bool {
        connectivity.isWatchReady && connectivity.isReachable
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    FormFitLogoMark(size: 64)

                    Text("Current Workout")
                        .font(.headline)
                        .foregroundStyle(FormFitTheme.textSecondary)

                    Text(workoutName)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(FormFitTheme.textPrimary)
                }

                heroCircle

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(FormFitTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    StatusStripRow(title: "Connection", value: connectivity.status)
                    StatusStripRow(title: "Remote", value: remoteControlAvailable ? "Watch open and ready for phone control" : "Open FormFit on the watch for remote control")
                    StatusStripRow(title: "Watch Buffer", value: "\(connectivity.watchBufferCount) samples")

                    if let watchMessage = connectivity.lastWatchMessage {
                        StatusStripRow(title: "Watch", value: watchMessage)
                    }

                    if let message = connectivity.lastImportMessage {
                        StatusStripRow(title: "Import", value: message)
                    }

                    if let latestFile = connectivity.lastImportedFilename {
                        StatusStripRow(title: "Latest Session", value: latestFile)
                    }
                }
                .formFitCard()
                .padding(.horizontal)

                commandSection

                Spacer()
            }
            .padding()
            .formFitScreenBackground()
            .navigationTitle("Start Workout")
        }
        .sheet(isPresented: $showWorkoutSummary) {
            WorkoutView()
        }
        .onDisappear {
            countdownTask?.cancel()
        }
        .onChange(of: connectivity.lastImportedFilename) { _, newValue in
            guard let newValue, newValue != importMarker else { return }
            showWorkoutSummary = true
            importMarker = newValue
        }
    }

    private var heroCircle: some View {
        ZStack {
            Circle()
                .fill(FormFitTheme.orange.opacity(0.1))
                .frame(width: 220, height: 220)

            Circle()
                .stroke(FormFitTheme.orange.opacity(0.18), lineWidth: 14)
                .frame(width: 220, height: 220)

            switch displayState {
            case .ready:
                VStack(spacing: 10) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 52))
                        .foregroundStyle(FormFitTheme.orange)
                    Text("Ready")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textPrimary)
                }
            case .countdown:
                VStack(spacing: 10) {
                    Text("\(countdown)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(FormFitTheme.orange)
                    Text("Starting from Phone")
                        .font(.headline)
                        .foregroundStyle(FormFitTheme.textSecondary)
                }
            case .preparing:
                VStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 48))
                        .foregroundStyle(FormFitTheme.orange)
                    Text("Arming Watch")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textPrimary)
                }
            case .collecting:
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 48))
                        .foregroundStyle(FormFitTheme.danger)
                    Text("Collecting")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textPrimary)
                }
            case .captured:
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(FormFitTheme.success)
                    Text("Ready to Save")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var commandSection: some View {
        VStack(spacing: 12) {
            switch displayState {
            case .ready:
                Button(action: startCountdown) {
                    Text("Start from Phone")
                        .formFitPrimaryButton()
                }
                .disabled(!remoteControlAvailable)
                .opacity(remoteControlAvailable ? 1 : 0.65)

                if !remoteControlAvailable {
                    Text("Remote start works once FormFit is open on the Apple Watch and the phone says the watch is reachable.")
                        .font(.caption)
                        .foregroundStyle(FormFitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

            case .countdown:
                Button(action: cancelCountdown) {
                    Text("Cancel Countdown")
                        .formFitSecondaryButton(accent: FormFitTheme.danger)
                }

            case .preparing:
                Button(action: stopCollection) {
                    Text("Stop Arming")
                        .formFitSecondaryButton(accent: FormFitTheme.danger)
                }

            case .collecting:
                Button(action: stopCollection) {
                    Text("Stop Collection")
                        .formFitSecondaryButton(accent: FormFitTheme.danger)
                }

            case .captured:
                Button(action: saveSessionToPhone) {
                    Text("Save Session to Phone")
                        .formFitPrimaryButton()
                }

                HStack(spacing: 12) {
                    Button(action: clearWatchBuffer) {
                        Text("Clear Buffer")
                            .formFitSecondaryButton(accent: FormFitTheme.orangeDeep)
                    }

                    Button(action: startCountdown) {
                        Text("Record Again")
                            .formFitSecondaryButton(accent: FormFitTheme.orange)
                    }
                    .disabled(!remoteControlAvailable)
                    .opacity(remoteControlAvailable ? 1 : 0.65)
                }
            }
        }
        .padding(.horizontal)
    }

    private var statusText: String {
        switch displayState {
        case .ready:
            return "Use the phone as a remote start button, or keep collecting directly on the watch. Raw CSVs will still be saved into Files on the phone."
        case .countdown:
            return "Get into position. When the countdown finishes, the phone tells the watch to begin collecting."
        case .preparing:
            return "The watch is arming and will start collecting in just a moment."
        case .collecting:
            return "Motion data is actively recording on the watch. You can stop from either device."
        case .captured:
            return "The watch has captured a session. Save it to transfer the CSV into Files and import it into the app."
        }
    }

    private func startCountdown() {
        guard remoteControlAvailable else { return }

        importMarker = connectivity.lastImportedFilename
        countdown = 5
        isCountdownActive = true
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
                isCountdownActive = false
                connectivity.sendCollectorCommand("start")
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        isCountdownActive = false
        countdown = 5
    }

    private func stopCollection() {
        cancelCountdown()
        connectivity.sendCollectorCommand("stop")
    }

    private func saveSessionToPhone() {
        connectivity.sendCollectorCommand("save")
    }

    private func clearWatchBuffer() {
        connectivity.sendCollectorCommand("clear")
    }
}

private struct StatusStripRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FormFitTheme.textSecondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WorkoutStartView()
}
