import SwiftUI
import Charts
import SwiftData

struct ProgressView: View {
    let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    @Environment(\.modelContext) private var modelContext
    @State private var workoutSessions: [WorkoutSessionSnapshot] = []

    @State private var selectedDay: Date?

    private let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter
    }()
    
    private var summary: WorkoutSummarySnapshot {
        WorkoutSummaryBuilder.build(from: workoutSessions)
    }

    private var selectedData: ChartPoint? {
        guard let selectedDay else { return nil }
        return summary.chartData.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Weekly Summary
                    HStack(spacing: 16) {
                        SummaryCard(
                            title: "Workouts",
                            value: "\(summary.weeklyWorkouts)",
                            icon: "figure.strengthtraining.traditional",
                            color: primaryOrange
                        )
                        
                        SummaryCard(
                            title: "Avg Form",
                            value: "\(summary.weeklyAverageScore)%",
                            icon: "chart.line.uptrend.xyaxis",
                            color: .green
                        )
                    }
                    
                    // Form Score Trend
                    VStack(alignment: .leading, spacing: 100) {
                        Text("Form Score Trend")
                            .font(.title.bold())

                        if summary.chartData.allSatisfy({ $0.workoutCount == 0 }) {
                            Text("Weekly scores will populate here as workouts are stored.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Chart(summary.chartData) { item in
                            LineMark(
                                x: .value("Day", item.date),
                                y: .value("Score", item.averageScore)
                            )
                            .foregroundStyle(primaryOrange)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Day", item.date),
                                y: .value("Score", item.averageScore)
                            )
                            .foregroundStyle(primaryOrange.opacity(0.1))
                            .interpolationMethod(.catmullRom)
                            
                            if let selectedDay, Calendar.current.isDate(item.date, inSameDayAs: selectedDay) {
                                PointMark(
                                    x: .value("Day", item.date),
                                    y: .value("Score", item.averageScore)
                                )
                                .foregroundStyle(primaryOrange)
                                .symbolSize(100)
                            }
                            
                            if let selectedDay, Calendar.current.isDate(item.date, inSameDayAs: selectedDay) {
                                RuleMark(x: .value("Day", selectedDay))
                                    .foregroundStyle(.gray.opacity(0.3))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                    .annotation(position: .automatic, alignment: .center, spacing: 0) {
                                        if let data = selectedData {
                                            VStack(spacing: 8) {
                                                Text(data.dayLabel)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.gray)

                                                Text(selectedDateFormatter.string(from: data.date))
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                
                                                Text("\(Int(data.averageScore.rounded()))")
                                                    .font(.title2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(primaryOrange)
                                                
                                                Text(data.workoutCount == 1 ? "1 workout" : "\(data.workoutCount) workouts")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(12)
                                            .background(Color.white)
                                            .cornerRadius(12)
                                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                        }
                                    }
                            }
                        }
                        .frame(height: 250)
                        .chartYScale(domain: 0...100)
                        .chartXSelection(value: $selectedDay)
                        .chartXAxis {
                            AxisMarks(values: summary.chartData.map(\.date)) { value in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                }
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Progress")
        }
        .task {
            loadWorkoutSessions()
        }
    }

    private func loadWorkoutSessions() {
        var descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.workoutDate)])
        descriptor.includePendingChanges = true

        do {
            workoutSessions = try modelContext.fetch(descriptor).map(WorkoutSessionSnapshot.init(session:))
        } catch {
            workoutSessions = []
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    ProgressViewPreview()
}

private struct ProgressViewPreview: View {
    var body: some View {
        ProgressView()
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
