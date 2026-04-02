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
                        .foregroundStyle(FormFitTheme.textPrimary)

                    Spacer()

                    Button("Skip") {
                        onDismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FormFitTheme.textSecondary)
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
                        .foregroundStyle(FormFitTheme.textSecondary)
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(FormFitTheme.primaryButtonGradient)
                    .clipShape(Capsule())
                }
            }
            .padding(24)
            .formFitScreenBackground()
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
                            colors: [step.accentColor.opacity(0.18), FormFitTheme.cardBackground],
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
                    .foregroundStyle(FormFitTheme.textPrimary)

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(FormFitTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .formFitCard()
    }
}

extension TutorialStep {
    static let defaultSteps: [TutorialStep] = [
        TutorialStep(
            icon: "house.fill",
            title: "Access your insights",
            description: "Use the Home and Progress tabs to check your latest imported sessions, view connection status, and jump back into a workout quickly.",
            accentColor: FormFitTheme.orange
        ),
        TutorialStep(
            icon: "applewatch",
            title: "Collect on the Watch",
            description: "Start the workout flow on your phone or watch, then collect the motion session on your Apple Watch. When you save on the watch, the phone stores the CSV automatically.",
            accentColor: FormFitTheme.info
        ),
        TutorialStep(
            icon: "square.and.arrow.down.fill",
            title: "Keep raw data and app data",
            description: "Every transferred CSV stays in the phone app's Files storage, and the app also imports that same session into its own data store for future on-device analysis.",
            accentColor: FormFitTheme.success
        ),
        TutorialStep(
            icon: "sparkles",
            title: "Score later",
            description: "The current summary screens are ready for imported sessions today, and the final Core ML scoring pipeline can plug into those same screens when it is ready.",
            accentColor: FormFitTheme.warning
        )
    ]
}

#Preview {
    TutorialView(steps: TutorialStep.defaultSteps, onDismiss: {})
}
