import SwiftUI

@main
struct FormFitWatchApp: App {
    @State private var connectivity = WatchConnectivityManager()
    @State private var motionManager = WatchMotionManager()

    var body: some Scene {
        WindowGroup {
            WorkoutControlView()
                .environment(connectivity)
                .environment(motionManager)
        }
    }
}
