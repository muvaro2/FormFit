import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private let session = WCSession.default
    private var pendingFileURL: URL?
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }
    
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {

        if let error = error {
            print("Watch activation error:", error)
            return
        }

        guard activationState == .activated else {
            print("Watch activation state:", activationState.rawValue)
            return
        }

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
}
