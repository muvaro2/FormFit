import SwiftUI

struct TutorialStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
}

struct TutorialView: View {
    let steps: [TutorialStep]
    let onDismiss: () -> Void

    @State private var currentStep = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack {
                    Text("How FormFit Works")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Spacer()

                    Button("Skip") {
                        onDismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gray)
                }

                TabView(selection: $currentStep) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        TutorialCard(step: step)
                            .tag(index)
                            .padding(.horizontal, 4)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(maxHeight: .infinity)

                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                currentStep -= 1
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.gray)
                    } else {
                        Color.clear
                            .frame(width: 60, height: 24)
                    }

                    Spacer()

                    Button(currentStep == steps.count - 1 ? "Get Started" : "Next") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if currentStep == steps.count - 1 {
                                onDismiss()
                            } else {
                                currentStep += 1
                            }
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 1.0, green: 0.42, blue: 0.21))
                    .clipShape(Capsule())
                }
            }
            .padding(24)
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct TutorialCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [step.accentColor.opacity(0.18), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 220)

                VStack(spacing: 18) {
                    Image(systemName: step.icon)
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundColor(step.accentColor)

                    Text(step.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(step.title)
                    .font(.title2.weight(.bold))

                Text(step.description)
                    .font(.body)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

extension TutorialStep {
    static let defaultSteps: [TutorialStep] = [
        TutorialStep(
            icon: "house.fill",
            title: "Access your insights",
            description: "Use the Home tab and Activity Tab to check your latest form score, current streak, and jump back into a workout quickly.",
            accentColor: Color(red: 1.0, green: 0.42, blue: 0.21)
        ),
        TutorialStep(
            icon: "figure.run",
            title: "Track Workouts Live",
            description: "Open Workout to start a session, watch your live form score, and tap the AI Coach card for expanded feedback.",
            accentColor: .blue
        ),
        TutorialStep(
            icon: "chart.line.uptrend.xyaxis",
            title: "Set Up Your Rep",
            description: "Place your arms next to your body, and make a 90 degree angle with your elbow, with the band in front of you. Then, Attempt to move your forearm to the left while keeping your elbow stationary.",
            accentColor: .green
        ),
        TutorialStep(
            icon: "person.fill",
            title: "End Workout",
            description: "After completing the workout, click stop workout and see your results.",
            accentColor: .orange
        )
    ]
}

#Preview {
    TutorialView(steps: TutorialStep.defaultSteps, onDismiss: {})
}
