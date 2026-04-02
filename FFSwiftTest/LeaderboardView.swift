import SwiftUI
import SwiftData

private struct LeaderboardEntry: Identifiable {
    let id: String
    let rank: Int
    let profile: AppUserProfile
}

struct LeaderboardView: View {
    private let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    @Environment(\.modelContext) private var modelContext
    @State private var weeklyBestScore: Int?

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

                        Text("See how your best form score this week compares with your friends.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)

                    if let score = currentUser.weeklyBestScore {
                        HStack(spacing: 16) {
                            LeaderboardHighlightCard(
                                title: "Your Best",
                                value: "\(score)",
                                subtitle: "This week",
                                color: primaryOrange
                            )

                            LeaderboardHighlightCard(
                                title: "Current Rank",
                                value: "#\(currentUserRank)",
                                subtitle: "Among friends",
                                color: .blue
                            )
                        }
                    } else {
                        Text("Complete a workout this week to join the leaderboard.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                    }

                    VStack(spacing: 12) {
                        ForEach(entries) { entry in
                            LeaderboardRow(
                                rank: entry.rank,
                                profile: entry.profile,
                                accentColor: entry.profile.isCurrentUser ? primaryOrange : .blue
                            )
                        }
                    }
                }
                .padding()
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Leaderboard")
        }
        .task {
            loadWeeklyBestScore()
        }
    }

    private var currentUserRank: Int {
        entries.first { $0.profile.isCurrentUser }?.rank ?? 1
    }

    private func loadWeeklyBestScore() {
        var descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.workoutDate)])
        descriptor.includePendingChanges = true

        do {
            let sessions = try modelContext.fetch(descriptor).map(WorkoutSessionSnapshot.init(session:))
            let bestScore = WorkoutSummaryBuilder.weeklyBestScore(from: sessions)
            weeklyBestScore = bestScore == 0 ? nil : bestScore
        } catch {
            weeklyBestScore = nil
        }
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
                .foregroundColor(.gray)

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(profile.weeklyBestScore.map(String.init) ?? "--")
                    .font(.title3.weight(.bold))
                    .foregroundColor(accentColor)

                Text("Best score")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
