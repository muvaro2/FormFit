import SwiftUI
import SwiftData

private struct LeaderboardEntry: Identifiable {
    let id: String
    let rank: Int
    let profile: AppUserProfile
}

@MainActor
struct LeaderboardView: View {
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]

    private var workoutSessions: [WorkoutSessionSnapshot] {
        storedSessions.map(WorkoutSessionSnapshot.init(session:))
    }

    private var weeklyBestScore: Int? {
        let bestScore = WorkoutSummaryBuilder.weeklyBestScore(from: workoutSessions)
        return bestScore == 0 ? nil : bestScore
    }

    private var currentUser: AppUserProfile {
        AppUserDirectory.currentUserProfile(weeklyBestScore: weeklyBestScore)
    }

    private var leaderboard: [AppUserProfile] {
        ([currentUser] + AppUserDirectory.friendProfiles).sorted {
            ($0.weeklyBestScore ?? 0) > ($1.weeklyBestScore ?? 0)
        }
    }

    private var entries: [LeaderboardEntry] {
        leaderboard.enumerated().map { index, profile in
            LeaderboardEntry(
                id: profile.id,
                rank: index + 1,
                profile: profile
            )
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Weekly Best")
                            .font(.title.bold())
                            .foregroundStyle(FormFitTheme.textPrimary)

                        Text("See how your best imported score this week compares with your friends.")
                            .font(.subheadline)
                            .foregroundStyle(FormFitTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .formFitCard()

                    if let score = currentUser.weeklyBestScore {
                        HStack(spacing: 16) {
                            LeaderboardHighlightCard(
                                title: "Your Best",
                                value: "\(score)",
                                subtitle: "This week",
                                color: FormFitTheme.orange
                            )

                            LeaderboardHighlightCard(
                                title: "Current Rank",
                                value: "#\(currentUserRank)",
                                subtitle: "Among friends",
                                color: FormFitTheme.info
                            )
                        }
                    } else {
                        Text("Import a workout this week to join the leaderboard.")
                            .font(.subheadline)
                            .foregroundStyle(FormFitTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .formFitCard()
                    }

                    VStack(spacing: 12) {
                        ForEach(entries) { entry in
                            LeaderboardRow(
                                rank: entry.rank,
                                profile: entry.profile,
                                accentColor: entry.profile.isCurrentUser ? FormFitTheme.orange : FormFitTheme.info
                            )
                        }
                    }
                }
                .padding()
            }
            .formFitScreenBackground()
            .navigationTitle("Leaderboard")
        }
    }

    private var currentUserRank: Int {
        entries.first { $0.profile.isCurrentUser }?.rank ?? 1
    }
}

struct LeaderboardHighlightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(FormFitTheme.textSecondary)

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formFitCard()
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let profile: AppUserProfile
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.headline.weight(.bold))
                .foregroundColor(accentColor)
                .frame(width: 28)

            Circle()
                .fill(accentColor.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(initials(for: profile.name))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accentColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(FormFitTheme.textPrimary)

                    if profile.isCurrentUser {
                        Text("You")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor)
                            .cornerRadius(999)
                    }
                }

                Text(profile.memberSince)
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(profile.weeklyBestScore.map(String.init) ?? "--")
                    .font(.title3.weight(.bold))
                    .foregroundColor(accentColor)

                Text("Best score")
                    .font(.caption)
                    .foregroundStyle(FormFitTheme.textSecondary)
            }
        }
        .formFitCard()
    }

    private func initials(for name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }
}

#Preview {
    LeaderboardPreview()
}

private struct LeaderboardPreview: View {
    var body: some View {
        LeaderboardView()
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
