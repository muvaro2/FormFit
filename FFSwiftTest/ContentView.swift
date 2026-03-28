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
                
                WorkoutView()
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
                
                ProfileView()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(3)
            }
            .accentColor(Color(red: 1.0, green: 0.42, blue: 0.21))

            Button(action: onShowTutorial) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.21))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
    }
}

#Preview {
    ContentView(onShowTutorial: {})
}
