import SwiftUI
import SwiftData

@main
struct FormFitPhoneApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: WorkoutSession.self,
                WorkoutRepetition.self,
                WorkoutMotionSample.self
            )
            PhoneConnectivityManager.shared.configure(modelContainer: modelContainer)
        } catch {
            fatalError("Failed to set up workout session storage: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootLaunchView()
                .onAppear {
                    PhoneConnectivityManager.shared.activate()
                }
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}

struct RootLaunchView: View {
    @State private var isShowingLaunchScreen = true
    @State private var isShowingTutorial = false

    var body: some View {
        ZStack {
            ContentView {
                isShowingTutorial = true
            }
            .opacity(isShowingLaunchScreen ? 0 : 1)

            if isShowingLaunchScreen {
                LaunchLoadingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))

            withAnimation(.easeInOut(duration: 0.45)) {
                isShowingLaunchScreen = false
            }

            try? await Task.sleep(for: .milliseconds(450))
            isShowingTutorial = true
        }
        .sheet(isPresented: $isShowingTutorial) {
            TutorialView(steps: TutorialStep.defaultSteps) {
                isShowingTutorial = false
            }
        }
    }
}
