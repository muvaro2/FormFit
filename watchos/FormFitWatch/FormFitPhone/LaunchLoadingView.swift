import SwiftUI

struct LaunchLoadingView: View {
    @State private var animateRing = false
    @State private var pulseLogo = false
    @State private var revealContent = false

    var body: some View {
        ZStack {
            FormFitBackdrop()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(FormFitTheme.orange.opacity(0.12), lineWidth: 18)
                        .frame(width: 150, height: 150)

                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    FormFitTheme.orange.opacity(0.2),
                                    FormFitTheme.orange,
                                    FormFitTheme.orangeDeep,
                                    FormFitTheme.orange.opacity(0.2)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(animateRing ? 360 : 0))

                    FormFitLogoMark(size: 86)
                    .scaleEffect(pulseLogo ? 1.04 : 0.96)
                }

                VStack(spacing: 10) {
                    Text("FormFit")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(FormFitTheme.textPrimary)

                    Text("Preparing your coaching dashboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FormFitTheme.textSecondary)
                }
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 10)

                VStack(spacing: 14) {
                    SwiftUI.ProgressView()
                        .progressViewStyle(.linear)
                        .tint(FormFitTheme.orange)
                        .frame(width: 180)

                    Text("Syncing workout insights...")
                        .font(.caption)
                        .foregroundStyle(FormFitTheme.textSecondary)
                }
                .opacity(revealContent ? 1 : 0)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                revealContent = true
            }

            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseLogo = true
            }

            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                animateRing = true
            }
        }
    }
}

#Preview {
    LaunchLoadingView()
}
