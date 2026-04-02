//
//  CollectorContentView.swift
//  FormFitWatch
//
//  Created by Saavan Kiran on 2/22/26.
//

import SwiftUI

struct CollectorContentView: View {
    @StateObject private var motion = MotionManager()
    
    private let cols = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        VStack {
            LazyVGrid(columns: cols, spacing: 10) {
                ControlTile(title: "Start", system: "play.fill") {
                    motion.armAndStart(prepDelay: 2.5, stillnessSeconds: 0.5)
                }
                .disabled(motion.isActive)
                
                ControlTile(title: "Stop", system: "pause.fill") {
                    motion.stop()
                }
                .disabled(!motion.isActive)
                
                ControlTile(title: "Clear", system: "trash") {
                    motion.clear()
                }
                .disabled(motion.isActive) //optional: disallow clearing mid-run
                
                ControlTile(title: "Save", system: "square.and.arrow.down") {
                    motion.saveCSV()
                }
                .disabled(motion.buffer.isEmpty || motion.isActive) // optional: disallow saving mid-run
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(8)
        .onAppear {
            WatchConnectivityManager.shared.activate()
        }
    }
}

private struct ControlTile: View {
    let title: String
    let system: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .font(.title2)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
    }
}

#Preview {
    CollectorContentView()
}
