import SwiftUI
import SwiftData

struct WorkoutView: View {
    @State private var showFeedbackExpanded = false
    @State private var showGraphs = false
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]

    private var latestSession: WorkoutSession? {
        storedSessions.max(by: { $0.workoutDate < $1.workoutDate })
    }

    private var sortedRepetitions: [WorkoutRepetition] {
        guard let latestSession else { return [] }
        return latestSession.repetitions.sorted {
            if $0.index == $1.index {
                return $0.repetitionDate < $1.repetitionDate
            }
            return $0.index < $1.index
        }
    }

    private var averageRangeOfMotion: Double? {
        let values = sortedRepetitions.compactMap(\.rangeOfMotion)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageConcentricTime: Double? {
        let values = sortedRepetitions.compactMap(\.concentricTime)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageEccentricTime: Double? {
        let values = sortedRepetitions.compactMap(\.eccentricTime)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageEccentricScore: EccentricScore? {
        averageEccentricTime.map(eccentricScore(duration:))
    }

    private var repetitionInsights: [RepetitionInsight] {
        sortedRepetitions.map { repetition in
            RepetitionInsight(
                id: repetition.id,
                index: repetition.index + 1,
                rangeOfMotion: repetition.rangeOfMotion,
                eccentricTime: repetition.eccentricTime,
                concentricTime: repetition.concentricTime,
                formScore: repetition.formScore,
                elbowHikingScore: repetition.elbowHikingScore,
                shoulderHikingScore: repetition.shoulderHikingScore,
                torsoTwistScore: repetition.torsoTwistScore
            )
        }
    }

    private var scoreValue: String {
        guard let latestSession else { return "--" }
        return "\(latestSession.formScore)"
    }

    private var scoreLabel: String {
        guard latestSession != nil else { return "No Session" }
        return "Form Score"
    }

    private var scoreTrim: Double {
        guard let latestSession else { return 0.12 }
        let normalized = Double(latestSession.formScore) / 100.0
        return max(0.12, min(normalized, 1.0))
    }

    private var coachMessage: String {
        guard let latestSession else {
            return "No imported workout yet. Start a set on the watch and the score will appear here automatically."
        }

        let score = latestSession.formScore
        let reps = latestSession.repetitionCount
        switch score {
        case 90...:
            return "Great set — \(reps) reps scored \(score)/100. Clean form across the board."
        case 75..<90:
            return "Solid set — \(reps) reps scored \(score)/100. Minor form drift detected."
        case 60..<75:
            return "Decent set — \(reps) reps scored \(score)/100. Focus on eccentric tempo and keeping the elbow pinned."
        default:
            return "\(reps) reps scored \(score)/100. Review your form cues and slow the lowering phase."
        }
    }

    private var expandedCoachMessage: String {
        guard let latestSession else {
            return "No imported workout is available yet. Start collection on the watch — the phone will auto-save and score it."
        }

        let filename = latestSession.sourceFilename ?? "Unknown source"
        return """
        Form score: \(latestSession.formScore)/100
        Reps detected: \(latestSession.repetitionCount)
        Samples stored: \(latestSession.sampleCount)
        Source file: \(filename)

        Scoring weights: 25% each for elbow hike, shoulder shrug, torso twist (Core ML), plus 25% for eccentric tempo (2–3s ideal).
        """
    }

    var body: some View {
        NavigationView {
            ZStack {
                FormFitBackdrop()

                ScrollView {
                    VStack(spacing: 24) {
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
                        .frame(maxWidth: .infinity)

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

                        if let averageRangeOfMotion, let averageEccentricTime {
                            HStack(spacing: 20) {
                                MetricView(
                                    icon: "ruler",
                                    value: "\(Int(averageRangeOfMotion.rounded()))°",
                                    label: "Avg ROM",
                                    color: FormFitTheme.warning
                                )
                                MetricView(
                                    icon: "arrow.down.circle",
                                    value: "\(averageConcentricTime?.formatted(.number.precision(.fractionLength(1))) ?? "--")s",
                                    label: "Concentric",
                                    color: FormFitTheme.info
                                )
                                MetricView(
                                    icon: "arrow.up.circle",
                                    value: "\(averageEccentricTime.formatted(.number.precision(.fractionLength(1))))s",
                                    label: "Eccentric",
                                    color: color(for: averageEccentricScore)
                                )
                            }
                        }

                        if !repetitionInsights.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Rep Split")
                                    .font(.headline)
                                    .foregroundStyle(FormFitTheme.textPrimary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(repetitionInsights) { repetition in
                                            RepetitionInsightCard(repetition: repetition)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .formFitCard()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)

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
            .navigationTitle("Workout Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(FormFitTheme.orange)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if let latestSession, latestSession.sampleCount > 0 {
                        Button(action: {
                            showGraphs = true
                        }) {
                            Label("See Graphs", systemImage: "chart.xyaxis.line")
                                .font(.headline)
                                .formFitSecondaryButton(accent: FormFitTheme.orange)
                        }
                    }

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.headline)
                            .formFitPrimaryButton()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
        }
        .fullScreenCover(isPresented: $showGraphs) {
            if let latestSession {
                WorkoutGraphsView(session: latestSession)
            }
        }
    }

    private func color(for score: EccentricScore?) -> Color {
        switch score {
        case .good:
            return FormFitTheme.success
        case .slightlyFast:
            return FormFitTheme.warning
        case .tooFast:
            return FormFitTheme.danger
        case nil:
            return FormFitTheme.textSecondary
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

private struct RepetitionInsight: Identifiable {
    let id: UUID
    let index: Int
    let rangeOfMotion: Double?
    let eccentricTime: Double?
    let concentricTime: Double?
    let formScore: Double?
    let elbowHikingScore: Double?
    let shoulderHikingScore: Double?
    let torsoTwistScore: Double?
}

private struct RepetitionInsightCard: View {
    let repetition: RepetitionInsight

    private var eccentricStatus: EccentricScore? {
        repetition.eccentricTime.map(eccentricScore(duration:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rep \(repetition.index)")
                    .font(.headline)
                    .foregroundStyle(FormFitTheme.textPrimary)

                Spacer(minLength: 8)

                if let formScore = repetition.formScore {
                    Text("\(Int(formScore.rounded()))/100")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scoreColor(for: formScore))
                }
            }

            Text(repetition.rangeOfMotion.map { "\($0.formatted(.number.precision(.fractionLength(0))))° ROM" } ?? "--")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FormFitTheme.orange)

            Text(repetition.eccentricTime.map { "\($0.formatted(.number.precision(.fractionLength(1))))s eccentric" } ?? "Eccentric pending")
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)

            Text(repetition.concentricTime.map { "\($0.formatted(.number.precision(.fractionLength(1))))s concentric" } ?? "Concentric pending")
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)

            if let eccentricStatus {
                Text(eccentricStatus.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: eccentricStatus))
            }

            if repetition.hasModelInsights {
                Divider()
                    .padding(.vertical, 2)

                insightRow(title: "Elbow", value: repetition.elbowHikingScore)
                rawInsightRow(title: "Elbow raw", value: repetition.elbowHikingScore)
                insightRow(title: "Shoulder", value: repetition.shoulderHikingScore)
                rawInsightRow(title: "Shoulder raw", value: repetition.shoulderHikingScore)
                insightRow(title: "Torso", value: repetition.torsoTwistScore)
                rawInsightRow(title: "Torso raw", value: repetition.torsoTwistScore)
            }
        }
        .frame(width: 170, alignment: .leading)
        .formFitCard()
    }

    private func color(for score: EccentricScore) -> Color {
        switch score {
        case .good:
            return FormFitTheme.success
        case .slightlyFast:
            return FormFitTheme.warning
        case .tooFast:
            return FormFitTheme.danger
        }
    }

    private func insightRow(title: String, value: Double?) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)

            Spacer(minLength: 8)

            Text(formattedIssueScore(value))
                .font(.caption.weight(.semibold))
                .foregroundStyle(issueColor(for: value))
        }
    }

    private func formattedIssueScore(_ value: Double?) -> String {
        guard let value else { return "--" }
        let subscore = max(1, min(100, Int(((1.0 - value) * 100.0).rounded())))
        return "\(subscore)/100"
    }

    private func rawInsightRow(title: String, value: Double?) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(FormFitTheme.textSecondary)

            Spacer(minLength: 8)

            Text(formattedRawScore(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(FormFitTheme.textSecondary)
        }
    }

    private func formattedRawScore(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.3f", value)
    }

    private func issueColor(for value: Double?) -> Color {
        guard let value else { return FormFitTheme.textSecondary }
        switch value {
        case ..<0.33:
            return FormFitTheme.success
        case ..<0.66:
            return FormFitTheme.warning
        default:
            return FormFitTheme.danger
        }
    }

    private func scoreColor(for score: Double) -> Color {
        switch score {
        case 90...:
            return FormFitTheme.success
        case 75..<90:
            return FormFitTheme.warning
        default:
            return FormFitTheme.danger
        }
    }
}

private extension RepetitionInsight {
    var hasModelInsights: Bool {
        formScore != nil ||
        elbowHikingScore != nil ||
        shoulderHikingScore != nil ||
        torsoTwistScore != nil
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
