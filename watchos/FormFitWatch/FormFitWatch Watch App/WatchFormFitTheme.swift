import SwiftUI

enum WatchFormFitTheme {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.21)
    static let orangeDeep = Color(red: 0.84, green: 0.28, blue: 0.14)
    static let orangeSoft = Color(red: 1.0, green: 0.82, blue: 0.72)
    static let creamTop = Color(red: 0.99, green: 0.96, blue: 0.93)
    static let creamBottom = Color(red: 0.98, green: 0.9, blue: 0.82)
    static let card = Color(red: 0.99, green: 0.985, blue: 0.975)
    static let border = Color(red: 0.95, green: 0.84, blue: 0.75)
    static let ink = Color(red: 0.17, green: 0.16, blue: 0.18)
    static let secondaryInk = Color(red: 0.43, green: 0.41, blue: 0.44)
    static let success = Color(red: 0.21, green: 0.62, blue: 0.45)
    static let danger = Color(red: 0.84, green: 0.26, blue: 0.2)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [creamTop, Color.white, creamBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WatchFormFitBackdrop: View {
    var body: some View {
        ZStack {
            WatchFormFitTheme.backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(WatchFormFitTheme.orange.opacity(0.15))
                .frame(width: 120, height: 120)
                .blur(radius: 6)
                .offset(x: 52, y: -84)

            Circle()
                .fill(WatchFormFitTheme.orangeDeep.opacity(0.08))
                .frame(width: 96, height: 96)
                .blur(radius: 10)
                .offset(x: -56, y: 92)
        }
    }
}

private struct WatchFormFitCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(WatchFormFitTheme.ink)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(WatchFormFitTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(WatchFormFitTheme.border.opacity(0.7), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func watchFormFitCard() -> some View {
        modifier(WatchFormFitCardModifier())
    }
}

struct WatchFormFitLogoMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .stroke(WatchFormFitTheme.border.opacity(0.7), lineWidth: max(1, size * 0.05))
                )

            Text("F")
                .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                .foregroundStyle(WatchFormFitTheme.orange)
                .offset(x: -size * 0.11, y: -size * 0.08)

            Text("F")
                .font(.system(size: size * 0.46, weight: .black, design: .rounded))
                .foregroundStyle(WatchFormFitTheme.orangeDeep)
                .offset(x: size * 0.1, y: size * 0.12)
        }
        .frame(width: size, height: size)
    }
}
