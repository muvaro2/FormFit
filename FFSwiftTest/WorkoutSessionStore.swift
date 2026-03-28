import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var exerciseName: String
    var formScore: Int
    var durationMinutes: Int
    var workoutDate: Date

    init(
        id: UUID = UUID(),
        exerciseName: String,
        formScore: Int,
        durationMinutes: Int,
        workoutDate: Date
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.formScore = formScore
        self.durationMinutes = durationMinutes
        self.workoutDate = workoutDate
    }
}

enum WorkoutSessionSeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<WorkoutSession>()
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for session in placeholderSessions() {
            context.insert(session)
        }

        try context.save()
    }

    private static func placeholderSessions() -> [WorkoutSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let seedData: [(String, Int, Int, Int)] = [
            ("Mobility Warmup", 82, 9, -24),
            ("Bicep Curls", 84, 11, -21),
            ("Push-ups", 86, 10, -18),
            ("Shoulder Press", 83, 12, -16),
            ("Air Squats", 88, 14, -14),
            ("Bent-over Rows", 87, 13, -12),
            ("Reverse Lunges", 89, 15, -10),
            ("Dead Bugs", 91, 8, -8),
            ("Push-ups", 90, 11, -6),
            ("Goblet Squats", 92, 16, -5),
            ("Bicep Curls", 93, 12, -3),
            ("Plank Series", 95, 7, -1)
        ]

        return seedData.compactMap { exerciseName, formScore, durationMinutes, offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }

            return WorkoutSession(
                exerciseName: exerciseName,
                formScore: formScore,
                durationMinutes: durationMinutes,
                workoutDate: date
            )
        }
    }
}

struct WorkoutSummarySnapshot {
    let latestScore: Int
    let streakDays: Int
    let monthlyProgressPercent: Int
    let recentWorkouts: [WorkoutSession]
    let weeklyWorkouts: Int
    let weeklyAverageScore: Int
    let chartData: [ChartPoint]

    static let empty = WorkoutSummarySnapshot(
        latestScore: 0,
        streakDays: 0,
        monthlyProgressPercent: 0,
        recentWorkouts: [],
        weeklyWorkouts: 0,
        weeklyAverageScore: 0,
        chartData: []
    )
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let dayLabel: String
    let date: Date
    let averageScore: Double
    let workoutCount: Int
}

enum WorkoutSummaryBuilder {
    static func build(from sessions: [WorkoutSession], calendar: Calendar = .current) -> WorkoutSummarySnapshot {
        let sortedSessions = sessions.sorted { $0.workoutDate < $1.workoutDate }
        guard !sortedSessions.isEmpty else { return .empty }

        let latestScore = sortedSessions.last?.formScore ?? 0
        let streakDays = calculateStreakDays(from: sortedSessions, calendar: calendar)
        let monthlyProgressPercent = calculateMonthlyProgress(from: sortedSessions, calendar: calendar)
        let recentWorkouts = Array(sortedSessions.suffix(3).reversed())

        let chartData = buildWeeklyChartData(from: sortedSessions, calendar: calendar)
        let weeklySessions = weeklySessions(from: sortedSessions, calendar: calendar)
        let weeklyWorkouts = weeklySessions.count
        let weeklyAverageScore = averageScore(for: weeklySessions)

        return WorkoutSummarySnapshot(
            latestScore: latestScore,
            streakDays: streakDays,
            monthlyProgressPercent: monthlyProgressPercent,
            recentWorkouts: recentWorkouts,
            weeklyWorkouts: weeklyWorkouts,
            weeklyAverageScore: weeklyAverageScore,
            chartData: chartData
        )
    }

    private static func weeklySessions(from sessions: [WorkoutSession], calendar: Calendar) -> [WorkoutSession] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return sessions
        }

        return sessions.filter { weekInterval.contains($0.workoutDate) }
    }

    private static func buildWeeklyChartData(from sessions: [WorkoutSession], calendar: Calendar) -> [ChartPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")

        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }

        let weekSessions = sessions.filter { weekInterval.contains($0.workoutDate) }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                return nil
            }

            let daySessions = weekSessions.filter { calendar.isDate($0.workoutDate, inSameDayAs: date) }
            let average = averageScoreDouble(for: daySessions)

            return ChartPoint(
                dayLabel: formatter.string(from: date),
                date: date,
                averageScore: average,
                workoutCount: daySessions.count
            )
        }
    }

    private static func calculateStreakDays(from sessions: [WorkoutSession], calendar: Calendar) -> Int {
        let uniqueDays = Set(sessions.map { calendar.startOfDay(for: $0.workoutDate) })
        guard let latestDay = uniqueDays.max() else { return 0 }

        var streak = 0
        var currentDay = latestDay

        while uniqueDays.contains(currentDay) {
            streak += 1

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }

            currentDay = previousDay
        }

        return streak
    }

    private static func calculateMonthlyProgress(from sessions: [WorkoutSession], calendar: Calendar) -> Int {
        let sorted = sessions.sorted { $0.workoutDate < $1.workoutDate }
        let now = Date()
        let last30Days = sorted.filter {
            guard let daysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return $0.workoutDate >= daysAgo
        }

        guard last30Days.count >= 2 else { return 0 }

        let firstHalf = Array(last30Days.prefix(last30Days.count / 2))
        let secondHalf = Array(last30Days.suffix(last30Days.count - firstHalf.count))

        let baseline = averageScoreDouble(for: firstHalf)
        let latest = averageScoreDouble(for: secondHalf)
        guard baseline > 0 else { return 0 }

        return Int(((latest - baseline) / baseline * 100).rounded())
    }

    private static func averageScore(for sessions: [WorkoutSession]) -> Int {
        Int(averageScoreDouble(for: sessions).rounded())
    }

    private static func averageScoreDouble(for sessions: [WorkoutSession]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.reduce(0) { $0 + $1.formScore }
        return Double(total) / Double(sessions.count)
    }
}
