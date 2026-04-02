import SwiftUI
import SwiftData

@MainActor
struct HomeView: View {
    @ObservedObject private var connectivity = PhoneConnectivityManager.shared
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]

    private var workoutSessions: [WorkoutSessionSnapshot] {
        storedSessions.map(WorkoutSessionSnapshot.init(session:))
    }

    private var summary: WorkoutSummarySnapshot {
        WorkoutSummaryBuilder.build(from: workoutSessions)
    }

    private var watchStatusTitle: String {
        if connectivity.isWatchReady {
            return "Connected"
        }

        if connectivity.isPaired {
            return "Install Watch App"
        }

        return "Waiting for Watch"
    }

    private var watchStatusColor: Color {
        if connectivity.isWatchReady {
            return FormFitTheme.success
        }

        if connectivity.isPaired {
            return FormFitTheme.orange
        }

        return FormFitTheme.textSecondary
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "applewatch")
                                .foregroundStyle(FormFitTheme.orange)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Watch")
                                    .font(.headline)
                                    .foregroundStyle(FormFitTheme.textPrimary)
                                Text(watchStatusTitle)
                                    .font(.caption)
                                    .foregroundStyle(FormFitTheme.textSecondary)
                            }

                            Spacer()

                            Circle()
                                .fill(watchStatusColor)
                                .frame(width: 12, height: 12)
                        }

                        VStack(spacing: 10) {
                            DataStatusRow(label: "Connection", value: connectivity.status)
                            DataStatusRow(label: "Saved CSVs", value: "\(connectivity.storedCSVCount)")
                            DataStatusRow(label: "App Sessions", value: "\(storedSessions.count)")
                            DataStatusRow(label: "Watch Buffer", value: "\(connectivity.watchBufferCount)")

                            if let name = connectivity.lastReceivedFilename {
                                DataStatusRow(label: "Last File", value: name)
                            }

                            if let importMessage = connectivity.lastImportMessage {
                                DataStatusRow(label: "Import", value: importMessage)
                            }

                            if let watchMessage = connectivity.lastWatchMessage {
                                DataStatusRow(label: "Watch", value: watchMessage)
                            }
                        }
                    }
                    .formFitCard()

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            BiometricCard(
                                icon: "heart.fill",
                                title: "Latest Score",
                                value: "\(summary.latestScore)",
                                unit: "Preview",
                                color: FormFitTheme.danger
                            )

                            BiometricCard(
                                icon: "flame.fill",
                                title: "Streak",
                                value: "\(summary.streakDays)",
                                unit: "Days",
                                color: FormFitTheme.orange
                            )
                        }

                        HStack(spacing: 16) {
                            BiometricCard(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "30 Day Progress",
                                value: formattedProgress(summary.monthlyProgressPercent),
                                unit: "Change",
                                color: FormFitTheme.success
                            )

                            NavigationLink(destination: WorkoutStartView()) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "figure.run")
                                            .foregroundStyle(FormFitTheme.orange)
                                            .font(.title3)
                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundStyle(FormFitTheme.orange)
                                        Text("Workout")
                                            .font(.caption)
                                            .foregroundStyle(FormFitTheme.textSecondary)
                                    }

                                    Text("Begin Training")
                                        .font(.subheadline)
                                        .foregroundStyle(FormFitTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .formFitCard()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Workouts")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        if summary.recentWorkouts.isEmpty {
                            Text("Imported watch sessions will appear here once the phone receives and saves a CSV.")
                                .font(.subheadline)
                                .foregroundStyle(FormFitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .formFitCard()
                        } else {
                            ForEach(summary.recentWorkouts, id: \.id) { workout in
                                WorkoutCard(
                                    exercise: workout.exerciseName,
                                    formScore: workout.formScore,
                                    duration: "\(workout.durationMinutes) min",
                                    primaryOrange: FormFitTheme.orange
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .formFitScreenBackground()
            .navigationTitle("FormFit")
        }
    }

    private func formattedProgress(_ progress: Int) -> String {
        progress > 0 ? "+\(progress)%" : "\(progress)%"
    }
}

private struct DataStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FormFitTheme.textSecondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}

struct BiometricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(FormFitTheme.textPrimary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(FormFitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formFitCard()
    }
}

struct WorkoutCard: View {
    let exercise: String
    let formScore: Int
    let duration: String
    let primaryOrange: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise)
                    .font(.headline)
                    .foregroundStyle(FormFitTheme.textPrimary)

                Label(duration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }

            Spacer()

            VStack(spacing: 4) {
                Text("\(formScore)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(primaryOrange)
                Text("Preview")
                    .font(.caption2)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }
        }
        .formFitCard()
    }
}

#Preview {
    HomeViewPreview()
}

private struct HomeViewPreview: View {
    var body: some View {
        HomeView()
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
