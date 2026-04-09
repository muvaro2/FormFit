import SwiftUI

struct WorkoutStartView: View {
    private enum DisplayState {
        case ready
        case countdown
        case preparing
        case collecting
        case saving
        case captured
    }

    private let workoutName = "External Rotation"

    @ObservedObject private var connectivity = PhoneConnectivityManager.shared
    @State private var countdown = 5
    @State private var isCountdownActive = false
    @State private var isAwaitingResults = false
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
        if isAwaitingResults {
            return .saving
        }
        // While the watch still has a buffer to save/import, show a "saving" state
        // rather than asking the user to press a button.
        if connectivity.watchBufferCount > 0 {
            return .saving
        }
        if importMarker != nil {
            return .captured
        }
        return .ready
    }

    private var remoteControlAvailable: Bool {
        connectivity.isWatchReady && connectivity.isReachable
    }

    var body: some View {
        ZStack {
            if isAwaitingResults {
                LaunchLoadingView()
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 8) {
                            Text("Finishing workout")
                                .font(.headline)
                                .foregroundStyle(FormFitTheme.textPrimary)
                            Text("Hold on while we save the watch session and prepare your results.")
                                .font(.subheadline)
                                .foregroundStyle(FormFitTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 56)
                    }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        heroCircle
                        statusMessage
                        statusCard
                        commandSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .formFitScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Workout")
                    .font(.headline)
                    .foregroundStyle(FormFitTheme.textPrimary)
            }
        }
        .sheet(isPresented: $showWorkoutSummary) {
            WorkoutView()
        }
        .onAppear {
            importMarker = connectivity.lastImportedFilename
        }
        .onDisappear {
            countdownTask?.cancel()
            isAwaitingResults = false
        }
        .onChange(of: connectivity.lastImportedFilename) { _, newValue in
            guard let newValue, newValue != importMarker else { return }
            importMarker = newValue
            isAwaitingResults = false
            showWorkoutSummary = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            FormFitLogoMark(size: 52)
                .padding(.bottom, 4)

            Text("Current Workout")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(FormFitTheme.textSecondary)

            Text(workoutName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FormFitTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    // MARK: - Hero circle

    private var heroCircle: some View {
        ZStack {
            Circle()
                .fill(FormFitTheme.orange.opacity(0.08))
                .frame(width: 200, height: 200)

            Circle()
                .stroke(FormFitTheme.orange.opacity(0.18), lineWidth: 12)
                .frame(width: 200, height: 200)

            switch displayState {
            case .ready:
                heroContent(icon: "figure.strengthtraining.traditional", label: "Ready", tint: FormFitTheme.orange)
            case .countdown:
                VStack(spacing: 6) {
                    Text("\(countdown)")
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .foregroundStyle(FormFitTheme.orange)
                    Text("Starting...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textSecondary)
                }
            case .preparing:
                heroContent(icon: "timer", label: "Arming", tint: FormFitTheme.orange)
            case .collecting:
                heroContent(icon: "waveform.path.ecg", label: "Collecting", tint: FormFitTheme.danger)
            case .saving:
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(FormFitTheme.orange)
                        .scaleEffect(1.4)
                    Text("Scoring...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FormFitTheme.textPrimary)
                }
            case .captured:
                heroContent(icon: "checkmark.circle.fill", label: "Saved", tint: FormFitTheme.success)
            }
        }
    }

    private func heroContent(icon: String, label: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(tint)
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(FormFitTheme.textPrimary)
        }
    }

    // MARK: - Status

    private var statusMessage: some View {
        Text(statusText)
            .font(.subheadline)
            .foregroundStyle(FormFitTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusText: String {
        switch displayState {
        case .ready:
            return "Use the phone as a remote start for your Apple Watch, or start collection directly on the watch."
        case .countdown:
            return "Get into position. Collection will begin when the countdown finishes."
        case .preparing:
            return "The watch is arming and will start collecting in a moment."
        case .collecting:
            return "Motion data is recording. Stop from either device to finish the set."
        case .saving:
            return "Saving session from the watch and running form analysis..."
        case .captured:
            return "Session scored and stored. Start another set whenever you're ready."
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusStripRow(title: "Connection", value: connectivity.status)
            StatusStripRow(
                title: "Remote",
                value: remoteControlAvailable
                    ? "Watch app open and reachable"
                    : "Open FormFit on Apple Watch"
            )
            StatusStripRow(title: "Buffer", value: "\(connectivity.watchBufferCount) samples")

            if let latestFile = connectivity.lastImportedFilename {
                StatusStripRow(title: "Latest", value: latestFile)
            }
            if let message = connectivity.lastImportMessage {
                StatusStripRow(title: "Status", value: message)
            }
        }
        .formFitCard()
    }

    // MARK: - Commands

    @ViewBuilder
    private var commandSection: some View {
        switch displayState {
        case .ready, .captured:
            Button(action: startCountdown) {
                Label("Start Workout", systemImage: "play.fill")
                    .formFitPrimaryButton()
            }
            .disabled(!remoteControlAvailable)
            .opacity(remoteControlAvailable ? 1 : 0.65)

            if !remoteControlAvailable {
                Text("Remote start requires FormFit open on the watch.")
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

        case .countdown:
            Button(action: cancelCountdown) {
                Label("Cancel", systemImage: "xmark")
                    .formFitSecondaryButton(accent: FormFitTheme.danger)
            }

        case .preparing:
            Button(action: stopArming) {
                Label("Stop Arming", systemImage: "stop.fill")
                    .formFitSecondaryButton(accent: FormFitTheme.danger)
            }

        case .collecting:
            Button(action: stopWorkoutAndScore) {
                Label("Stop & Score", systemImage: "stop.fill")
                    .formFitPrimaryButton()
            }

        case .saving:
            // No interactive controls while auto-save is happening; the
            // summary sheet will open on completion.
            EmptyView()
        }
    }

    // MARK: - Actions

    private func startCountdown() {
        guard remoteControlAvailable else { return }

        importMarker = connectivity.lastImportedFilename
        countdown = 5
        isCountdownActive = true
        countdownTask?.cancel()
        countdownTask = Task {
            for value in stride(from: 5, through: 1, by: -1) {
                await MainActor.run { countdown = value }
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

    private func stopArming() {
        cancelCountdown()
        isAwaitingResults = false
        connectivity.sendCollectorCommand("stop")
    }

    private func stopWorkoutAndScore() {
        cancelCountdown()
        isAwaitingResults = true
        connectivity.sendCollectorCommand("stop")
        // PhoneConnectivityManager will detect the collecting → stopped
        // transition and automatically send the save command.
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
                .frame(width: 76, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationView {
        WorkoutStartView()
    }
}
