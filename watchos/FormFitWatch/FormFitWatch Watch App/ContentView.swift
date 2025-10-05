//
//  ContentView.swift
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

struct ContentView: View {
    //Own exactly one MotionManager instance for this view
    @StateObject private var motion = MotionManager()
    //@StateObject pretty much means “this view owns one MotionManager and keeps it alive across SwiftUI redraws.”
    
    // Bind the slider to MotionManager.tickMs but route writes through updateTicks(ms:)
    private var tickBinding: Binding<Double> {
        .init(get: {motion.tickMs }, set: { motion.updateTick(ms: $0) })
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("FormFit • Watch")
                .font(.headline)
            
            HStack(spacing: 10) {
                Button { motion.start() }  label: { Image(systemName: "play.fill") }
                Button { motion.stop() }   label: { Image(systemName: "stop.fill") }
                Button { motion.clear() }  label: { Image(systemName: "trash") }
                Button { motion.saveCSV() } label: { Image(systemName: "square.and.arrow.down") }
                    .disabled(motion.buffer.isEmpty) //disabled if nothing to save
            }
            .buttonStyle(.bordered)      // smaller than .borderedProminent
            .controlSize(.mini)          // tighter padding
            
            VStack(spacing: 6) {
                Text("Tick: \(Int(motion.tickMs)) ms")
                    .font(.caption2)
                
                Slider(value: tickBinding, in: 10...200, step: 10) //10-200 ms
            }
            
            //displays last save message
            if let msg = motion.lastSaveMessage {
                Text(msg)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            
            //For now: a simple sanity check that we can observe state
            Text("Buffer samples: \(motion.buffer.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // would likely print : ⚠️ Device motion not available on this device/simulator.
            
            // Live readout
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
                Text("No samples yet").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
