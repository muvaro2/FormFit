import Foundation
import CoreML

struct Sample: Codable {
    var accelerationX: Float
    var accelerationY: Float
    var accelerationZ: Float

    var gyroX: Float
    var gyroY: Float
    var gyroZ: Float

    var roll: Float
    var pitch: Float
    var yaw: Float

    var flattenedChannels: [Float] {
        [
            accelerationX, accelerationY, accelerationZ,
            gyroX, gyroY, gyroZ,
            roll, pitch, yaw
        ]
    }
}

struct Repetition: Codable {
    var samples: [Sample]
    var rangeOfMotion: Float?
    var concentricTime: Float?
    var eccentricTime: Float?
    var timestamp: Date
}

struct ActivitySet: Codable {
    var repetitions: [Repetition]
    var timestamp: Date
}

typealias sample = Sample
typealias repetition = Repetition
typealias activity_set = ActivitySet

private enum MotionDataError: Error {
    case emptyInput
    case invalidCSVPath(String)
    case noSampleColumns
}

private struct ParsedCSVData {
    var samples: [Sample]
    var timestamps: [Double]
}

private enum OrientationAxis: CaseIterable {
    case roll
    case pitch
    case yaw
}

private let defaultSampleRate: Float = 50.0
private let minRepSamples = 8

func flatten(activity_set set: ActivitySet) throws -> MLMultiArray {
    let allSamples = set.repetitions.flatMap { $0.samples }
    let channelsPerSample = 9

    let shape: [NSNumber] = [NSNumber(value: allSamples.count), NSNumber(value: channelsPerSample)]
    let array = try MLMultiArray(shape: shape, dataType: .float32)

    for sampleIndex in 0..<allSamples.count {
        let channels = allSamples[sampleIndex].flattenedChannels
        for channelIndex in 0..<channelsPerSample {
            let linearIndex = sampleIndex * channelsPerSample + channelIndex
            array[linearIndex] = NSNumber(value: channels[channelIndex])
        }
    }

    return array
}

func unpack_csv(_ fileName: String, sampleRate: Float = defaultSampleRate) throws -> ActivitySet {
    let csvURL = try resolveCSVURL(fileName)
    let raw = try String(contentsOf: csvURL, encoding: .utf8)
    let parsedData = try parseCSVData(from: raw)
    let parsedSamples = parsedData.samples

    guard !parsedSamples.isEmpty else { throw MotionDataError.emptyInput }
    let inferredSampleRate = estimateSampleRate(from: parsedData.timestamps) ?? sampleRate
    let baseTimestamp = Date()

    let initialRep = Repetition(
        samples: parsedSamples,
        rangeOfMotion: nil,
        concentricTime: nil,
        eccentricTime: nil,
        timestamp: baseTimestamp
    )

    let split = split_reps(repetition: initialRep, sampleRate: inferredSampleRate)
    let metricized: [Repetition] = split.map { rep in
        var updated = rep
        let (rom, conc, ecc) = calculate_metrics(repetition: rep, sampleRate: inferredSampleRate)
        updated.rangeOfMotion = rom
        updated.concentricTime = conc
        updated.eccentricTime = ecc
        return updated
    }

    return ActivitySet(repetitions: metricized, timestamp: baseTimestamp)
}

func split_reps(repetition r: Repetition, sampleRate: Float = defaultSampleRate) -> [Repetition] {
    let values = orientationValues(from: r.samples)
    guard values.count >= minRepSamples else { return [r] }

    // Rep segmentation should rely on yaw/roll for this exercise, not pitch.
    let dominant = dominantAxis(values, allowedAxes: [.roll, .yaw])
    let axisValues = smoothed(values[dominant] ?? [], window: 5)
    let totalRange = valueRange(axisValues)

    guard axisValues.count >= minRepSamples, totalRange > 0 else { return [r] }

    let extrema = findExtrema(in: axisValues)
    if extrema.peaks.isEmpty || extrema.valleys.count < 2 {
        return [r]
    }

    let valleySegments = segmentsBetweenAnchors(
        anchors: extrema.valleys,
        opposite: extrema.peaks,
        values: axisValues,
        minAmplitude: max(0.08, totalRange * 0.18)
    )

    let peakSegments = segmentsBetweenAnchors(
        anchors: extrema.peaks,
        opposite: extrema.valleys,
        values: axisValues,
        minAmplitude: max(0.08, totalRange * 0.18)
    )

    let selectedSegments = valleySegments.count >= peakSegments.count ? valleySegments : peakSegments
    if selectedSegments.isEmpty { return [r] }

    let repetitions: [Repetition] = selectedSegments.compactMap { segment in
        let trimmed = trimSegment(segment, values: axisValues)
        let lower = max(0, trimmed.start)
        let upper = min(r.samples.count - 1, trimmed.end)

        guard upper > lower, (upper - lower + 1) >= minRepSamples else { return nil }

        let samples = Array(r.samples[lower...upper])
        let dt = sampleRate > 0 ? Double(lower) / Double(sampleRate) : 0
        return Repetition(
            samples: samples,
            rangeOfMotion: nil,
            concentricTime: nil,
            eccentricTime: nil,
            timestamp: r.timestamp.addingTimeInterval(dt)
        )
    }

    return repetitions.isEmpty ? [r] : repetitions
}

func calculate_metrics(repetition r: Repetition, sampleRate: Float = defaultSampleRate) -> (Float, Float, Float) {
    guard r.samples.count >= 2 else { return (0, 0, 0) }

    let values = orientationValues(from: r.samples)
    let dominant = dominantAxis(values, allowedAxes: [.roll, .yaw])
    guard let axisValues = values[dominant], !axisValues.isEmpty else { return (0, 0, 0) }

    let baseline = (axisValues.first! + axisValues.last!) / 2

    var peakIndex = 0
    var peakDelta: Float = 0

    for i in axisValues.indices {
        let d = abs(axisValues[i] - baseline)
        if d > peakDelta {
            peakDelta = d
            peakIndex = i
        }
    }

    let romDegrees = peakDelta * (180.0 / .pi)

    let safeSampleRate = sampleRate > 0 ? sampleRate : defaultSampleRate
    let concentricSamples = max(0, peakIndex)
    let eccentricSamples = max(0, (axisValues.count - 1) - peakIndex)

    let concentricTime = Float(concentricSamples) / safeSampleRate
    let eccentricTime = Float(eccentricSamples) / safeSampleRate

    return (romDegrees, concentricTime, eccentricTime)
}

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

    throw MotionDataError.invalidCSVPath(fileName)
}

private func parseCSVData(from csvText: String) throws -> ParsedCSVData {
    let rawLines = csvText
        .components(separatedBy: CharacterSet.newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !rawLines.isEmpty else { return ParsedCSVData(samples: [], timestamps: []) }

    let firstColumns = splitCSVLine(rawLines[0]).map(normalizeColumnName)
    let hasHeader = firstColumns.contains { containsAnyLetters($0) }

    let dataStart = hasHeader ? 1 : 0
    let headerMap = hasHeader ? indexMap(from: firstColumns) : [:]

    var samples: [Sample] = []
    var timestamps: [Double] = []
    for i in dataStart..<rawLines.count {
        let row = splitCSVLine(rawLines[i])
        if row.isEmpty { continue }

        if let parsed = parseSampleRow(row, headerMap: headerMap) {
            samples.append(parsed.sample)
            if let ts = parsed.timestamp {
                timestamps.append(ts)
            }
        }
    }

    if samples.isEmpty { throw MotionDataError.noSampleColumns }
    return ParsedCSVData(samples: samples, timestamps: timestamps)
}

private func parseSampleRow(_ row: [String], headerMap: [String: Int]) -> (sample: Sample, timestamp: Double?)? {
    if headerMap.isEmpty {
        let numeric = row.compactMap(parseFloat)
        if numeric.count >= 10 {
            let hasTimestampAndIndex = numeric.count >= 11
            let offset = hasTimestampAndIndex ? 2 : 1
            let ts = hasTimestampAndIndex ? Double(numeric[1]) : nil
            return (
                sample: Sample(
                    accelerationX: numeric[offset + 0],
                    accelerationY: numeric[offset + 1],
                    accelerationZ: numeric[offset + 2],
                    gyroX: numeric[offset + 3],
                    gyroY: numeric[offset + 4],
                    gyroZ: numeric[offset + 5],
                    roll: numeric[offset + 6],
                    pitch: numeric[offset + 7],
                    yaw: numeric[offset + 8]
                ),
                timestamp: ts
            )
        }

        if numeric.count >= 9 {
            return (
                sample: Sample(
                    accelerationX: numeric[0],
                    accelerationY: numeric[1],
                    accelerationZ: numeric[2],
                    gyroX: numeric[3],
                    gyroY: numeric[4],
                    gyroZ: numeric[5],
                    roll: numeric[6],
                    pitch: numeric[7],
                    yaw: numeric[8]
                ),
                timestamp: nil
            )
        }
        return nil
    }

    func value(_ keys: [String]) -> Float? {
        for key in keys {
            if let idx = headerMap[key], idx < row.count, let v = parseFloat(row[idx]) {
                return v
            }
        }
        return nil
    }

    guard
        let ax = value(["accelerationx", "accx", "ax"]),
        let ay = value(["accelerationy", "accy", "ay"]),
        let az = value(["accelerationz", "accz", "az"]),
        let gx = value(["gyrox", "gx"]),
        let gy = value(["gyroy", "gy"]),
        let gz = value(["gyroz", "gz"]),
        let roll = value(["roll", "orientationroll"]),
        let pitch = value(["pitch", "orientationpitch"]),
        let yaw = value(["yaw", "orientationyaw"])
    else {
        return nil
    }

    let timestamp = value(["timestamp", "time", "t"]).map(Double.init)
    return (
        sample: Sample(
            accelerationX: ax,
            accelerationY: ay,
            accelerationZ: az,
            gyroX: gx,
            gyroY: gy,
            gyroZ: gz,
            roll: roll,
            pitch: pitch,
            yaw: yaw
        ),
        timestamp: timestamp
    )
}

private func estimateSampleRate(from timestamps: [Double]) -> Float? {
    guard timestamps.count >= 3 else { return nil }
    var deltas: [Double] = []
    deltas.reserveCapacity(timestamps.count - 1)

    for i in 1..<timestamps.count {
        let delta = timestamps[i] - timestamps[i - 1]
        if delta > 0, delta.isFinite {
            deltas.append(delta)
        }
    }

    guard !deltas.isEmpty else { return nil }
    let sorted = deltas.sorted()
    let median = sorted[sorted.count / 2]
    guard median > 0 else { return nil }

    let rate = 1.0 / median
    if !rate.isFinite || rate <= 0 { return nil }
    return Float(rate)
}

private func orientationValues(from samples: [Sample]) -> [OrientationAxis: [Float]] {
    var roll: [Float] = []
    var pitch: [Float] = []
    var yaw: [Float] = []

    roll.reserveCapacity(samples.count)
    pitch.reserveCapacity(samples.count)
    yaw.reserveCapacity(samples.count)

    for s in samples {
        roll.append(s.roll)
        pitch.append(s.pitch)
        yaw.append(s.yaw)
    }

    return [.roll: roll, .pitch: pitch, .yaw: yaw]
}

private func dominantAxis(_ values: [OrientationAxis: [Float]]) -> OrientationAxis {
    dominantAxis(values, allowedAxes: OrientationAxis.allCases)
}

private func dominantAxis(
    _ values: [OrientationAxis: [Float]],
    allowedAxes: [OrientationAxis]
) -> OrientationAxis {
    var bestAxis: OrientationAxis = allowedAxes.first ?? .pitch
    var bestRange: Float = -Float.infinity

    for axis in allowedAxes {
        let current = valueRange(values[axis] ?? [])
        if current > bestRange {
            bestRange = current
            bestAxis = axis
        }
    }

    return bestAxis
}

private func valueRange(_ values: [Float]) -> Float {
    guard let minV = values.min(), let maxV = values.max() else { return 0 }
    return maxV - minV
}

private func smoothed(_ values: [Float], window: Int) -> [Float] {
    guard !values.isEmpty, window > 1 else { return values }
    let half = max(1, window / 2)
    var out = Array(repeating: Float(0), count: values.count)

    for i in values.indices {
        let start = max(0, i - half)
        let end = min(values.count - 1, i + half)
        let count = end - start + 1
        let sum = values[start...end].reduce(Float(0), +)
        out[i] = sum / Float(count)
    }

    return out
}

private func findExtrema(in values: [Float]) -> (peaks: [Int], valleys: [Int]) {
    guard values.count >= 3 else { return ([], []) }
    var peaks: [Int] = []
    var valleys: [Int] = []

    for i in 1..<(values.count - 1) {
        let prev = values[i - 1]
        let cur = values[i]
        let next = values[i + 1]

        if cur > prev && cur >= next {
            peaks.append(i)
        }
        if cur < prev && cur <= next {
            valleys.append(i)
        }
    }

    return (peaks, valleys)
}

private func segmentsBetweenAnchors(
    anchors: [Int],
    opposite: [Int],
    values: [Float],
    minAmplitude: Float
) -> [(start: Int, peak: Int, end: Int)] {
    guard anchors.count >= 2 else { return [] }
    var segments: [(start: Int, peak: Int, end: Int)] = []

    for i in 0..<(anchors.count - 1) {
        let start = anchors[i]
        let end = anchors[i + 1]
        if end <= start + 1 { continue }

        let inside = opposite.filter { $0 > start && $0 < end }
        guard let primary = inside.max(by: { abs(values[$0] - values[start]) < abs(values[$1] - values[start]) }) else {
            continue
        }

        let left = values[start]
        let right = values[end]
        let baseline = (left + right) / 2
        let amplitude = abs(values[primary] - baseline)

        if amplitude >= minAmplitude {
            segments.append((start: start, peak: primary, end: end))
        }
    }

    return segments
}

private func trimSegment(_ segment: (start: Int, peak: Int, end: Int), values: [Float]) -> (start: Int, end: Int) {
    var start = segment.start
    var end = segment.end

    let baseline = (values[start] + values[end]) / 2
    let fullAmplitude = abs(values[segment.peak] - baseline)
    let margin = max(0.03, fullAmplitude * 0.15)

    while start < segment.peak && abs(values[start] - baseline) < margin {
        start += 1
    }

    while end > segment.peak && abs(values[end] - baseline) < margin {
        end -= 1
    }

    return (start: start, end: end)
}

private func splitCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false

    for ch in line {
        if ch == "\"" {
            inQuotes.toggle()
        } else if ch == "," && !inQuotes {
            fields.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
        } else {
            current.append(ch)
        }
    }

    fields.append(current.trimmingCharacters(in: .whitespaces))
    return fields
}

private func parseFloat(_ raw: String) -> Float? {
    let cleaned = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\"", with: "")

    if cleaned.isEmpty { return nil }
    return Float(cleaned)
}

private func normalizeColumnName(_ name: String) -> String {
    name
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: " ", with: "")
}

private func containsAnyLetters(_ s: String) -> Bool {
    s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
}

private func indexMap(from normalizedHeaders: [String]) -> [String: Int] {
    var map: [String: Int] = [:]
    for (idx, header) in normalizedHeaders.enumerated() where !header.isEmpty {
        map[header] = idx
    }
    return map
}
