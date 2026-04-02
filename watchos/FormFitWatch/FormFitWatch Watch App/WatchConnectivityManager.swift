import Foundation
import WatchConnectivity
import Combine

final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session = WCSession.default
    private var pendingFileURL: URL?

    @Published private(set) var isPhoneReachable = false
    @Published private(set) var connectionStatus = "Waiting for iPhone"
    @Published private(set) var lastPhoneCommandMessage: String?
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        updateConnectionState()
    }
    
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {

        if let error = error {
            print("Watch activation error:", error)
            updateConnectionState(statusOverride: "Watch connectivity error")
            return
        }

        guard activationState == .activated else {
            print("Watch activation state:", activationState.rawValue)
            updateConnectionState()
            return
        }

        updateConnectionState()

        if let url = pendingFileURL {
            pendingFileURL = nil
            _ = self.session.transferFile(url, metadata: ["filename": url.lastPathComponent])
            print("Watch: queued transfer after activation:", url.lastPathComponent)
        }
    }
    
    func transferFile(_ fileURL: URL) {
        guard WCSession.isSupported() else { return }

        if self.session.activationState != .activated {
            pendingFileURL = fileURL
            activate()
            print("Watch: not activated yet, will send after activation:", fileURL.lastPathComponent)
            return
        }

        _ = self.session.transferFile(fileURL, metadata: ["filename": fileURL.lastPathComponent])
        print("Watch: queued transfer:", fileURL.lastPathComponent)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateConnectionState()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handle(message: message, replyHandler: nil)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any],
        replyHandler: @escaping ([String : Any]) -> Void
    ) {
        handle(message: message, replyHandler: replyHandler)
    }

    func pushCollectorStateUpdate(reason: String? = nil) {
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isReachable else {
            updateConnectionState()
            return
        }

        session.sendMessage(statePayload(reason: reason), replyHandler: nil) { error in
            print("Watch state push failed:", error.localizedDescription)
        }
    }

    private func handle(
        message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) {
        let command = (message["collectorCommand"] as? String)?.lowercased()
        let response: [String: Any]

        switch command {
        case "start":
            performOnMain {
                MotionManager.shared.startFromPhone()
            }
            response = statePayload(reason: "Phone requested collection start.")
        case "stop":
            performOnMain {
                MotionManager.shared.stop()
            }
            response = statePayload(reason: "Phone requested collection stop.")
        case "clear":
            performOnMain {
                MotionManager.shared.clear()
            }
            response = statePayload(reason: "Phone requested buffer clear.")
        case "save":
            performOnMain {
                MotionManager.shared.saveCSV()
            }
            response = statePayload(reason: "Phone requested save to phone files.")
        default:
            response = statePayload(reason: "Unknown phone command.")
        }

        DispatchQueue.main.async {
            self.lastPhoneCommandMessage = response["reason"] as? String
        }

        replyHandler?(response)
    }

    private func statePayload(reason: String?) -> [String: Any] {
        let motion = MotionManager.shared

        return [
            "messageType": "collectorState",
            "reason": reason ?? collectionStatusSummary(for: motion),
            "collectionState": collectionStateIdentifier(for: motion),
            "isCollecting": motion.isRecording,
            "isPreparing": motion.isPreparing,
            "bufferCount": motion.buffer.count,
            "lastSaveMessage": motion.lastSaveMessage ?? ""
        ]
    }

    private func collectionStateIdentifier(for motion: MotionManager) -> String {
        if motion.isRecording {
            return "collecting"
        }

        if motion.isPreparing || motion.isRunning {
            return "arming"
        }

        if motion.buffer.isEmpty {
            return "idle"
        }

        return "captured"
    }

    private func collectionStatusSummary(for motion: MotionManager) -> String {
        if let lastSaveMessage = motion.lastSaveMessage, !lastSaveMessage.isEmpty {
            return lastSaveMessage
        }

        switch collectionStateIdentifier(for: motion) {
        case "collecting":
            return "Watch is collecting motion data."
        case "arming":
            return "Watch is preparing to collect."
        case "captured":
            return "Watch has captured data and is ready to save."
        default:
            return "Watch is ready for a new session."
        }
    }

    private func updateConnectionState(statusOverride: String? = nil) {
        let reachable = session.isReachable
        let status: String

        if let statusOverride {
            status = statusOverride
        } else if session.activationState != .activated {
            status = "Connecting to iPhone"
        } else if reachable {
            status = "iPhone connected"
        } else {
            status = "Phone not reachable"
        }

        DispatchQueue.main.async {
            self.isPhoneReachable = reachable
            self.connectionStatus = status
        }
    }

    private func performOnMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
