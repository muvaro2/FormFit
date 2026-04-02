import SwiftUI
import SwiftData

@MainActor
struct ProfileView: View {
    @ObservedObject private var connectivity = PhoneConnectivityManager.shared
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]

    private var workoutSessions: [WorkoutSessionSnapshot] {
        storedSessions.map(WorkoutSessionSnapshot.init(session:))
    }

    private var weeklyBestScore: Int? {
        let best = WorkoutSummaryBuilder.weeklyBestScore(from: workoutSessions)
        return best == 0 ? nil : best
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(FormFitTheme.orange.opacity(0.16))
                                .frame(width: 100, height: 100)

                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(FormFitTheme.orange)
                        }

                        Text(AppUserDirectory.currentUserName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        Text("Member since \(AppUserDirectory.currentUserMemberSince)")
                            .font(.subheadline)
                            .foregroundStyle(FormFitTheme.textSecondary)

                        if let weeklyBestScore {
                            Text("Weekly best: \(weeklyBestScore)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FormFitTheme.orange)
                        }
                    }
                    .padding()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Achievements")
                            .font(.headline)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        HStack(spacing: 16) {
                            AchievementBadge(icon: "flame.fill", title: "100 Workouts", color: FormFitTheme.orange)
                            AchievementBadge(icon: "star.fill", title: "Perfect Form", color: .yellow)
                            AchievementBadge(icon: "bolt.fill", title: "Streak 30d", color: FormFitTheme.info)
                        }
                    }
                    .formFitCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Integrations")
                            .font(.headline)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        IntegrationRow(
                            name: "Apple Watch",
                            icon: "applewatch",
                            isConnected: connectivity.isWatchReady,
                            color: FormFitTheme.orange
                        )
                        IntegrationRow(name: "HealthKit", icon: "heart.fill", isConnected: true, color: FormFitTheme.danger)
                    }
                    .formFitCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Storage")
                            .font(.headline)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        StorageRow(icon: "folder.fill", title: "Files App CSVs", value: "\(connectivity.storedCSVCount)", color: FormFitTheme.orange)
                        StorageRow(icon: "tray.full.fill", title: "In-app Sessions", value: "\(storedSessions.count)", color: FormFitTheme.success)
                        StorageRow(icon: "antenna.radiowaves.left.and.right", title: "Watch Buffer", value: "\(connectivity.watchBufferCount)", color: FormFitTheme.info)

                        if let latestImported = connectivity.lastImportedFilename {
                            StorageRow(icon: "square.and.arrow.down.fill", title: "Latest Import", value: latestImported, color: FormFitTheme.info)
                        }
                    }
                    .formFitCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.headline)
                            .foregroundStyle(FormFitTheme.textPrimary)

                        SettingsRow(icon: "bell.fill", title: "Notifications", color: FormFitTheme.orange)
                        SettingsRow(icon: "person.2.fill", title: "Share with Friends", color: FormFitTheme.info)
                        SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support", color: FormFitTheme.success)
                    }
                    .formFitCard()
                }
                .padding()
            }
            .formFitScreenBackground()
            .navigationTitle("Profile")
        }
    }
}

struct AchievementBadge: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IntegrationRow: View {
    let name: String
    let icon: String
    let isConnected: Bool
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)

            Text(name)
                .font(.body)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct StorageRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(FormFitTheme.textPrimary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 30)

            Text(title)
                .font(.body)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(FormFitTheme.textSecondary)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ProfileViewPreview()
}

private struct ProfileViewPreview: View {
    var body: some View {
        ProfileView()
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
