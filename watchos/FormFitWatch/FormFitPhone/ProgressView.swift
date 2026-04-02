import SwiftUI
import Charts
import SwiftData

@MainActor
struct ProgressView: View {
    @Query(sort: \WorkoutSession.workoutDate) private var storedSessions: [WorkoutSession]
    @State private var selectedDay: Date?

    private let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter
    }()

    private var workoutSessions: [WorkoutSessionSnapshot] {
        storedSessions.map(WorkoutSessionSnapshot.init(session:))
    }

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
                    HStack(spacing: 16) {
                        SummaryCard(
                            title: "Workouts",
                            value: "\(summary.weeklyWorkouts)",
                            icon: "figure.strengthtraining.traditional",
                            color: FormFitTheme.orange
                        )

                        SummaryCard(
                            title: "Avg Form",
                            value: "\(summary.weeklyAverageScore)%",
                            icon: "chart.line.uptrend.xyaxis",
                            color: FormFitTheme.success
                        )
                    }

                    VStack(alignment: .leading, spacing: 100) {
                        Text("Form Score Trend")
                            .font(.title.bold())
                            .foregroundStyle(FormFitTheme.textPrimary)

                        if summary.chartData.allSatisfy({ $0.workoutCount == 0 }) {
                            Text("Weekly scores will populate here as imported workouts are stored.")
                                .font(.subheadline)
                                .foregroundStyle(FormFitTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Chart(summary.chartData) { item in
                            LineMark(
                                x: .value("Day", item.date),
                                y: .value("Score", item.averageScore)
                            )
                            .foregroundStyle(FormFitTheme.orange)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Day", item.date),
                                y: .value("Score", item.averageScore)
                            )
                            .foregroundStyle(FormFitTheme.orange.opacity(0.12))
                            .interpolationMethod(.catmullRom)

                            if let selectedDay, Calendar.current.isDate(item.date, inSameDayAs: selectedDay) {
                                PointMark(
                                    x: .value("Day", item.date),
                                    y: .value("Score", item.averageScore)
                                )
                                .foregroundStyle(FormFitTheme.orange)
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
                                                    .foregroundStyle(FormFitTheme.textSecondary)

                                                Text(selectedDateFormatter.string(from: data.date))
                                                    .font(.caption2)
                                                    .foregroundStyle(FormFitTheme.textSecondary)

                                                Text("\(Int(data.averageScore.rounded()))")
                                                    .font(.title2)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(FormFitTheme.orange)

                                                Text(data.workoutCount == 1 ? "1 workout" : "\(data.workoutCount) workouts")
                                                    .font(.caption2)
                                                    .foregroundStyle(FormFitTheme.textSecondary)
                                            }
                                            .formFitCard()
                                        }
                                    }
                            }
                        }
                        .frame(height: 250)
                        .chartYScale(domain: 0...100)
                        .chartXSelection(value: $selectedDay)
                        .chartXAxis {
                            AxisMarks(values: summary.chartData.map(\.date)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                    }
                    .formFitCard()
                }
                .padding()
            }
            .formFitScreenBackground()
            .navigationTitle("Progress")
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
                .foregroundStyle(FormFitTheme.textPrimary)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(FormFitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .formFitCard()
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
