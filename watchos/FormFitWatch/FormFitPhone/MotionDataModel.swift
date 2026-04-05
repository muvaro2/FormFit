import Foundation
import CoreML

// MARK: - Constants

let defaultSampleRate: Double = 100.0
let minRepSamples: Int = 5
let accelTailMagThreshold: Double = 0.5
let accelTailQuietRunSamples: Int = 50
let accelTailMaxTrimSamples: Int = 300

// MARK: - Data structures

struct Sample: Codable, Equatable {
    var relativeTime: Double?

    var accelerationX: Double
    var accelerationY: Double
    var accelerationZ: Double

    var gyroX: Double
    var gyroY: Double
    var gyroZ: Double

    var roll: Double
    var pitch: Double
    var yaw: Double

    var flattenedChannels: [Float] {
        [
            accelerationX, accelerationY, accelerationZ,
            gyroX, gyroY, gyroZ,
            roll, pitch, yaw
        ].map(Float.init)
    }
}

struct Repetition: Codable, Equatable {
    var samples: [Sample]
    var rangeOfMotion: Double?
    var concentricTime: Double?
    var eccentricTime: Double?
    var timestamp: Date
}

struct ActivitySet: Codable, Equatable {
    var repetitions: [Repetition]
    var timestamp: Date
}

typealias sample = Sample
typealias repetition = Repetition
typealias activity_set = ActivitySet

/// One row from a FormFit session CSV (`t,ax,ay,az,gx,gy,gz,roll,pitch,yaw`).
struct SessionCSVRow: Equatable {
    var t: Double
    var ax: Double
    var ay: Double
    var az: Double
    var gx: Double
    var gy: Double
    var gz: Double
    var roll: Double
    var pitch: Double
    var yaw: Double
}

enum EccentricScore: String, CaseIterable {
    case good
    case slightlyFast = "slightly_fast"
    case tooFast = "too_fast"

    private static let colorHexByScore: [EccentricScore: String] = [
        .good: "#7dd87d",
        .slightlyFast: "#f5c842",
        .tooFast: "#e8675a"
    ]

    private static let labelByScore: [EccentricScore: String] = [
        .good: "Good eccentric",
        .slightlyFast: "Eccentric slightly too fast",
        .tooFast: "Eccentric too fast"
    ]

    var colorHex: String { Self.colorHexByScore[self]! }
    var label: String { Self.labelByScore[self]! }
}

// MARK: - Analysis result

struct FormFitCSVAnalysis {
    var trimmedRows: [SessionCSVRow]
    var repetitions: [Repetition]
}

enum FormFitCSVError: Error, LocalizedError {
    case fileReadFailed(url: URL, underlying: Error?)
    case missingOrInvalidHeader
    case missingRequiredColumns(missing: [String])
    case invalidCSVPath(String)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case let .fileReadFailed(url, err):
            return "Could not read CSV at \(url.path): \(err?.localizedDescription ?? "unknown")"
        case .missingOrInvalidHeader:
            return "CSV is missing a header row or it could not be parsed."
        case let .missingRequiredColumns(missing):
            return "CSV header is missing columns: \(missing.joined(separator: ", "))"
        case let .invalidCSVPath(path):
            return "Could not find CSV at path \(path)."
        case .emptyInput:
            return "CSV did not contain any motion samples."
        }
    }
}

private let requiredCSVColumnNames = [
    "t", "ax", "ay", "az", "gx", "gy", "gz", "roll", "pitch", "yaw"
]

// MARK: - Public API

func flatten(activity_set set: ActivitySet) throws -> MLMultiArray {
    let allSamples = set.repetitions.flatMap(\.samples)
    let channelsPerSample = 9

    let shape: [NSNumber] = [
        NSNumber(value: allSamples.count),
        NSNumber(value: channelsPerSample)
    ]
    let array = try MLMultiArray(shape: shape, dataType: .float32)

    for sampleIndex in allSamples.indices {
        let channels = allSamples[sampleIndex].flattenedChannels
        for channelIndex in 0..<channelsPerSample {
            let linearIndex = sampleIndex * channelsPerSample + channelIndex
            array[linearIndex] = NSNumber(value: channels[channelIndex])
        }
    }

    return array
}

func unpack_csv(_ fileName: String, sampleRate: Double = defaultSampleRate) throws -> ActivitySet {
    let csvURL = try resolveCSVURL(fileName)
    let sessionStart = Date()
    let analysis = try analyzeFormFitCSV(
        at: csvURL,
        sampleRate: sampleRate,
        sessionStart: sessionStart
    )

    return ActivitySet(
        repetitions: analysis.repetitions,
        timestamp: sessionStart
    )
}

func analyzeFormFitCSV(
    at url: URL,
    sampleRate: Double = defaultSampleRate,
    sessionStart: Date = Date()
) throws -> FormFitCSVAnalysis {
    let text: String
    do {
        text = try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw FormFitCSVError.fileReadFailed(url: url, underlying: error)
    }

    var rows = try parseFormFitCSV(text)
    rows = trimTailUntilAccelQuiet(rows)
    guard !rows.isEmpty else {
        throw FormFitCSVError.emptyInput
    }

    let samples: [Sample] = rows.map {
        Sample(
            relativeTime: $0.t,
            accelerationX: $0.ax,
            accelerationY: $0.ay,
            accelerationZ: $0.az,
            gyroX: $0.gx,
            gyroY: $0.gy,
            gyroZ: $0.gz,
            roll: $0.roll,
            pitch: $0.pitch,
            yaw: $0.yaw
        )
    }

    let fullRep = Repetition(
        samples: samples,
        rangeOfMotion: nil,
        concentricTime: nil,
        eccentricTime: nil,
        timestamp: sessionStart
    )

    let repetitions = splitReps(fullRep, sampleRate: sampleRate).map { rep in
        var updated = rep
        let metrics = calculate_metrics(repetition: rep, sampleRate: sampleRate)
        updated.rangeOfMotion = metrics.0
        updated.concentricTime = metrics.1
        updated.eccentricTime = metrics.2
        return updated
    }

    return FormFitCSVAnalysis(trimmedRows: rows, repetitions: repetitions)
}

func parseFormFitCSV(_ text: String) throws -> [SessionCSVRow] {
    var lines = text.components(separatedBy: .newlines)
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
        lines.removeLast()
    }

    guard let headerLine = lines.first else {
        throw FormFitCSVError.missingOrInvalidHeader
    }

    let headerFields = splitCSVLine(headerLine).map { $0.lowercased() }
    var indexByName: [String: Int] = [:]
    for (index, name) in headerFields.enumerated() {
        indexByName[name] = index
    }

    let missing = requiredCSVColumnNames.filter { indexByName[$0] == nil }
    if !missing.isEmpty {
        throw FormFitCSVError.missingRequiredColumns(missing: missing)
    }

    func field(_ row: [String], _ name: String) -> Double? {
        guard let index = indexByName[name], index < row.count else { return nil }
        return Double(row[index].trimmingCharacters(in: .whitespaces))
    }

    var rows: [SessionCSVRow] = []
    rows.reserveCapacity(max(lines.count - 1, 0))

    for line in lines.dropFirst() {
        let fields = splitCSVLine(line)
        guard
            let t = field(fields, "t"),
            let ax = field(fields, "ax"),
            let ay = field(fields, "ay"),
            let az = field(fields, "az"),
            let gx = field(fields, "gx"),
            let gy = field(fields, "gy"),
            let gz = field(fields, "gz"),
            let roll = field(fields, "roll"),
            let pitch = field(fields, "pitch"),
            let yaw = field(fields, "yaw")
        else {
            continue
        }

        rows.append(
            SessionCSVRow(
                t: t,
                ax: ax,
                ay: ay,
                az: az,
                gx: gx,
                gy: gy,
                gz: gz,
                roll: roll,
                pitch: pitch,
                yaw: yaw
            )
        )
    }

    return rows
}

func trimTailUntilAccelQuiet(
    _ rows: [SessionCSVRow],
    magThreshold: Double = accelTailMagThreshold,
    quietRun: Int = accelTailQuietRunSamples,
    maxTrim: Int = accelTailMaxTrimSamples
) -> [SessionCSVRow] {
    if rows.isEmpty || maxTrim <= 0 {
        return rows
    }

    let count = rows.count
    if count < quietRun {
        return rows
    }

    func suffixQuiet(end: Int) -> Bool {
        let start = end - quietRun
        for index in start..<end {
            let row = rows[index]
            if abs(row.ax) >= magThreshold ||
                abs(row.ay) >= magThreshold ||
                abs(row.az) >= magThreshold {
                return false
            }
        }
        return true
    }

    let minEnd = max(quietRun, count - maxTrim)
    var end = count
    while end >= minEnd {
        if suffixQuiet(end: end) {
            return Array(rows[..<end])
        }
        end -= 1
    }

    let fallbackEnd = max(0, count - maxTrim)
    return Array(rows[..<fallbackEnd])
}

func split_reps(repetition: Repetition, sampleRate: Double = defaultSampleRate) -> [Repetition] {
    splitReps(repetition, sampleRate: sampleRate)
}

func splitReps(_ repetition: Repetition, sampleRate: Double = defaultSampleRate) -> [Repetition] {
    if repetition.samples.count < minRepSamples {
        return [repetition]
    }

    let values = orientationValues(repetition.samples)
    let axisValues = smoothed(values.roll, window: 5)
    guard axisValues.count >= minRepSamples else {
        return [repetition]
    }

    let sortedValues = axisValues.sorted()
    let nSorted = sortedValues.count
    let robustLo = sortedValues[max(0, Int(Double(nSorted) * 0.02))]
    let robustHi = sortedValues[min(nSorted - 1, Int(Double(nSorted) * 0.98))]
    let totalRange = max(robustHi - robustLo, valueRange(axisValues) * 0.3)

    if totalRange <= 0 {
        return [repetition]
    }

    var (peaks, valleys) = findExtrema(axisValues)
    if valleys.isEmpty {
        return [repetition]
    }

    let minAmplitude = max(0.07, totalRange * 0.18)
    let startRoll = axisValues[0]
    let firstDeepValley = valleys.first { valleyIndex in
        (startRoll - axisValues[valleyIndex]) > minAmplitude * 0.4
    }

    if let firstDeepValley {
        let noisePeaks = peaks.filter { peakIndex in
            peakIndex < firstDeepValley &&
                abs(axisValues[peakIndex] - startRoll) < totalRange * 0.03
        }

        if !noisePeaks.isEmpty {
            let valleyFloor = axisValues[firstDeepValley]
            let recoveryThreshold = valleyFloor + totalRange * 0.10
            let firstRecovery = peaks.first { peakIndex in
                peakIndex > firstDeepValley && axisValues[peakIndex] > recoveryThreshold
            }

            if let firstRecovery {
                peaks = peaks.filter { $0 >= firstRecovery }
                peaks = [0] + peaks
            }
        }
    }

    if peaks.isEmpty {
        return [repetition]
    }

    let selectedSegments = segmentsBetweenAnchors(
        anchors: peaks,
        opposite: valleys,
        values: axisValues,
        minAmplitude: minAmplitude
    )

    if selectedSegments.isEmpty {
        return [repetition]
    }

    let count = repetition.samples.count
    var results: [Repetition] = []

    for segment in selectedSegments {
        let (trimmedStart, trimmedEnd) = trimSegment(segment, values: axisValues)
        let lower = max(0, trimmedStart)
        let upper = min(count - 1, trimmedEnd)

        if upper <= lower || (upper - lower + 1) < minRepSamples {
            continue
        }

        let slice = Array(repetition.samples[lower...upper])
        let dt = sampleTime(for: repetition.samples[lower], index: lower, sampleRate: sampleRate)
        results.append(
            Repetition(
                samples: slice,
                rangeOfMotion: nil,
                concentricTime: nil,
                eccentricTime: nil,
                timestamp: repetition.timestamp.addingTimeInterval(dt)
            )
        )
    }

    if results.isEmpty {
        return [repetition]
    }

    let rollGapThreshold = 0.40
    let timeGapThreshold = 0.50
    let rollCenterThreshold = 0.4

    var merged: [Repetition] = [results[0]]
    for repetition in results.dropFirst() {
        var previous = merged[merged.count - 1]
        let nextStartTime = sampleTime(for: repetition.samples[0], index: 0, sampleRate: sampleRate)
        let previousEndTime = sampleTime(
            for: previous.samples[previous.samples.count - 1],
            index: previous.samples.count - 1,
            sampleRate: sampleRate
        )
        let timeGap = nextStartTime - previousEndTime
        let rollGap = abs(repetition.samples[0].roll - previous.samples[previous.samples.count - 1].roll)

        if timeGap <= timeGapThreshold && rollGap <= rollGapThreshold {
            let boundaryRoll = 0.5 * (
                previous.samples[previous.samples.count - 1].roll +
                    repetition.samples[0].roll
            )

            if abs(boundaryRoll) < rollCenterThreshold {
                merged.append(repetition)
                continue
            }

            previous = Repetition(
                samples: previous.samples + repetition.samples,
                rangeOfMotion: previous.rangeOfMotion,
                concentricTime: previous.concentricTime,
                eccentricTime: previous.eccentricTime,
                timestamp: previous.timestamp
            )
            merged[merged.count - 1] = previous
            continue
        }

        merged.append(repetition)
    }

    let minRepDepth = 0.15
    merged = merged.filter { repetition in
        guard let firstRoll = repetition.samples.first?.roll else { return false }
        let minRoll = repetition.samples.map(\.roll).min() ?? firstRoll
        return (firstRoll - minRoll) >= minRepDepth
    }

    if merged.isEmpty {
        return [repetition]
    }

    return merged
}

func calculate_metrics(
    repetition: Repetition,
    sampleRate: Double = defaultSampleRate
) -> (Double, Double, Double) {
    let rolls = repetition.samples.map(\.roll)
    guard rolls.count >= 2,
          let minRoll = rolls.min(),
          let maxRoll = rolls.max(),
          let valleyIndex = rolls.firstIndex(of: minRoll)
    else {
        return (0, 0, 0)
    }

    let startTime = sampleTime(for: repetition.samples[0], index: 0, sampleRate: sampleRate)
    let valleyTime = sampleTime(
        for: repetition.samples[valleyIndex],
        index: valleyIndex,
        sampleRate: sampleRate
    )
    let endTime = sampleTime(
        for: repetition.samples[repetition.samples.count - 1],
        index: repetition.samples.count - 1,
        sampleRate: sampleRate
    )

    let rangeOfMotion = (maxRoll - minRoll) * (180.0 / .pi)
    let concentricTime = max(0, valleyTime - startTime)
    let eccentricTime = max(0, endTime - valleyTime)

    return (rangeOfMotion, concentricTime, eccentricTime)
}

func eccentricTime(rep: Repetition, sampleRate: Double = defaultSampleRate) -> Double {
    let metrics = calculate_metrics(repetition: rep, sampleRate: sampleRate)
    return metrics.2
}

func eccentricScore(duration: Double) -> EccentricScore {
    if duration >= 3.0 {
        return .good
    }
    if duration >= 2.0 {
        return .slightlyFast
    }
    return .tooFast
}

// MARK: - File resolution

private func resolveCSVURL(_ fileName: String) throws -> URL {
    let inputURL = URL(fileURLWithPath: fileName)
    if inputURL.isFileURL,
       FileManager.default.fileExists(atPath: inputURL.path) {
        return inputURL
    }

    let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: cwdURL.path) {
        return cwdURL
    }

    let ns = fileName as NSString
    let stem = ns.deletingPathExtension
    let ext = ns.pathExtension.isEmpty ? "csv" : ns.pathExtension
    if let bundleURL = Bundle.main.url(forResource: stem, withExtension: ext) {
        return bundleURL
    }

    throw FormFitCSVError.invalidCSVPath(fileName)
}

// MARK: - Helpers

private struct OrientationValues {
    var roll: [Double] = []
    var pitch: [Double] = []
    var yaw: [Double] = []
}

private typealias Segment = (start: Int, peak: Int, end: Int)

private func orientationValues(_ samples: [Sample]) -> OrientationValues {
    var result = OrientationValues()
    result.roll.reserveCapacity(samples.count)
    result.pitch.reserveCapacity(samples.count)
    result.yaw.reserveCapacity(samples.count)

    for sample in samples {
        result.roll.append(sample.roll)
        result.pitch.append(sample.pitch)
        result.yaw.append(sample.yaw)
    }

    return result
}

private func valueRange(_ values: [Double]) -> Double {
    guard let maxValue = values.max(), let minValue = values.min() else { return 0 }
    return maxValue - minValue
}

private func smoothed(_ values: [Double], window: Int = 5) -> [Double] {
    if values.isEmpty || window <= 1 {
        return values
    }

    let halfWindow = max(1, window / 2)
    var output: [Double] = []
    output.reserveCapacity(values.count)

    for index in values.indices {
        let start = max(0, index - halfWindow)
        let end = min(values.count - 1, index + halfWindow)
        let chunk = values[start...end]
        let sum = chunk.reduce(0, +)
        output.append(sum / Double(chunk.count))
    }

    return output
}

private func findExtrema(_ values: [Double]) -> (peaks: [Int], valleys: [Int]) {
    if values.count < 3 {
        return ([], [])
    }

    var peaks: [Int] = []
    var valleys: [Int] = []

    for index in 1..<(values.count - 1) {
        let previous = values[index - 1]
        let current = values[index]
        let next = values[index + 1]

        if current > previous && current >= next {
            peaks.append(index)
        }

        if current < previous && current <= next {
            valleys.append(index)
        }
    }

    return (peaks, valleys)
}

private func segmentsBetweenAnchors(
    anchors: [Int],
    opposite: [Int],
    values: [Double],
    minAmplitude: Double
) -> [Segment] {
    if anchors.count < 2 {
        return []
    }

    var segments: [Segment] = []
    var anchorIndex = 0

    while anchorIndex < anchors.count - 1 {
        let start = anchors[anchorIndex]
        var found = false
        let searchUpper = min(anchorIndex + 4, anchors.count)

        for nextIndex in (anchorIndex + 1)..<searchUpper {
            let end = anchors[nextIndex]
            if end <= start + 1 {
                continue
            }

            let inside = opposite.filter { start < $0 && $0 < end }
            if inside.isEmpty {
                continue
            }

            let primary = inside.max { left, right in
                abs(values[left] - values[start]) < abs(values[right] - values[start])
            }!

            let baseline = (values[start] + values[end]) / 2
            let amplitude = abs(values[primary] - baseline)
            if amplitude >= minAmplitude {
                segments.append((start, primary, end))
                anchorIndex = nextIndex
                found = true
                break
            }
        }

        if !found {
            anchorIndex += 1
        }
    }

    return segments
}

private func trimSegment(_ segment: Segment, values: [Double]) -> (Int, Int) {
    var start = segment.start
    var end = segment.end
    let peak = segment.peak
    let baseline = (values[start] + values[end]) / 2
    let fullAmplitude = abs(values[peak] - baseline)
    let margin = max(0.03, fullAmplitude * 0.15)

    while start < peak && abs(values[start] - baseline) < margin {
        start += 1
    }

    while end > peak && abs(values[end] - baseline) < margin {
        end -= 1
    }

    return (start, end)
}

private func sampleTime(for sample: Sample, index: Int, sampleRate: Double) -> Double {
    if let relativeTime = sample.relativeTime {
        return relativeTime
    }

    guard sampleRate > 0 else { return 0 }
    return Double(index) / sampleRate
}

/// Splits a simple comma-separated line. FormFit exports do not contain quoted commas.
private func splitCSVLine(_ line: String) -> [String] {
    line
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}
