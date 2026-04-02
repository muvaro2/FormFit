import Foundation
import WatchConnectivity
import Observation

// MARK: - Shared message-protocol types (duplicated in PhoneConnectivityManager.swift)

enum WorkoutCommand: String {
    case startWorkout = "startWorkout"
    case stopWorkout  = "stopWorkout"
}

enum WorkoutEvent: String {
    case stabilityReady = "stabilityReady"
    case workoutStarted = "workoutStarted"
    case workoutStopped = "workoutStopped"
}

// MARK: - Watch-side connectivity manager
/// Receives start/stop commands from the phone and sends events + CSV file back.
@Observable
final class WatchConnectivityManager: NSObject {

    var isPhoneReachable = false

    /// Set when the phone sends a command; consumed by WorkoutControlView.
    var pendingCommand: WatchPendingCommand? = nil

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Events to Phone

    func sendStabilityReady() {
        sendEvent(.stabilityReady)
    }

    func sendWorkoutStarted() {
        sendEvent(.workoutStarted)
    }

    func sendWorkoutStopped() {
        sendEvent(.workoutStopped)
    }

    func transferCSV(at url: URL) {
        WCSession.default.transferFile(url, metadata: ["type": "motionData"])
    }

    // MARK: - Private

    private func sendEvent(_ event: WorkoutEvent) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["event": event.rawValue], replyHandler: nil)
    }
}

// MARK: - Pending command type (watch-local)

enum WatchPendingCommand: Equatable {
    case startWorkout(name: String)
    case stopWorkout
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let commandRaw = message["command"] as? String else { return }
        Task { @MainActor in
            switch commandRaw {
            case WorkoutCommand.startWorkout.rawValue:
                let name = message["workoutName"] as? String ?? "External Rotation"
                self.pendingCommand = .startWorkout(name: name)
            case WorkoutCommand.stopWorkout.rawValue:
                self.pendingCommand = .stopWorkout
            default:
                break
            }
        }
    }
}
