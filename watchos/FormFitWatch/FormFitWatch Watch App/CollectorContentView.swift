//
//  CollectorContentView.swift
//  FormFitWatch
//
//  Created by Saavan Kiran on 2/22/26.
//

import SwiftUI

struct CollectorContentView: View {
    @StateObject private var motion = MotionManager.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var stateTitle: String {
        if motion.isRecording {
            return "Collecting"
        }

        if motion.isPreparing || motion.isRunning {
            return "Arming"
        }

        if motion.buffer.isEmpty {
            return "Ready"
        }

        return "Captured"
    }

    private var stateDetail: String {
        if motion.isRecording {
            return "Watch motion data is actively being recorded."
        }

        if motion.isPreparing || motion.isRunning {
            return "Get into position. Recording will begin in a moment."
        }

        if motion.buffer.isEmpty {
            return "Start on the watch or from the phone when the watch is open."
        }

        return "Session captured. Save it to send the CSV to the phone."
    }

    private var statusBanner: String? {
        if let lastSaveMessage = motion.lastSaveMessage, !lastSaveMessage.isEmpty {
            return lastSaveMessage
        }

        return connectivity.lastPhoneCommandMessage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                stateCard
                if let statusBanner {
                    bannerCard(text: statusBanner)
                }
                controlsGrid
            }
            .padding(8)
        }
        .background(WatchFormFitBackdrop())
        .onAppear {
            WatchConnectivityManager.shared.activate()
            WatchConnectivityManager.shared.pushCollectorStateUpdate()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WatchFormFitLogoMark(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("FormFit")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(WatchFormFitTheme.ink)
                Text(connectivity.connectionStatus)
                    .font(.caption2)
                    .foregroundStyle(WatchFormFitTheme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(connectivity.isPhoneReachable ? WatchFormFitTheme.success : WatchFormFitTheme.orange)
                .frame(width: 10, height: 10)
        }
        .watchFormFitCard()
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stateTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(stateDetail)
                        .font(.caption2)
                        .foregroundStyle(WatchFormFitTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(WatchFormFitTheme.orange.opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: motion.isRecording ? "waveform.path.ecg" : "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(motion.isRecording ? WatchFormFitTheme.danger : WatchFormFitTheme.orange)
                }
            }

            HStack(spacing: 6) {
                WatchMetricPill(title: "Samples", value: "\(motion.buffer.count)")
                WatchMetricPill(title: "Rate", value: "\(Int(motion.tickMs))ms")
                WatchMetricPill(title: "Phone", value: connectivity.isPhoneReachable ? "Live" : "Later")
            }
        }
        .watchFormFitCard()
    }

    private func bannerCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.circle.fill")
                .foregroundStyle(WatchFormFitTheme.orange)
                .font(.caption)
                .padding(.top, 1)

            Text(text)
                .font(.caption2)
                .foregroundStyle(WatchFormFitTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .watchFormFitCard()
    }

    private var controlsGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            WatchControlTile(
                title: "Start",
                subtitle: "Arm",
                systemImage: "play.fill",
                accent: WatchFormFitTheme.orange,
                isEnabled: !motion.isActive
            ) {
                motion.armAndStart(prepDelay: 2.5, stillnessSeconds: 0.5)
            }

            WatchControlTile(
                title: "Stop",
                subtitle: "Pause",
                systemImage: "pause.fill",
                accent: WatchFormFitTheme.danger,
                isEnabled: motion.isActive
            ) {
                motion.stop()
            }

            WatchControlTile(
                title: "Clear",
                subtitle: "Reset",
                systemImage: "trash",
                accent: WatchFormFitTheme.orangeDeep,
                isEnabled: !motion.isActive
            ) {
                motion.clear()
            }

            WatchControlTile(
                title: "Save",
                subtitle: "Send",
                systemImage: "square.and.arrow.down.fill",
                accent: WatchFormFitTheme.success,
                isEnabled: !motion.buffer.isEmpty && !motion.isActive
            ) {
                motion.saveCSV()
            }
        }
    }
}

private struct WatchMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(WatchFormFitTheme.ink)
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(WatchFormFitTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(WatchFormFitTheme.border.opacity(0.8), lineWidth: 1)
                )
        )
    }
}

private struct WatchControlTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .opacity(0.9)
            }
            .foregroundStyle(isEnabled ? Color.white : WatchFormFitTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(tileBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(isEnabled ? 0 : 0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.7)
    }

    private var tileBackground: some ShapeStyle {
        if isEnabled {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [accent, accent.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(0.94))
    }
}

#Preview {
    CollectorContentView()
}
