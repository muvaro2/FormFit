import Foundation

// MARK: - Constants

let defaultSampleRate: Double = 100.0
let minRepSamples: Int = 5
let accelTailMagThreshold: Double = 0.5
let accelTailQuietRunSamples: Int = 50
let accelTailMaxTrimSamples: Int = 300

// MARK: - Data structures

struct Sample: Equatable {
    var roll: Double
    var pitch: Double
    var yaw: Double
    var t: Double
}

struct Repetition: Equatable {
    var samples: [Sample]
    var rangeOfMotion: Double?
    var concentricTime: Double?
    var eccentricTime: Double?
    var t: Date
}

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
        .tooFast: "#e8675a",
    ]

    private static let labelByScore: [EccentricScore: String] = [
        .good: "Good eccentric",
        .slightlyFast: "Eccentric slightly too fast",
        .tooFast: "Eccentric too fast",
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

    var errorDescription: String? {
        switch self {
        case let .fileReadFailed(url, err):
            return "Could not read CSV at \(url.path): \(err?.localizedDescription ?? "unknown")"
        case .missingOrInvalidHeader:
            return "CSV is missing a header row or it could not be parsed."
        case let .missingRequiredColumns(missing):
            return "CSV header is missing columns: \(missing.joined(separator: ", "))"
        }
    }
}

// MARK: - CSV load

private let requiredCSVColumnNames = [
    "t", "ax", "ay", "az", "gx", "gy", "gz", "roll", "pitch", "yaw",
]

/// Parses session CSV text. Malformed data lines are skipped (Python `read_csv` is strict; we skip bad lines for robustness).
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
    for (i, name) in headerFields.enumerated() {
        indexByName[name] = i
    }

    var missing: [String] = []
    for name in requiredCSVColumnNames {
        if indexByName[name] == nil {
            missing.append(name)
        }
    }
    if !missing.isEmpty {
        throw FormFitCSVError.missingRequiredColumns(missing: missing)
    }

    func field(_ row: [String], _ name: String) -> Double? {
        guard let i = indexByName[name], i < row.count else { return nil }
        return Double(row[i].trimmingCharacters(in: .whitespaces))
    }

    var rows: [SessionCSVRow] = []
    rows.reserveCapacity(lines.count - 1)

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
                t: t, ax: ax, ay: ay, az: az, gx: gx, gy: gy, gz: gz,
                roll: roll, pitch: pitch, yaw: yaw
            )
        )
    }

    return rows
}

/// Splits a simple comma-separated line (no quoted commas in FormFit exports).
private func splitCSVLine(_ line: String) -> [String] {
    line.split(separator: ",", omittingEmptySubsequences: false).map {
        String($0).trimmingCharacters(in: .whitespaces)
    }
}

func analyzeFormFitCSV(at url: URL, sampleRate: Double = defaultSampleRate, sessionStart: Date = Date()) throws -> FormFitCSVAnalysis {
    let text: String
    do {
        text = try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw FormFitCSVError.fileReadFailed(url: url, underlying: error)
    }

    var rows = try parseFormFitCSV(text)
    rows = trimTailUntilAccelQuiet(rows)

    let samples: [Sample] = rows.map {
        Sample(roll: $0.roll, pitch: $0.pitch, yaw: $0.yaw, t: $0.t)
    }
    let fullRep = Repetition(
        samples: samples,
        rangeOfMotion: nil,
        concentricTime: nil,
        eccentricTime: nil,
        t: sessionStart
    )
    let reps = splitReps(fullRep, sampleRate: sampleRate)

    return FormFitCSVAnalysis(trimmedRows: rows, repetitions: reps)
}

// MARK: - Accelerometer tail trim

func trimTailUntilAccelQuiet(
    _ rows: [SessionCSVRow],
    magThreshold: Double = accelTailMagThreshold,
    quietRun: Int = accelTailQuietRunSamples,
    maxTrim: Int = accelTailMaxTrimSamples
) -> [SessionCSVRow] {
    if rows.isEmpty || maxTrim <= 0 {
        return rows
    }
    let n = rows.count
    if n < quietRun {
        return rows
    }

    func suffixQuiet(end: Int) -> Bool {
        let start = end - quietRun
        for i in start..<end {
            let r = rows[i]
            if abs(r.ax) >= magThreshold || abs(r.ay) >= magThreshold || abs(r.az) >= magThreshold {
                return false
            }
        }
        return true
    }

    let minEnd = max(quietRun, n - maxTrim)
    var end = n
    while end >= minEnd {
        if suffixQuiet(end: end) {
            return Array(rows[..<end])
        }
        end -= 1
    }

    let fallbackEnd = max(0, n - maxTrim)
    return Array(rows[..<fallbackEnd])
}

// MARK: - Orientation helpers (split_reps)

private struct OrientationValues {
    var roll: [Double] = []
    var pitch: [Double] = []
    var yaw: [Double] = []
}

private typealias Segment = (start: Int, peak: Int, end: Int)

func splitReps(_ repetition: Repetition, sampleRate: Double = defaultSampleRate) -> [Repetition] {
    let values = orientationValues(repetition.samples)

    if repetition.samples.count < minRepSamples {
        return [repetition]
    }

    let axisValues = smoothed(values.roll, window: 5)

    let sortedVals = axisValues.sorted()
    let nSorted = sortedVals.count
    let robustLo = sortedVals[max(0, Int(Double(nSorted) * 0.02))]
    let robustHi = sortedVals[min(nSorted - 1, Int(Double(nSorted) * 0.98))]
    let totalRange = max(robustHi - robustLo, valueRange(axisValues) * 0.3)

    if axisValues.count < minRepSamples || totalRange <= 0 {
        return [repetition]
    }

    var (peaks, valleys) = findExtrema(axisValues)

    if valleys.isEmpty {
        return [repetition]
    }

    let minAmplitude = max(0.07, totalRange * 0.18)

    let startRoll = axisValues[0]
    let firstDeepValley = valleys.first { v in
        (startRoll - axisValues[v]) > minAmplitude * 0.4
    }

    if let firstDeepValley {
        let noisePeaks = peaks.filter { p in
            p < firstDeepValley && abs(axisValues[p] - startRoll) < totalRange * 0.03
        }
        if !noisePeaks.isEmpty {
            let valleyFloor = axisValues[firstDeepValley]
            let recoveryThreshold = valleyFloor + totalRange * 0.10
            let firstRecovery = peaks.first { p in
                p > firstDeepValley && axisValues[p] > recoveryThreshold
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

    let valleySegments = segmentsBetweenAnchors(
        anchors: peaks,
        opposite: valleys,
        values: axisValues,
        minAmplitude: minAmplitude
    )
    let selected = valleySegments

    if selected.isEmpty {
        return [repetition]
    }

    var result: [Repetition] = []
    let n = repetition.samples.count

    for segment in selected {
        let (trimmedStart, trimmedEnd) = trimSegment(segment, values: axisValues)
        let lower = max(0, trimmedStart)
        let upper = min(n - 1, trimmedEnd)

        if upper <= lower || (upper - lower + 1) < minRepSamples {
            continue
        }

        let slice = Array(repetition.samples[lower ... upper])
        let dt = sampleRate > 0 ? Double(lower) / sampleRate : 0.0
        result.append(
            Repetition(
                samples: slice,
                rangeOfMotion: nil,
                concentricTime: nil,
                eccentricTime: nil,
                t: repetition.t.addingTimeInterval(dt)
            )
        )
    }

    if result.isEmpty {
        return [repetition]
    }

    let rollGapThreshold = 0.40
    let timeGapThreshold = 0.50
    let rollCenterThreshold = 0.4

    var merged: [Repetition] = [result[0]]

    for rep in result.dropFirst() {
        var prev = merged[merged.count - 1]
        let tGap = rep.samples[0].t - prev.samples[prev.samples.count - 1].t
        let rollGap = abs(rep.samples[0].roll - prev.samples[prev.samples.count - 1].roll)

        if tGap <= timeGapThreshold && rollGap <= rollGapThreshold {
            let boundaryRoll = 0.5 * (prev.samples[prev.samples.count - 1].roll + rep.samples[0].roll)
            if abs(boundaryRoll) < rollCenterThreshold {
                merged.append(rep)
                continue
            }

            merged[merged.count - 1] = Repetition(
                samples: prev.samples + rep.samples,
                rangeOfMotion: prev.rangeOfMotion,
                concentricTime: prev.concentricTime,
                eccentricTime: prev.eccentricTime,
                t: prev.t
            )
            continue
        }

        merged.append(rep)
    }

    let minRepDepth = 0.15
    merged = merged.filter { r in
        let minRoll = r.samples.map(\.roll).min() ?? r.samples[0].roll
        return (r.samples[0].roll - minRoll) >= minRepDepth
    }

    if merged.isEmpty {
        return [repetition]
    }

    return merged
}

private func orientationValues(_ samples: [Sample]) -> OrientationValues {
    var result = OrientationValues()
    for s in samples {
        result.roll.append(s.roll)
        result.pitch.append(s.pitch)
        result.yaw.append(s.yaw)
    }
    return result
}

private func valueRange(_ values: [Double]) -> Double {
    guard let mx = values.max(), let mn = values.min() else { return 0 }
    return mx - mn
}

private func smoothed(_ values: [Double], window: Int = 5) -> [Double] {
    if values.isEmpty || window <= 1 {
        return values
    }
    let half = max(1, window / 2)
    var out: [Double] = []
    out.reserveCapacity(values.count)
    for i in 0..<values.count {
        let start = max(0, i - half)
        let end = min(values.count - 1, i + half)
        let chunk = values[start ... end]
        let sum = chunk.reduce(0, +)
        out.append(sum / Double(chunk.count))
    }
    return out
}

private func findExtrema(_ values: [Double]) -> (peaks: [Int], valleys: [Int]) {
    if values.count < 3 {
        return ([], [])
    }
    var peaks: [Int] = []
    var valleys: [Int] = []
    for i in 1..<(values.count - 1) {
        let prev = values[i - 1]
        let cur = values[i]
        let nxt = values[i + 1]
        if cur > prev && cur >= nxt {
            peaks.append(i)
        }
        if cur < prev && cur <= nxt {
            valleys.append(i)
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
    var i = 0
    while i < anchors.count - 1 {
        let start = anchors[i]
        var found = false
        let jUpper = min(i + 4, anchors.count)
        for j in (i + 1)..<jUpper {
            let end = anchors[j]
            if end <= start + 1 {
                continue
            }
            let inside = opposite.filter { start < $0 && $0 < end }
            if inside.isEmpty {
                continue
            }
            let primary = inside.max(by: { abs(values[$0] - values[start]) < abs(values[$1] - values[start]) })!
            let baseline = (values[start] + values[end]) / 2
            let amplitude = abs(values[primary] - baseline)
            if amplitude >= minAmplitude {
                segments.append((start, primary, end))
                i = j
                found = true
                break
            }
        }
        if !found {
            i += 1
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

// MARK: - Eccentric scoring

func eccentricTime(rep: Repetition) -> Double {
    let rolls = rep.samples.map(\.roll)
    guard let minRoll = rolls.min(),
          let valleyIdx = rolls.firstIndex(of: minRoll)
    else {
        return 0
    }
    return rep.samples[rep.samples.count - 1].t - rep.samples[valleyIdx].t
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
