import SwiftUI

enum FormFitTheme {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.21)
    static let orangeDeep = Color(red: 0.84, green: 0.28, blue: 0.14)
    static let orangeSoft = Color(red: 1.0, green: 0.78, blue: 0.65)
    static let backgroundTop = Color(red: 1.0, green: 0.97, blue: 0.94)
    static let backgroundBottom = Color(red: 0.99, green: 0.92, blue: 0.86)
    static let cardBackground = Color(red: 0.995, green: 0.989, blue: 0.98)
    static let cardBorder = Color(red: 0.95, green: 0.84, blue: 0.75)
    static let textPrimary = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let textSecondary = Color(red: 0.43, green: 0.42, blue: 0.45)
    static let success = Color(red: 0.21, green: 0.62, blue: 0.45)
    static let info = Color(red: 0.22, green: 0.52, blue: 0.88)
    static let warning = Color(red: 0.9, green: 0.63, blue: 0.18)
    static let danger = Color(red: 0.84, green: 0.26, blue: 0.2)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, Color.white, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var primaryButtonGradient: LinearGradient {
        LinearGradient(
            colors: [orange, orangeDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct FormFitBackdrop: View {
    var body: some View {
        ZStack {
            FormFitTheme.backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(FormFitTheme.orange.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 12)
                .offset(x: 140, y: -250)

            Circle()
                .fill(FormFitTheme.orangeDeep.opacity(0.08))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: -150, y: 280)
        }
    }
}

private struct FormFitCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(FormFitTheme.textPrimary)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(FormFitTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(FormFitTheme.cardBorder.opacity(0.65), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 8)
    }
}

private struct FormFitPrimaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(FormFitTheme.primaryButtonGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: FormFitTheme.orange.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

private struct FormFitSecondaryButtonModifier: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.semibold))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FormFitTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accent.opacity(0.25), lineWidth: 1.25)
                    )
            )
    }
}

extension View {
    func formFitScreenBackground() -> some View {
        background(FormFitBackdrop())
    }

    func formFitCard() -> some View {
        modifier(FormFitCardModifier())
    }

    func formFitPrimaryButton() -> some View {
        modifier(FormFitPrimaryButtonModifier())
    }

    func formFitSecondaryButton(accent: Color = FormFitTheme.orange) -> some View {
        modifier(FormFitSecondaryButtonModifier(accent: accent))
    }
}

struct FormFitLogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .stroke(FormFitTheme.cardBorder.opacity(0.6), lineWidth: max(1, size * 0.03))
                )
                .shadow(color: Color.black.opacity(0.08), radius: size * 0.14, x: 0, y: size * 0.08)

            Text("F")
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(FormFitTheme.orange)
                .offset(x: -size * 0.12, y: -size * 0.1)

            Text("F")
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(FormFitTheme.orangeDeep)
                .offset(x: size * 0.1, y: size * 0.12)
        }
        .frame(width: size, height: size)
    }
}
