//
//  DiagnosticsContentView.swift
//  FormFitWatch Watch App
//
//  Created by Saavan Kiran on 10/4/25.
//

import SwiftUI

fileprivate extension Double {
    var f3: String { String(format: "%.3f", self) } // 3 decimal places
}

struct MetricCell: View {
    let label: String
    let value: Double
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.f3).font(.caption2).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct DiagnosticsContentView: View {
    //Own exactly one MotionManager instance for this view
    @StateObject private var motion = MotionManager()
    //@StateObject pretty much means “this view owns one MotionManager and keeps it alive across SwiftUI redraws.”
    
    // Bind the slider to MotionManager.tickMs but route writes through updateTicks(ms:)
    /*
    private var tickBinding: Binding<Double> {
        .init(get: {motion.tickMs }, set: { motion.updateTick(ms: $0) })
    }
    */
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {

                Text("FormFit • Watch")
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Button { motion.start() }  label: { Image(systemName: "play.fill") }
                        .disabled(motion.isRunning)

                    Button { motion.stop() }   label: { Image(systemName: "pause.fill") }
                        .disabled(!motion.isRunning)

                    Button { motion.clear() }  label: { Image(systemName: "trash") }

                    Button { motion.saveCSV() } label: { Image(systemName: "square.and.arrow.down") }
                        .disabled(motion.buffer.isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                /* //old slider bar
                VStack(spacing: 4) {
                    Text("Tick: \(Int(motion.tickMs)) ms")
                        .font(.caption2)

                    Slider(value: tickBinding, in: 10...200, step: 10)
                }
                 */
                
                
                if let msg = motion.lastSaveMessage {
                    Text(msg)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Text("Buffer samples: \(motion.buffer.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let s = motion.latest {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accel (m/s²)").font(.caption2)
                        HStack {
                            MetricCell(label: "ax", value: s.ax)
                            MetricCell(label: "ay", value: s.ay)
                            MetricCell(label: "az", value: s.az)
                        }

                        Text("Gyro (rad/s)").font(.caption2).padding(.top, 2)
                        HStack {
                            MetricCell(label: "gx", value: s.gx)
                            MetricCell(label: "gy", value: s.gy)
                            MetricCell(label: "gz", value: s.gz)
                        }

                        Text("Attitude (rad)").font(.caption2).padding(.top, 2)
                        HStack {
                            MetricCell(label: "roll",  value: s.roll)
                            MetricCell(label: "pitch", value: s.pitch)
                            MetricCell(label: "yaw",   value: s.yaw)
                        }
                    }
                } else {
                    Text("No samples yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .focusable(true) // helps the Digital Crown scroll the page
    }

}

#Preview {
    DiagnosticsContentView()
}
