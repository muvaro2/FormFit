import Foundation
import WatchConnectivity
import Combine
import SwiftData

final class PhoneConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published private(set) var status: String = "Receiver ready"
    @Published private(set) var lastReceivedFilename: String?
    @Published private(set) var lastImportedFilename: String?
    @Published private(set) var lastImportMessage: String? = "Incoming watch CSV files are saved to Files and mirrored into app data."
    @Published private(set) var storedCSVCount: Int = 0
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var isWatchAppInstalled: Bool = false
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var isCollecting: Bool = false
    @Published private(set) var isPreparingCollection: Bool = false
    @Published private(set) var watchBufferCount: Int = 0
    @Published private(set) var lastWatchMessage: String? = "Open FormFit on the watch to enable remote control from the phone."

    var isWatchReady: Bool {
        isPaired && isWatchAppInstalled
    }

    private let fileManager = FileManager.default
    private let session = WCSession.default
    private var modelContainer: ModelContainer?
    private var hasActivatedSession = false
    private var hasPerformedInitialImport = false

    private override init() {
        super.init()
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        refreshStoredFiles()
        performInitialImportIfNeeded()
    }

    func activate() {
        guard WCSession.isSupported() else {
            updateStatus("WCSession not supported")
            return
        }

        if !hasActivatedSession {
            session.delegate = self
            session.activate()
            hasActivatedSession = true
        }

        updateSessionState(from: session)
        refreshStoredFiles()
        performInitialImportIfNeeded()
        updateStatus(connectionStatusText(for: session, activationState: session.activationState))

        print(
            "PHONE WC activate: paired=\(session.isPaired) " +
            "watchAppInstalled=\(session.isWatchAppInstalled) " +
            "reachable=\(session.isReachable) state=\(session.activationState.rawValue)"
        )
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        updateSessionState(from: session)
        performInitialImportIfNeeded()

        if let error {
            updateStatus("Activation error: \(error.localizedDescription)")
        } else {
            updateStatus(connectionStatusText(for: session, activationState: activationState))
        }

        print("PHONE WC activated: state=\(activationState.rawValue) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) err=\(String(describing: error))")
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        updateSessionState(from: session)
        updateStatus(connectionStatusText(for: session, activationState: session.activationState))
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateSessionState(from: session)
        updateStatus(connectionStatusText(for: session, activationState: session.activationState))
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateSessionState(from: session)
        updateStatus(connectionStatusText(for: session, activationState: session.activationState))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingMessage(message)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let incomingURL = file.fileURL
        let filename = (file.metadata?["filename"] as? String) ?? incomingURL.lastPathComponent

        // Save it somewhere stable (the incoming URL is temporary)
        let docs = documentsDirectory()
        let dest = docs.appendingPathComponent(filename)

        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.moveItem(at: incomingURL, to: dest)

            DispatchQueue.main.async {
                self.lastReceivedFilename = filename
                self.refreshStoredFiles()
                self.updateStatus("Received \(filename)")
            }

            importReceivedFile(at: dest)
            print("PHONE WC received file saved to:", dest)
        } catch {
            DispatchQueue.main.async {
                self.updateStatus("Receive failed: \(error.localizedDescription)")
                self.lastImportMessage = "The incoming file could not be stored on the phone."
            }
            print("PHONE WC receive failed:", error)
        }
    }

    private func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }

    private func updateSessionState(from session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    private func documentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func csvFileURLs() -> [URL] {
        let docs = documentsDirectory()
        let urls = (try? fileManager.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func refreshStoredFiles() {
        let urls = csvFileURLs()

        DispatchQueue.main.async {
            self.storedCSVCount = urls.count
            if self.lastReceivedFilename == nil {
                self.lastReceivedFilename = urls.last?.lastPathComponent
            }
        }
    }

    private func performInitialImportIfNeeded() {
        guard !hasPerformedInitialImport, let modelContainer else { return }
        hasPerformedInitialImport = true

        let urls = csvFileURLs()
        guard !urls.isEmpty else {
            DispatchQueue.main.async {
                self.lastImportMessage = "Watch CSV files will appear here after the watch saves and transfers a session."
            }
            return
        }

        Task { @MainActor in
            let context = modelContainer.mainContext
            var importedCount = 0

            for url in urls {
                do {
                    if try WorkoutSessionImporter.hasImportedCSV(named: url.lastPathComponent, in: context) {
                        continue
                    }

                    _ = try WorkoutSessionImporter.importCSV(at: url, in: context)
                    importedCount += 1
                    lastImportedFilename = url.lastPathComponent
                } catch {
                    lastImportMessage = "Saved CSVs are on the phone, but \(url.lastPathComponent) could not be imported into app data."
                }
            }

            refreshStoredFiles()

            if importedCount > 0 {
                lastImportMessage = importedCount == 1
                    ? "Imported 1 saved CSV into app data."
                    : "Imported \(importedCount) saved CSV files into app data."
            } else {
                lastImportMessage = "All saved CSV files are already available inside the app."
            }
        }
    }

    private func importReceivedFile(at fileURL: URL) {
        guard let modelContainer else {
            DispatchQueue.main.async {
                self.lastImportMessage = "The CSV was saved to Files, but app storage is not configured yet."
            }
            return
        }

        Task { @MainActor in
            do {
                let importedSession = try WorkoutSessionImporter.importCSV(
                    at: fileURL,
                    in: modelContainer.mainContext
                )
                lastImportedFilename = fileURL.lastPathComponent
                lastImportMessage = "Imported \(importedSession.sampleCount) samples into app data from \(fileURL.lastPathComponent)."
            } catch {
                lastImportMessage = "Saved \(fileURL.lastPathComponent) to Files, but app import failed: \(error.localizedDescription)"
            }
        }
    }

    private func connectionStatusText(
        for session: WCSession,
        activationState: WCSessionActivationState
    ) -> String {
        if !session.isPaired {
            return "Waiting for a paired Apple Watch"
        }

        if !session.isWatchAppInstalled {
            return "Watch paired, but the watch app is not installed"
        }

        if activationState != .activated {
            return "Activating Apple Watch connection..."
        }

        if session.isReachable {
            return "Apple Watch connected and reachable"
        }

        return "Apple Watch connected"
    }

    func sendCollectorCommand(_ command: String) {
        guard WCSession.isSupported() else {
            lastWatchMessage = "WatchConnectivity is not available on this phone."
            return
        }

        guard session.activationState == .activated else {
            activate()
            lastWatchMessage = "Activating the Apple Watch connection. Try again in a moment."
            return
        }

        guard session.isReachable else {
            lastWatchMessage = "Open FormFit on the Apple Watch to control collection from the phone."
            return
        }

        let payload = ["collectorCommand": command]
        updateStatus("Sending \(command) to Apple Watch...")

        session.sendMessage(payload) { response in
            self.handleIncomingMessage(response)
        } errorHandler: { error in
            DispatchQueue.main.async {
                self.lastWatchMessage = "Could not send \(command) to the watch: \(error.localizedDescription)"
                self.updateStatus(self.connectionStatusText(for: self.session, activationState: self.session.activationState))
            }
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard (message["messageType"] as? String) == "collectorState" else { return }

        let reason = message["reason"] as? String
        let isCollecting = message["isCollecting"] as? Bool ?? false
        let isPreparing = message["isPreparing"] as? Bool ?? false
        let bufferCount = message["bufferCount"] as? Int ?? 0
        let lastSaveMessage = message["lastSaveMessage"] as? String

        DispatchQueue.main.async {
            self.isCollecting = isCollecting
            self.isPreparingCollection = isPreparing
            self.watchBufferCount = bufferCount
            self.status = self.connectionStatusText(for: self.session, activationState: self.session.activationState)

            if let reason, !reason.isEmpty {
                self.lastWatchMessage = reason
            } else if let lastSaveMessage, !lastSaveMessage.isEmpty {
                self.lastWatchMessage = lastSaveMessage
            }
        }
    }
}
