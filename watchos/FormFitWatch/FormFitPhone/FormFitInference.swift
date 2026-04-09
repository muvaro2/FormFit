//
//  FormFitInference.swift
//  FormFitPhone
//
//  Runs the FormFitModel Core ML package on split repetitions and produces
//  per-rep 3-tuples and a single 0-100 workout score.
//
//  The Core ML model expects:
//    input  shape (1, 9, 128) float32  — ax, ay, az, gx, gy, gz, roll, pitch, yaw
//    output shape (1, 3)      float32  — sigmoid scores:
//                                         [elbow_hiking, shoulder_hiking, torso_twist]
//
//  Training applied `StandardScaler` per-rep-per-channel before slicing into
//  128-sample windows, so we replicate that normalization here.
//

import Foundation
import CoreML

struct RepInferenceResult {
    let elbowHiking: Double       // 0-1
    let shoulderHiking: Double    // 0-1
    let torsoTwist: Double        // 0-1
    let overallScore: Double      // 0-100, using CNN.py get_feedback formula

    var tuple: (Double, Double, Double) {
        (elbowHiking, shoulderHiking, torsoTwist)
    }
}

enum FormFitInferenceError: Error {
    case modelUnavailable
    case inferenceFailed(String)
    case emptyInput
}

final class FormFitInference {
    static let shared = FormFitInference()

    private let seqLen = 128
    private let channels = 9
    private let windowStride = 64     // 50% overlap, matches training sliding window

    // Loaded lazily so app launch isn't blocked if the model isn't in the bundle yet.
    private var _model: FormFitModel?
    private var loadAttempted = false

    private init() {}

    private func loadModelIfNeeded() -> FormFitModel? {
        if let model = _model { return model }
        if loadAttempted { return nil }
        loadAttempted = true

        let config = MLModelConfiguration()
        config.computeUnits = .all
        do {
            _model = try FormFitModel(configuration: config)
            return _model
        } catch {
            print("FormFitInference: failed to load FormFitModel — \(error.localizedDescription)")
            return nil
        }
    }

    /// Runs the model on every repetition in `activitySet` and returns per-rep
    /// results plus a single aggregated workout score (0-100).
    ///
    /// - Returns: tuple of (perRepResults, workoutScore). If the model cannot be
    ///   loaded, returns nil so the caller can fall back to a placeholder score.
    func scoreWorkout(_ activitySet: ActivitySet) -> (rep: [RepInferenceResult], workout: Int)? {
        guard let model = loadModelIfNeeded() else { return nil }
        guard !activitySet.repetitions.isEmpty else { return nil }

        var repResults: [RepInferenceResult] = []
        repResults.reserveCapacity(activitySet.repetitions.count)

        for rep in activitySet.repetitions {
            guard let result = scoreRepetition(rep, using: model) else { continue }
            repResults.append(result)
        }

        guard !repResults.isEmpty else { return nil }

        // Workout score = average of per-rep overall scores.
        let avg = repResults.reduce(0.0) { $0 + $1.overallScore } / Double(repResults.count)
        let workoutScore = max(0, min(100, Int(avg.rounded())))
        return (rep: repResults, workout: workoutScore)
    }

    // MARK: - Per-rep

    private func scoreRepetition(_ rep: Repetition, using model: FormFitModel) -> RepInferenceResult? {
        guard !rep.samples.isEmpty else { return nil }

        // 1. Build [samples x 9] normalized matrix (StandardScaler equivalent).
        let normalized = standardScale(samples: rep.samples)
        guard !normalized.isEmpty else { return nil }

        // 2. Produce one or more 128-sample windows and average predictions
        //    (matches how training data was built).
        let windows = makeWindows(from: normalized)
        guard !windows.isEmpty else { return nil }

        var sums: [Double] = [0, 0, 0]
        var runCount = 0

        for window in windows {
            guard let pred = runModel(model, window: window) else { continue }
            for i in 0..<3 { sums[i] += pred[i] }
            runCount += 1
        }

        guard runCount > 0 else { return nil }
        let avg = sums.map { $0 / Double(runCount) }

        let elbow = clamp01(avg[0])
        let shoulder = clamp01(avg[1])
        let torso = clamp01(avg[2])

        // 3. Combine with eccentric time into 0-100 overall score.
        //    Mirrors CNN.py get_feedback: 25 pts per metric + 25 pts for ecc time.
        let eccSeconds = rep.eccentricTime ?? 0
        let overall = computeOverallScore(
            elbow: elbow,
            shoulder: shoulder,
            torso: torso,
            eccentricTime: eccSeconds
        )

        return RepInferenceResult(
            elbowHiking: elbow,
            shoulderHiking: shoulder,
            torsoTwist: torso,
            overallScore: overall
        )
    }

    // MARK: - Normalization (StandardScaler equivalent)

    /// Returns an array of length `samples.count`, each element a [9] Float row,
    /// standardized per channel (zero mean, unit variance).
    private func standardScale(samples: [Sample]) -> [[Float]] {
        let n = samples.count
        guard n > 0 else { return [] }

        // Transpose: raw[channel][sampleIndex]
        var raw = Array(repeating: [Float](repeating: 0, count: n), count: channels)
        for (i, s) in samples.enumerated() {
            let row = s.flattenedChannels
            for c in 0..<channels {
                raw[c][i] = row[c]
            }
        }

        // Mean / std per channel.
        var means = [Float](repeating: 0, count: channels)
        var stds  = [Float](repeating: 1, count: channels)

        for c in 0..<channels {
            let col = raw[c]
            let mean = col.reduce(0, +) / Float(n)
            means[c] = mean

            var sq: Float = 0
            for v in col {
                let d = v - mean
                sq += d * d
            }
            // sklearn StandardScaler uses population std (divide by N)
            let variance = sq / Float(n)
            let std = variance > 0 ? sqrt(variance) : 1
            stds[c] = std
        }

        // Build normalized row-major output.
        var rows = Array(repeating: [Float](repeating: 0, count: channels), count: n)
        for i in 0..<n {
            for c in 0..<channels {
                rows[i][c] = (raw[c][i] - means[c]) / stds[c]
            }
        }
        return rows
    }

    // MARK: - Windowing

    /// Produces one or more 128-sample windows as channel-major [9][128] matrices.
    /// If the rep is shorter than 128 samples, a single zero-padded window is returned.
    /// Otherwise, sliding windows of 128 with stride 64 are returned.
    private func makeWindows(from normalizedRows: [[Float]]) -> [[[Float]]] {
        let n = normalizedRows.count

        if n < seqLen {
            // Pad with zeros at the end.
            var padded = normalizedRows
            while padded.count < seqLen {
                padded.append([Float](repeating: 0, count: channels))
            }
            return [transpose(padded)]
        }

        var windows: [[[Float]]] = []
        var start = 0
        while start + seqLen <= n {
            let slice = Array(normalizedRows[start..<(start + seqLen)])
            windows.append(transpose(slice))
            start += windowStride
        }

        // Guarantee at least one window even if stride somehow skipped it.
        if windows.isEmpty {
            let slice = Array(normalizedRows[0..<seqLen])
            windows.append(transpose(slice))
        }
        return windows
    }

    /// Converts [samples][channels] -> [channels][samples].
    private func transpose(_ rows: [[Float]]) -> [[Float]] {
        let samples = rows.count
        var out = Array(repeating: [Float](repeating: 0, count: samples), count: channels)
        for i in 0..<samples {
            for c in 0..<channels {
                out[c][i] = rows[i][c]
            }
        }
        return out
    }

    // MARK: - Model invocation

    /// `window` is a [9][128] channel-major matrix.
    private func runModel(_ model: FormFitModel, window: [[Float]]) -> [Double]? {
        let shape: [NSNumber] = [1, NSNumber(value: channels), NSNumber(value: seqLen)]
        guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else { return nil }

        // Core ML row-major stride: index = c * seqLen + t (since batch=1).
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: channels * seqLen)
        for c in 0..<channels {
            for t in 0..<seqLen {
                ptr[c * seqLen + t] = window[c][t]
            }
        }

        do {
            let input = FormFitModelInput(input: array)
            let output = try model.prediction(input: input)
            let mlOut = output.output  // MLMultiArray shape (1, 3)
            guard mlOut.count >= 3 else { return nil }
            let outPtr = mlOut.dataPointer.bindMemory(to: Float.self, capacity: mlOut.count)
            return [Double(outPtr[0]), Double(outPtr[1]), Double(outPtr[2])]
        } catch {
            print("FormFitInference: prediction failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Scoring math (mirrors CNN.py get_feedback)

    /// 25 points each for (1 - elbow), (1 - shoulder), (1 - torso), and eccentric time → max 100.
    private func computeOverallScore(
        elbow: Double,
        shoulder: Double,
        torso: Double,
        eccentricTime: Double
    ) -> Double {
        let metricContribution =
            (1.0 - elbow) * 25.0 +
            (1.0 - shoulder) * 25.0 +
            (1.0 - torso) * 25.0

        let eccContribution = eccentricScore(eccentricTime) * 25.0
        let total = metricContribution + eccContribution
        return max(0, min(100, total))
    }

    /// Full credit for 2.0-3.0s eccentrics; tapering distribution otherwise.
    ///     in [2, 3] → 1.0
    ///     else     → min(1.0, 1.25 / (1 + (x - 2.5)^2))
    private func eccentricScore(_ seconds: Double) -> Double {
        if (2.0...3.0).contains(seconds) { return 1.0 }
        return min(1.0, 1.25 / (1.0 + pow(seconds - 2.5, 2)))
    }

    private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
}
