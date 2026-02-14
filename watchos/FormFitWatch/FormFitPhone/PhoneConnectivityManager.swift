/*
import Foundation
import WatchConnectivity

final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // leave empty for now
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // For now just print, we’ll save to Documents next step.
        print("Received file:", file.fileURL)
    }
}
*/

import Foundation
import WatchConnectivity
import Combine

final class PhoneConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published private(set) var status: String = "Receiver ready"
    @Published private(set) var lastReceivedFilename: String?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = "WCSession not supported"
            return
        }

        let s = WCSession.default
        s.delegate = self
        s.activate()

        status = "Activating… paired=\(s.isPaired) watchAppInstalled=\(s.isWatchAppInstalled)"
        print("PHONE WC activate: paired=\(s.isPaired) watchAppInstalled=\(s.isWatchAppInstalled) state=\(s.activationState.rawValue)")
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.status = "Activation error: \(error.localizedDescription)"
            } else {
                self.status = "Activated. paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled)"
            }
        }
        print("PHONE WC activated: state=\(activationState.rawValue) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) err=\(String(describing: error))")
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let incomingURL = file.fileURL
        let filename = incomingURL.lastPathComponent

        // Save it somewhere stable (the incoming URL is temporary)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent(filename)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: incomingURL, to: dest)

            DispatchQueue.main.async {
                self.lastReceivedFilename = filename
                self.status = "Received \(filename)"
            }
            print("PHONE WC received file saved to:", dest)
        } catch {
            DispatchQueue.main.async {
                self.status = "Receive failed: \(error.localizedDescription)"
            }
            print("PHONE WC receive failed:", error)
        }
    }
}
