import SwiftUI

struct LaunchLoadingView: View {
    let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    @State private var animateRing = false
    @State private var pulseLogo = false
    @State private var revealContent = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.97, blue: 0.94),
                    Color.white,
                    Color(red: 0.99, green: 0.92, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(primaryOrange.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 10)
                .offset(x: 120, y: -220)

            Circle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 240, height: 240)
                .blur(radius: 30)
                .offset(x: -120, y: 280)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(primaryOrange.opacity(0.12), lineWidth: 18)
                        .frame(width: 150, height: 150)

                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    primaryOrange.opacity(0.2),
                                    primaryOrange,
                                    Color(red: 0.84, green: 0.26, blue: 0.12),
                                    primaryOrange.opacity(0.2)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(animateRing ? 360 : 0))

                    VStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(primaryOrange)

                        Text("FF")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.82))
                    }
                    .scaleEffect(pulseLogo ? 1.04 : 0.96)
                }

                VStack(spacing: 10) {
                    Text("FormFit")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.9))

                    Text("Preparing your coaching dashboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gray)
                }
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 10)

                VStack(spacing: 14) {
                    SwiftUI.ProgressView()
                        .progressViewStyle(.linear)
                        .tint(primaryOrange)
                        .frame(width: 180)

                    Text("Syncing workout insights...")
                        .font(.caption)
                        .foregroundColor(.gray)
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
