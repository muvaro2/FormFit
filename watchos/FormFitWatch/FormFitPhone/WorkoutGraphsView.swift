import SwiftUI
import Charts
import SwiftData
import UIKit

@MainActor
struct WorkoutGraphsView: View {
    private enum Scope: Hashable {
        case fullSession
        case repetition(UUID)
    }

    private struct ChannelPoint: Identifiable {
        let id = UUID()
        let time: Double
        let channel: Channel
        let value: Double
    }

    private enum Channel: String, CaseIterable, Identifiable {
        case roll
        case pitch
        case yaw

        var id: String { rawValue }

        var title: String {
            switch self {
            case .roll:
                return "Roll"
            case .pitch:
                return "Pitch"
            case .yaw:
                return "Yaw"
            }
        }

        var color: Color {
            switch self {
            case .roll:
                return FormFitTheme.orange
            case .pitch:
                return FormFitTheme.info
            case .yaw:
                return FormFitTheme.success
            }
        }
    }

    private struct BoundaryMarker: Identifiable {
        let id = UUID()
        let label: String
        let time: Double
    }

    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScope: Scope = .fullSession

    private let maxRenderedSamples = 900

    private var repetitions: [WorkoutRepetition] {
        session.repetitions.sorted {
            if $0.index == $1.index {
                return $0.repetitionDate < $1.repetitionDate
            }
            return $0.index < $1.index
        }
    }

    private var displayedSamples: [WorkoutMotionSample] {
        let baseSamples: [WorkoutMotionSample]
        switch selectedScope {
        case .fullSession:
            baseSamples = repetitions
                .flatMap { repetition in
                    repetition.samples.sorted { left, right in
                        if left.relativeTime == right.relativeTime {
                            return left.index < right.index
                        }
                        return left.relativeTime < right.relativeTime
                    }
                }
        case let .repetition(id):
            baseSamples = repetitions
                .first(where: { $0.id == id })?
                .samples
                .sorted { left, right in
                    if left.relativeTime == right.relativeTime {
                        return left.index < right.index
                    }
                    return left.relativeTime < right.relativeTime
                } ?? []
        }

        return downsample(baseSamples, maxCount: maxRenderedSamples)
    }

    private var channelPoints: [ChannelPoint] {
        guard let firstTime = displayedSamples.first?.relativeTime else { return [] }

        return displayedSamples.flatMap { sample in
            let elapsed = sample.relativeTime - firstTime
            return [
                ChannelPoint(time: elapsed, channel: .roll, value: sample.roll * 180.0 / .pi),
                ChannelPoint(time: elapsed, channel: .pitch, value: sample.pitch * 180.0 / .pi),
                ChannelPoint(time: elapsed, channel: .yaw, value: sample.yaw * 180.0 / .pi)
            ]
        }
    }

    private var boundaryMarkers: [BoundaryMarker] {
        guard case .fullSession = selectedScope,
              let firstTime = repetitions.first?.samples.sorted(by: { $0.relativeTime < $1.relativeTime }).first?.relativeTime
        else {
            return []
        }

        return repetitions.dropFirst().compactMap { repetition in
            guard let startTime = repetition.samples.sorted(by: { $0.relativeTime < $1.relativeTime }).first?.relativeTime else {
                return nil
            }

            return BoundaryMarker(
                label: "Rep \(repetition.index + 1)",
                time: startTime - firstTime
            )
        }
    }

    private var selectedRepetition: WorkoutRepetition? {
        guard case let .repetition(id) = selectedScope else { return nil }
        return repetitions.first { $0.id == id }
    }

    private var scopeTitle: String {
        switch selectedScope {
        case .fullSession:
            return "Full Session"
        case let .repetition(id):
            guard let repetition = repetitions.first(where: { $0.id == id }) else {
                return "Repetition"
            }
            return "Rep \(repetition.index + 1)"
        }
    }

    private var rangeText: String {
        let range = selectedMetricRange
        return range.map { "\($0.formatted(.number.precision(.fractionLength(0))))°" } ?? "--"
    }

    private var eccentricText: String {
        let eccentric = selectedMetricEccentricTime
        return eccentric.map { "\($0.formatted(.number.precision(.fractionLength(1))))s" } ?? "--"
    }

    private var concentricText: String {
        let concentric = selectedMetricConcentricTime
        return concentric.map { "\($0.formatted(.number.precision(.fractionLength(1))))s" } ?? "--"
    }

    private var eccentricBadge: EccentricScore? {
        selectedMetricEccentricTime.map(eccentricScore(duration:))
    }

    private var selectedMetricRange: Double? {
        metricValues(\.rangeOfMotion)
    }

    private var selectedMetricConcentricTime: Double? {
        metricValues(\.concentricTime)
    }

    private var selectedMetricEccentricTime: Double? {
        metricValues(\.eccentricTime)
    }

    private var graphHeaderSubtitle: String {
        if displayedSamples.count < (selectedScope == .fullSession ? session.sampleCount : selectedRepetition?.samples.count ?? 0) {
            return "Displaying a downsampled view of the imported motion trace for readability."
        }

        return "Imported pitch, yaw, and roll traces from the watch session."
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                FormFitBackdrop()

                Group {
                    if isLandscape {
                        HStack(spacing: 20) {
                            chartPanel
                            sidePanel
                                .frame(width: min(320, geometry.size.width * 0.32))
                        }
                    } else {
                        VStack(spacing: 18) {
                            chartPanel
                                .frame(maxHeight: geometry.size.height * 0.5)
                            sidePanel
                            Text("Rotate your phone for the widest graph view.")
                                .font(.caption)
                                .foregroundStyle(FormFitTheme.textSecondary)
                        }
                    }
                }
                .padding(20)
            }
            .onAppear {
                FormFitOrientationCoordinator.requestLandscape()
            }
            .onDisappear {
                FormFitOrientationCoordinator.restoreDefault()
            }
        }
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(scopeTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(FormFitTheme.textPrimary)

                    Text(graphHeaderSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(FormFitTheme.textSecondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(FormFitTheme.orange)
            }

            scopePicker

            Chart {
                ForEach(boundaryMarkers) { marker in
                    RuleMark(x: .value("Boundary", marker.time))
                        .foregroundStyle(FormFitTheme.cardBorder.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(marker.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(FormFitTheme.textSecondary)
                        }
                }

                ForEach(channelPoints) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Degrees", point.value),
                        series: .value("Channel", point.channel.title)
                    )
                    .foregroundStyle(point.channel.color)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: point.channel == .roll ? 3 : 2,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(FormFitTheme.cardBorder.opacity(0.5))
                    AxisValueLabel {
                        if let time = value.as(Double.self) {
                            Text("\(time.formatted(.number.precision(.fractionLength(1))))s")
                                .foregroundStyle(FormFitTheme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(FormFitTheme.cardBorder.opacity(0.5))
                    AxisValueLabel {
                        if let degrees = value.as(Double.self) {
                            Text("\(degrees.formatted(.number.precision(.fractionLength(0))))°")
                                .foregroundStyle(FormFitTheme.textSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)

            HStack(spacing: 12) {
                ForEach(Channel.allCases) { channel in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(channel.color)
                            .frame(width: 10, height: 10)
                        Text(channel.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FormFitTheme.textSecondary)
                    }
                }
            }
        }
        .formFitCard()
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rep Metrics")
                .font(.title3.weight(.bold))
                .foregroundStyle(FormFitTheme.textPrimary)

            GraphMetricCard(
                title: "Range of Motion",
                value: rangeText,
                accent: FormFitTheme.warning,
                subtitle: selectedScope == .fullSession ? "Average across detected reps" : "Detected from selected rep"
            )

            GraphMetricCard(
                title: "Concentric",
                value: concentricText,
                accent: FormFitTheme.info,
                subtitle: selectedScope == .fullSession ? "Average lowering phase" : "Selected rep lowering phase"
            )

            GraphMetricCard(
                title: "Eccentric",
                value: eccentricText,
                accent: eccentricBadge.map(color(for:)) ?? FormFitTheme.textSecondary,
                subtitle: eccentricBadge?.label ?? "Not available yet"
            )

            GraphMetricCard(
                title: "Rendered Samples",
                value: "\(displayedSamples.count)",
                accent: FormFitTheme.orange,
                subtitle: selectedScope == .fullSession ? "Across the imported session" : "From the selected rep"
            )

            Spacer(minLength: 0)
        }
        .formFitCard()
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                scopeChip(
                    title: "Full Session",
                    subtitle: "\(session.repetitionCount) reps",
                    isSelected: selectedScope == .fullSession
                ) {
                    selectedScope = .fullSession
                }

                ForEach(repetitions, id: \.id) { repetition in
                    scopeChip(
                        title: "Rep \(repetition.index + 1)",
                        subtitle: repetition.eccentricTime.map { eccentricScore(duration: $0).label } ?? "Metrics pending",
                        isSelected: selectedScope == .repetition(repetition.id)
                    ) {
                        selectedScope = .repetition(repetition.id)
                    }
                }
            }
        }
    }

    private func scopeChip(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : FormFitTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : FormFitTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(FormFitTheme.primaryButtonGradient)
                            : AnyShapeStyle(FormFitTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isSelected
                                    ? FormFitTheme.orange.opacity(0.1)
                                    : FormFitTheme.cardBorder.opacity(0.8),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var yDomain: ClosedRange<Double> {
        let values = channelPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return -90...90
        }

        let padding = max(8, (maxValue - minValue) * 0.12)
        return (minValue - padding)...(maxValue + padding)
    }

    private func metricValues(_ keyPath: KeyPath<WorkoutRepetition, Double?>) -> Double? {
        switch selectedScope {
        case .fullSession:
            let values = repetitions.compactMap { $0[keyPath: keyPath] }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        case let .repetition(id):
            return repetitions.first(where: { $0.id == id })?[keyPath: keyPath]
        }
    }

    private func downsample(_ samples: [WorkoutMotionSample], maxCount: Int) -> [WorkoutMotionSample] {
        guard samples.count > maxCount, maxCount > 1 else { return samples }

        let step = max(1, samples.count / maxCount)
        var reduced = stride(from: 0, to: samples.count, by: step).map { samples[$0] }
        if let last = samples.last, reduced.last?.id != last.id {
            reduced.append(last)
        }
        return reduced
    }

    private func color(for score: EccentricScore) -> Color {
        switch score {
        case .good:
            return FormFitTheme.success
        case .slightlyFast:
            return FormFitTheme.warning
        case .tooFast:
            return FormFitTheme.danger
        }
    }
}

private struct GraphMetricCard: View {
    let title: String
    let value: String
    let accent: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FormFitTheme.textSecondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accent)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(FormFitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formFitCard()
    }
}

@MainActor
private enum FormFitOrientationCoordinator {
    static func requestLandscape() {
        guard let scene = activeWindowScene else { return }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: .landscape
        )
        scene.requestGeometryUpdate(preferences)
    }

    static func restoreDefault() {
        guard let scene = activeWindowScene else { return }

        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: .allButUpsideDown
        )
        scene.requestGeometryUpdate(preferences)
    }

    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }
}
