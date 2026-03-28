import SwiftUI
import SwiftData

struct HomeView: View {
    let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    @Query(sort: \WorkoutSession.workoutDate) private var workoutSessions: [WorkoutSession]

    init() {}

    private var summary: WorkoutSummarySnapshot {
        WorkoutSummaryBuilder.build(from: workoutSessions)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Apple Watch Status
                    HStack {
                        Image(systemName: "applewatch")
                            .foregroundColor(primaryOrange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Watch")
                                .font(.headline)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // Biometric Cards Grid
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            BiometricCard(
                                icon: "heart.fill",
                                title: "Last Score",
                                value: "\(summary.latestScore)",
                                unit: "Rating",
                                color: .red
                            )
                            
                            BiometricCard(
                                icon: "flame.fill",
                                title: "Streak",
                                value: "\(summary.streakDays)",
                                unit: "Days",
                                color: primaryOrange
                            )
                        }
                        
                        HStack(spacing: 16) {
                            BiometricCard(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "30 Day Progress",
                                value: formattedProgress(summary.monthlyProgressPercent),
                                unit: "Increase",
                                color: .green
                            )
                            NavigationLink(destination: WorkoutView()) {
                                   VStack(alignment: .leading, spacing: 12) {
                                       HStack {
                                           Image(systemName: "figure.run")
                                               .foregroundColor(primaryOrange)
                                               .font(.title3)
                                           Spacer()
                                       }
                                       
                                       VStack(alignment: .leading, spacing: 4) {
                                           Text("Start")
                                               .font(.title)
                                               .fontWeight(.bold)
                                               .foregroundColor(primaryOrange)
                                           Text("Workout")
                                               .font(.caption)
                                               .foregroundColor(.gray)
                                       }
                                       
                                       Text("Begin Training")
                                           .font(.subheadline)
                                           .foregroundColor(.gray)
                                   }
                                   .padding()
                                   .frame(maxWidth: .infinity, alignment: .leading)
                                   .background(Color.white)
                                   .cornerRadius(16)
                                   .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                               }
                               .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // Recent Workouts
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Workouts")
                            .font(.title3)
                            .fontWeight(.bold)

                        if summary.recentWorkouts.isEmpty {
                            Text("Workout history will appear here once sessions are saved.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(16)
                        } else {
                            ForEach(summary.recentWorkouts, id: \.id) { workout in
                                WorkoutCard(
                                    exercise: workout.exerciseName,
                                    formScore: workout.formScore,
                                    duration: "\(workout.durationMinutes) min",
                                    primaryOrange: primaryOrange
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("FormFit")
        }
    }

    private func formattedProgress(_ progress: Int) -> String {
        progress > 0 ? "+\(progress)%" : "\(progress)%"
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
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
                
                HStack(spacing: 16) {
                    Label(duration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    
                }
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("\(formScore)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(primaryOrange)
                Text("Form")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
        let container = try! ModelContainer(for: WorkoutSession.self, configurations: configuration)
        try! WorkoutSessionSeeder.seedIfNeeded(in: container.mainContext)
        return container
    }
}
