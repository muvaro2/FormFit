import Foundation
import SwiftData

struct WorkoutSessionSnapshot: Identifiable {
    let id: UUID
    let exerciseName: String
    let formScore: Int
    let durationMinutes: Int
    let workoutDate: Date

    init(session: WorkoutSession) {
        id = session.id
        exerciseName = session.exerciseName
        formScore = session.formScore
        durationMinutes = session.durationMinutes
        workoutDate = session.workoutDate
    }
}

@Model
final class WorkoutSession {
    var id: UUID
    var exerciseName: String
    var formScore: Int
    var durationMinutes: Int
    var workoutDate: Date
    var sourceFilename: String?
    var repetitionCount: Int = 0
    var sampleCount: Int = 0
    var sampleRateHz: Double?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutRepetition.session) var repetitions: [WorkoutRepetition]

    init(
        id: UUID = UUID(),
        exerciseName: String,
        formScore: Int,
        durationMinutes: Int,
        workoutDate: Date,
        sourceFilename: String? = nil,
        repetitionCount: Int = 0,
        sampleCount: Int = 0,
        sampleRateHz: Double? = nil,
        repetitions: [WorkoutRepetition] = []
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.formScore = formScore
        self.durationMinutes = durationMinutes
        self.workoutDate = workoutDate
        self.sourceFilename = sourceFilename
        self.repetitionCount = repetitionCount
        self.sampleCount = sampleCount
        self.sampleRateHz = sampleRateHz
        self.repetitions = repetitions
    }
}

@Model
final class WorkoutRepetition {
    var id: UUID
    var index: Int = 0
    var rangeOfMotion: Double?
    var concentricTime: Double?
    var eccentricTime: Double?
    var repetitionDate: Date
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutMotionSample.repetition) var samples: [WorkoutMotionSample]

    init(
        id: UUID = UUID(),
        index: Int,
        rangeOfMotion: Double? = nil,
        concentricTime: Double? = nil,
        eccentricTime: Double? = nil,
        repetitionDate: Date,
        session: WorkoutSession? = nil,
        samples: [WorkoutMotionSample] = []
    ) {
        self.id = id
        self.index = index
        self.rangeOfMotion = rangeOfMotion
        self.concentricTime = concentricTime
        self.eccentricTime = eccentricTime
        self.repetitionDate = repetitionDate
        self.session = session
        self.samples = samples
    }
}

@Model
final class WorkoutMotionSample {
    var id: UUID
    var index: Int = 0
    var relativeTime: Double = 0
    var accelerationX: Double = 0
    var accelerationY: Double = 0
    var accelerationZ: Double = 0
    var gyroX: Double = 0
    var gyroY: Double = 0
    var gyroZ: Double = 0
    var roll: Double = 0
    var pitch: Double = 0
    var yaw: Double = 0
    var repetition: WorkoutRepetition?

    init(
        id: UUID = UUID(),
        index: Int,
        relativeTime: Double,
        accelerationX: Double,
        accelerationY: Double,
        accelerationZ: Double,
        gyroX: Double,
        gyroY: Double,
        gyroZ: Double,
        roll: Double,
        pitch: Double,
        yaw: Double,
        repetition: WorkoutRepetition? = nil
    ) {
        self.id = id
        self.index = index
        self.relativeTime = relativeTime
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.gyroZ = gyroZ
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.repetition = repetition
    }
}

enum WorkoutSessionSeeder {
    static let isSampleDataEnabled = true

    private static let seedSignatureKey = "WorkoutSessionSeeder.seedSignature"

    static func seedIfNeeded(in context: ModelContext) throws {
        guard isSampleDataEnabled else { return }

        let storedSeedSignature = UserDefaults.standard.string(forKey: seedSignatureKey)
        let currentSeedSignature = placeholderSeedSignature()
        let needsSeedRefresh = storedSeedSignature != currentSeedSignature

        if needsSeedRefresh {
            try resetSeedData(in: context)
        }

        var descriptor = FetchDescriptor<WorkoutSession>()
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for session in placeholderSessions() {
            context.insert(session)
        }

        try context.save()
        UserDefaults.standard.set(currentSeedSignature, forKey: seedSignatureKey)
    }

    private static func resetSeedData(in context: ModelContext) throws {
        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        for session in existingSessions {
            context.delete(session)
        }

        try context.save()
    }

    private static func placeholderSessions() -> [WorkoutSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return placeholderSeedData().compactMap { exerciseName, formScore, durationMinutes, offset in
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

    private static func placeholderSeedData() -> [(String, Int, Int, Int)] {
        [
            ("Mobility Warmup", 82, 9, -24),
            ("Bicep Curls", 84, 11, -21),
            ("Push-ups", 86, 10, -18),
            ("Shoulder Press", 83, 12, -16),
            ("Air Squats", 88, 14, -14),
            ("Bent-over Rows", 87, 13, -12),
            ("Reverse Lunges", 89, 15, -10),
            ("Dead Bugs", 91, 8, -5),
            ("Push-ups", 90, 11, -4),
            ("Goblet Squats", 92, 16, -3),
            ("Bicep Curls", 95, 12, -2),
            ("Plank Series", 93, 7, -1)
        ]
    }

    private static func placeholderSeedSignature() -> String {
        placeholderSeedData()
            .map { "\($0.0)|\($0.1)|\($0.2)|\($0.3)" }
            .joined(separator: "||")
    }
}

enum WorkoutSessionImporter {
    static func importCSV(
        at fileURL: URL,
        exerciseName: String = "External Rotation",
        in context: ModelContext
    ) throws -> WorkoutSession {
        let activitySet = try unpack_csv(fileURL.path)
        return try save(
            activitySet: activitySet,
            exerciseName: exerciseName,
            sourceFilename: fileURL.lastPathComponent,
            sampleRateHz: 50.0,
            in: context
        )
    }

    static func save(
        activitySet: ActivitySet,
        exerciseName: String = "External Rotation",
        sourceFilename: String? = nil,
        sampleRateHz: Double? = nil,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let repetitions = activitySet.repetitions
        let sampleCount = repetitions.reduce(0) { $0 + $1.samples.count }
        let durationSeconds = repetitions
            .flatMap(\.samples)
            .compactMap(\.relativeTime)
            .map(Double.init)
            .max() ?? 0

        let session = WorkoutSession(
            exerciseName: exerciseName,
            formScore: derivedFormScore(from: repetitions),
            durationMinutes: max(1, Int(ceil(durationSeconds / 60.0))),
            workoutDate: activitySet.timestamp,
            sourceFilename: sourceFilename,
            repetitionCount: repetitions.count,
            sampleCount: sampleCount,
            sampleRateHz: sampleRateHz
        )

        context.insert(session)

        session.repetitions = repetitions.enumerated().map { index, repetition in
            let storedRepetition = WorkoutRepetition(
                index: index,
                rangeOfMotion: repetition.rangeOfMotion.map(Double.init),
                concentricTime: repetition.concentricTime.map(Double.init),
                eccentricTime: repetition.eccentricTime.map(Double.init),
                repetitionDate: repetition.timestamp,
                session: session
            )

            storedRepetition.samples = repetition.samples.enumerated().map { sampleIndex, sample in
                WorkoutMotionSample(
                    index: sampleIndex,
                    relativeTime: Double(sample.relativeTime ?? 0),
                    accelerationX: Double(sample.accelerationX),
                    accelerationY: Double(sample.accelerationY),
                    accelerationZ: Double(sample.accelerationZ),
                    gyroX: Double(sample.gyroX),
                    gyroY: Double(sample.gyroY),
                    gyroZ: Double(sample.gyroZ),
                    roll: Double(sample.roll),
                    pitch: Double(sample.pitch),
                    yaw: Double(sample.yaw),
                    repetition: storedRepetition
                )
            }

            return storedRepetition
        }

        try context.save()
        return session
    }

    private static func derivedFormScore(from repetitions: [Repetition]) -> Int {
        let romValues = repetitions.compactMap(\.rangeOfMotion)
        guard !romValues.isEmpty else { return 0 }
        let averageROM = romValues.reduce(0, +) / Float(romValues.count)
        return max(0, min(100, Int(averageROM.rounded())))
    }
}

struct WorkoutSummarySnapshot {
    let latestScore: Int
    let streakDays: Int
    let monthlyProgressPercent: Int
    let recentWorkouts: [WorkoutSessionSnapshot]
    let weeklyWorkouts: Int
    let weeklyAverageScore: Int
    let weeklyBestScore: Int
    let chartData: [ChartPoint]

    static let empty = WorkoutSummarySnapshot(
        latestScore: 0,
        streakDays: 0,
        monthlyProgressPercent: 0,
        recentWorkouts: [],
        weeklyWorkouts: 0,
        weeklyAverageScore: 0,
        weeklyBestScore: 0,
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
    static func build(from sessions: [WorkoutSessionSnapshot], calendar: Calendar = .current) -> WorkoutSummarySnapshot {
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
        let weeklyBestScore = bestScore(for: weeklySessions)

        return WorkoutSummarySnapshot(
            latestScore: latestScore,
            streakDays: streakDays,
            monthlyProgressPercent: monthlyProgressPercent,
            recentWorkouts: recentWorkouts,
            weeklyWorkouts: weeklyWorkouts,
            weeklyAverageScore: weeklyAverageScore,
            weeklyBestScore: weeklyBestScore,
            chartData: chartData
        )
    }

    static func weeklyBestScore(from sessions: [WorkoutSessionSnapshot], calendar: Calendar = .current) -> Int {
        let weeklySessions = weeklySessions(from: sessions, calendar: calendar)
        return bestScore(for: weeklySessions)
    }

    private static func weeklySessions(from sessions: [WorkoutSessionSnapshot], calendar: Calendar) -> [WorkoutSessionSnapshot] {
        guard let weekInterval = referenceWeekInterval(from: sessions, calendar: calendar) else {
            return sessions
        }

        return sessions.filter { weekInterval.contains($0.workoutDate) }
    }

    private static func buildWeeklyChartData(from sessions: [WorkoutSessionSnapshot], calendar: Calendar) -> [ChartPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE")

        guard let weekInterval = referenceWeekInterval(from: sessions, calendar: calendar) else {
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

    private static func calculateStreakDays(from sessions: [WorkoutSessionSnapshot], calendar: Calendar) -> Int {
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

    private static func calculateMonthlyProgress(from sessions: [WorkoutSessionSnapshot], calendar: Calendar) -> Int {
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

    private static func averageScore(for sessions: [WorkoutSessionSnapshot]) -> Int {
        Int(averageScoreDouble(for: sessions).rounded())
    }

    private static func bestScore(for sessions: [WorkoutSessionSnapshot]) -> Int {
        sessions.map(\.formScore).max() ?? 0
    }

    private static func averageScoreDouble(for sessions: [WorkoutSessionSnapshot]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.reduce(0) { $0 + $1.formScore }
        return Double(total) / Double(sessions.count)
    }

    private static func referenceWeekInterval(
        from sessions: [WorkoutSessionSnapshot],
        calendar: Calendar
    ) -> DateInterval? {
        guard let latestWorkoutDate = sessions.map(\.workoutDate).max() else {
            return nil
        }

        return calendar.dateInterval(of: .weekOfYear, for: latestWorkoutDate)
    }
}
