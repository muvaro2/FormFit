import Foundation
import CoreMotion
import Observation

// Raw IMU sample collected from the watch
struct WatchMotionSample {
    let relativeTime: Double
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let roll: Double
    let pitch: Double
    let yaw: Double
}

@Observable
final class WatchMotionManager {

    var isCollecting = false
    var sampleCount = 0

    // True once at least a short window of data suggests the watch is stationary.
    var isStable = false

    private let motionManager = CMMotionManager()
    private var samples: [WatchMotionSample] = []
    private var startTime: Date?

    /// Starts 50 Hz device-motion collection and updates `isStable` as data arrives.
    func startCollecting() {
        guard motionManager.isDeviceMotionAvailable, !isCollecting else { return }

        samples.removeAll()
        startTime = Date()
        isCollecting = true
        sampleCount = 0
        isStable = false

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }

            let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
            let sample = WatchMotionSample(
                relativeTime: elapsed,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                gyroX: motion.rotationRate.x,
                gyroY: motion.rotationRate.y,
                gyroZ: motion.rotationRate.z,
                roll: motion.attitude.roll,
                pitch: motion.attitude.pitch,
                yaw: motion.attitude.yaw
            )
            self.samples.append(sample)
            self.sampleCount = self.samples.count

            // Update stability flag from the most recent window of samples.
            // TODO: Replace with proper variance-based check once thresholds are tuned.
            self.isStable = self.checkStability()
        }
    }

    /// Stops collection, serialises all buffered samples to a CSV in the temp directory,
    /// and returns the file URL (or nil if no samples were collected).
    @discardableResult
    func stopCollecting() -> URL? {
        motionManager.stopDeviceMotionUpdates()
        isCollecting = false
        return writeCSV()
    }

    // MARK: - Private

    /// Returns true when the last ~0.5 s of samples show low resultant acceleration.
    private func checkStability() -> Bool {
        let windowSize = 25  // 0.5 s at 50 Hz
        guard samples.count >= windowSize else { return false }
        let window = samples.suffix(windowSize)

        // Compute mean resultant of user-acceleration magnitudes over the window.
        let meanMag = window.reduce(0.0) {
            $0 + sqrt($1.accelerationX * $1.accelerationX
                      + $1.accelerationY * $1.accelerationY
                      + $1.accelerationZ * $1.accelerationZ)
        } / Double(windowSize)

        return meanMag < 0.12  // threshold in g — adjust after real-world testing
    }

    private func writeCSV() -> URL? {
        guard !samples.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "workout_\(formatter.string(from: startTime ?? Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        var lines = ["timestamp,accelerationX,accelerationY,accelerationZ,gyroX,gyroY,gyroZ,roll,pitch,yaw"]
        for s in samples {
            lines.append(
                "\(fmt(s.relativeTime)),\(fmt(s.accelerationX)),\(fmt(s.accelerationY)),"
                + "\(fmt(s.accelerationZ)),\(fmt(s.gyroX)),\(fmt(s.gyroY)),\(fmt(s.gyroZ)),"
                + "\(fmt(s.roll)),\(fmt(s.pitch)),\(fmt(s.yaw))"
            )
        }
        let csv = lines.joined(separator: "\n")

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("[WatchMotion] Failed to write CSV: \(error)")
            return nil
        }
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.6f", v)
    }
}
