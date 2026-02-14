import SwiftUI

@main
struct FormFitPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneHomeView()
                .onAppear {
                    PhoneConnectivityManager.shared.activate()
                }
        }
    }
}

struct PhoneHomeView: View {
    @ObservedObject private var wc = PhoneConnectivityManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Text("FormFit Phone")
                .font(.headline)

            Text(wc.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let name = wc.lastReceivedFilename {
                Text("Last file: \(name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
