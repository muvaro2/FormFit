import Foundation
import WatchConnectivity
import Observation
import SwiftData

// MARK: - Shared message types

enum WorkoutCommand: String {
    case startWorkout = "startWorkout"
    case stopWorkout = "stopWorkout"
}

enum WorkoutEvent: String {
    case stabilityReady = "stabilityReady"
    case workoutStarted = "workoutStarted"
    case workoutStopped = "workoutStopped"
}

// MARK: - Watch workout state as seen from the phone

enum WatchWorkoutState {
    case idle
    case stabilizing
    case active
}

// MARK: - Phone-side connectivity manager

@Observable
final class PhoneConnectivityManager: NSObject {

    // Published state
    var isWatchPaired = false
    var isWatchReachable = false
    var watchWorkoutState: WatchWorkoutState = .idle

    /// Set when a motion CSV file has been received from the watch and saved to Documents.
    var latestReceivedCSVURL: URL? = nil

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Commands to Watch

    func sendStartWorkout(name: String = "External Rotation") {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [
                "command": WorkoutCommand.startWorkout.rawValue,
                "workoutName": name
            ],
            replyHandler: nil
        )
        watchWorkoutState = .stabilizing
    }

    func sendStopWorkout() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["command": WorkoutCommand.stopWorkout.rawValue],
            replyHandler: nil
        )
    }

    // MARK: - CSV Documents directory helpers

    static var csvDocumentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkoutCSVs", isDirectory: true)
    }

    static func allSavedCSVs() -> [URL] {
        let dir = csvDocumentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return aDate > bDate
            }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let eventRaw = message["event"] as? String,
              let event = WorkoutEvent(rawValue: eventRaw) else { return }
        Task { @MainActor in
            switch event {
            case .stabilityReady:
                self.watchWorkoutState = .stabilizing
            case .workoutStarted:
                self.watchWorkoutState = .active
            case .workoutStopped:
                // State transitions to idle once CSV file is received
                break
            }
        }
    }

    /// Called when the watch transfers a motion CSV file to the phone.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.fileURL.pathExtension.lowercased() == "csv" else { return }

        let dir = PhoneConnectivityManager.csvDocumentsDirectory
        let destURL = dir.appendingPathComponent(file.fileURL.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            // Must copy before this delegate method returns — the source file is deleted afterward.
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)

            Task { @MainActor in
                self.latestReceivedCSVURL = destURL
                self.watchWorkoutState = .idle
            }
        } catch {
            print("[PhoneConnectivity] Failed to save incoming CSV: \(error)")
        }
    }
}
