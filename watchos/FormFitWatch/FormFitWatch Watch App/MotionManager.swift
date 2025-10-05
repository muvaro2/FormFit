//
//  MotionManager.swift
//  FormFitWatch
//
//  Created by Saavan Kiran on 10/5/25.
//

import Foundation
import CoreMotion
import Combine

struct MotionSample: Identifiable {
    let id = UUID() //Unique id for each data sample
    let timestamp: TimeInterval
    
    // Linear acceleration (m/s^2) without gravity
    let ax, ay, az: Double
    
    // Rotation rate (rad/s)
    let gx, gy, gz: Double
    
    // Orientation (radians)
    let roll, pitch, yaw: Double
}

final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    
    // Tick rate in milliseconds (changeable later from the UI)
    @Published var tickMs: Double = 50 //Published is used by publisher through Combine
    @Published private(set) var latest: MotionSample?
    @Published private(set) var buffer: [MotionSample] = []
    
    @Published private(set) var isRunning = false
    
    @Published private(set) var lastSaveMessage: String?
    
    private let maxBuffer = 5000 //5000 * 50 = 250000 ms or 250 seconds of data can be buffered
    
    func start() {
        guard motion.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available on this device/simulator.")
            return
        }
        motion.deviceMotionUpdateInterval = tickMs / 1000.0 //setting the interval into manager
        isRunning = true
        
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, err in guard let self, let m = dm, err == nil else {return} //complicated handler but equivalent of saying “Only proceed if self still exists, a motion reading dm is present (call it m), and there’s no error.”
            
            let s = MotionSample(
                timestamp: m.timestamp,
                ax: m.userAcceleration.x, ay: m.userAcceleration.y, az: m.userAcceleration.z,
                gx: m.rotationRate.x, gy: m.rotationRate.y, gz: m.rotationRate.z,
                roll: m.attitude.roll, pitch: m.attitude.pitch, yaw: m.attitude.yaw
            )
            
            self.latest = s //updates latest
            self.buffer.append(s) //adds s to buffer
            if self.buffer.count > self.maxBuffer { //recycles buffer if full
                self.buffer.removeFirst(self.buffer.count - self.maxBuffer) //yes this is O(n) -> fine for prototyping, we can switch to O(1) somehow later
            }
            
        }
    }
        
    func stop() {
        motion.stopDeviceMotionUpdates()
        isRunning = false
    }
    
    func clear() {
        buffer.removeAll()
        latest = nil
    }
    
    // Update the tick rate; if we’re running, restart updates so it takes effect.
    func updateTick(ms: Double) {
        tickMs = ms
        if isRunning {
            stop()
            start()
        }
    }
    
    // Save the current buffer to a CSV file in the app's Documents folder.
    func saveCSV() {
        guard !buffer.isEmpty else {
            lastSaveMessage = "Nothing to save (buffer is empty)."
            print("CSV: buffer empty — not saving.")
            return
        }
        do {
            // File name like: formfit-20251005-130742-50ms.csv
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let fname = "formfit-\(df.string(from: Date()))-\(Int(tickMs))ms.csv"

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! //cant access this directly from watch; must transfer to phone to read via WatchConnectivity
            let url  = docs.appendingPathComponent(fname)

            var csv = "idx,timestamp,ax,ay,az,gx,gy,gz,roll,pitch,yaw\n" //header row
            csv.reserveCapacity(buffer.count * 120) //hints how many characters to pre-allocate to reduce reallocations. 120 is a rough per-row guess; safe to tweak.

            for (i, s) in buffer.enumerated() {
                csv +=  "\(i),\(s.timestamp),\(s.ax),\(s.ay),\(s.az),\(s.gx),\(s.gy),\(s.gz),\(s.roll),\(s.pitch),\(s.yaw)\n"
                //solid readable lines of data that can be processed on phone
            }

            try csv.write(to: url, atomically: true, encoding: .utf8)
            //Try so that if there is error, jumps to catch
            //atomically: True writes to a temp file then renames → avoids partially written/corrupted files if something interrupts.
            //encoding: .utf8 makes the file a standard UTF-8 CSV
            
            lastSaveMessage = "Saved \(buffer.count) samples → \(fname)"
            print("CSV saved at: \(url)")
        } catch {
            lastSaveMessage = "Save failed: \(error.localizedDescription)"
            print("CSV save failed: \(error)")
        }
    }
}
