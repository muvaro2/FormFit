import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    let onShowTutorial: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)

                WorkoutStartView()
                    .tabItem {
                        Image(systemName: "figure.run")
                        Text("Workout")
                    }
                    .tag(1)

                ProgressView()
                    .tabItem {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Progress")
                    }
                    .tag(2)

                LeaderboardView()
                    .tabItem {
                        Image(systemName: "person.3.fill")
                        Text("Leaderboard")
                    }
                    .tag(3)

                ProfileView()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(4)
            }
            .tint(FormFitTheme.orange)
            .toolbarBackground(FormFitTheme.cardBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)

            Button(action: onShowTutorial) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(FormFitTheme.orange)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(FormFitTheme.cardBackground.opacity(0.96))
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView(onShowTutorial: {})
}
