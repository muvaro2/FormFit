import SwiftUI
import SwiftData

struct WorkoutView: View {
    @State private var showFeedbackExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]

    private var latestSession: WorkoutSession? {
        storedSessions.max(by: { $0.workoutDate < $1.workoutDate })
    }

    private var scoreValue: String {
        guard let latestSession else { return "--" }
        return latestSession.formScore > 0 ? "\(latestSession.formScore)" : "Saved"
    }

    private var scoreLabel: String {
        guard let latestSession else { return "No Session" }
        return latestSession.formScore > 0 ? "Preview Score" : "Data Ready"
    }

    private var scoreTrim: Double {
        guard let latestSession else { return 0.12 }
        let normalized = Double(latestSession.formScore) / 100.0
        return max(0.12, min(normalized, 1.0))
    }

    private var coachMessage: String {
        guard let latestSession else {
            return "No imported workout yet. Finish a watch collection and save it to send the CSV here."
        }

        if latestSession.formScore > 0 {
            return "This preview score is derived from the imported motion data. Final Core ML coaching will replace this placeholder feedback later."
        }

        return "Workout data imported successfully. Final scoring and AI coaching will appear here once the Core ML pipeline is connected."
    }

    private var expandedCoachMessage: String {
        guard let latestSession else {
            return "No imported workout is available yet. Start collection on the watch, save the session there, and the phone will keep the CSV in Files while also importing it into the app."
        }

        let filename = latestSession.sourceFilename ?? "Unknown source"
        return """
        Raw workout data is already safely on the phone.

        Source file: \(filename)
        Samples stored in app data: \(latestSession.sampleCount)
        Repetitions detected: \(latestSession.repetitionCount)

        Final Core ML scoring and coaching can plug into this summary screen later without changing the watch-to-phone transfer flow.
        """
    }

    var body: some View {
        NavigationView {
            ZStack {
                FormFitBackdrop()

                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(FormFitTheme.cardBorder.opacity(0.5), lineWidth: 20)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: scoreTrim)
                            .stroke(FormFitTheme.orange, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 8) {
                            Text(scoreValue)
                                .font(.system(size: 56, weight: .bold))
                                .foregroundStyle(FormFitTheme.orange)
                                .multilineTextAlignment(.center)
                            Text(scoreLabel)
                                .font(.headline)
                                .foregroundStyle(FormFitTheme.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(FormFitTheme.orange)
                            Text("AI Coach")
                                .font(.headline)
                                .foregroundStyle(FormFitTheme.textPrimary)
                        }

                        Text(coachMessage)
                            .font(.subheadline)
                            .foregroundStyle(FormFitTheme.textSecondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .formFitCard()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFeedbackExpanded = true
                        }
                    }

                    if let latestSession {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(latestSession.exerciseName) • \(latestSession.durationMinutes) min")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FormFitTheme.textPrimary)

                            if let sourceFilename = latestSession.sourceFilename {
                                Text(sourceFilename)
                                    .font(.caption)
                                    .foregroundStyle(FormFitTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 20) {
                        MetricView(icon: "flame.fill", value: "\(latestSession?.repetitionCount ?? 0)", label: "Reps", color: FormFitTheme.orange)
                        MetricView(icon: "waveform.path.ecg", value: "\(latestSession?.sampleCount ?? 0)", label: "Samples", color: FormFitTheme.info)
                        MetricView(
                            icon: "timer",
                            value: latestSession?.sampleRateHz.map { "\(Int($0.rounded()))Hz" } ?? "--",
                            label: "Rate",
                            color: FormFitTheme.success
                        )
                    }

                    Spacer()

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.headline)
                            .formFitPrimaryButton()
                    }
                    .padding(.horizontal)
                }
                .padding()
                .navigationTitle("Workout Summary")

                if showFeedbackExpanded {
                    ZStack {
                        Rectangle()
                            .foregroundColor(Color.black.opacity(0.5))
                            .edgesIgnoringSafeArea(.all)

                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(FormFitTheme.orange)
                                    .font(.title2)
                                Text("Session Import Details")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(FormFitTheme.textPrimary)
                            }

                            Text(expandedCoachMessage)
                                .font(.body)
                                .foregroundStyle(FormFitTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tap anywhere to close")
                                .font(.caption)
                                .foregroundStyle(FormFitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                        }
                        .formFitCard()
                        .padding(.horizontal, 40)
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFeedbackExpanded = false
                        }
                    }
                }
            }
        }
    }
}

struct MetricView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(FormFitTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .formFitCard()
    }
}

#Preview {
    WorkoutViewPreview()
}

private struct WorkoutViewPreview: View {
    var body: some View {
        WorkoutView()
            .modelContainer(previewContainer)
    }

    private var previewContainer: ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: WorkoutSession.self,
            WorkoutRepetition.self,
            WorkoutMotionSample.self,
            configurations: configuration
        )
        try! WorkoutSessionSeeder.seedIfNeeded(in: container.mainContext)
        return container
    }
}
