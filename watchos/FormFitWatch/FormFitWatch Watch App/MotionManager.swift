//
//  MotionManager.swift
//  FormFitWatch
//
//  Created by Saavan Kiran on 10/5/25.
//

import Foundation
import CoreMotion
import Combine
import WatchKit

struct MotionSample: Identifiable {
    let id = UUID() //Unique id for each data sample
    
    // Raw Core Motion timestamps
    let timestamp: TimeInterval
    
    // Time since recording
    let t: TimeInterval
    
    // Linear acceleration (g units) without gravity
    let ax, ay, az: Double
    
    // Rotation rate (rad/s)
    let gx, gy, gz: Double
    
    // Orientation (radians)
    let roll, pitch, yaw: Double
}

final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    
    // Tick rate in milliseconds (changeable later from the UI)
    // @Published var tickMs: Double = 10 //Published is used by publisher through Combine
    let tickMs: Double = 10
    @Published private(set) var latest: MotionSample?
    @Published private(set) var buffer: [MotionSample] = []
    
    @Published private(set) var isRunning = false
    
    @Published private(set) var lastSaveMessage: String?
    
    // For the collector UI, alias to existing state
    var isActive: Bool { isRunning }
    
    // Arming state (prep delay + stillness detection)
    private var allowStillnessCheck = false
    private var stillStartTimestamp: TimeInterval?
    private var prepWorkItem: DispatchWorkItem?
    
    // While arming, we sample but do not append until we "start gun"
    private var isRecording = false
    private var recordingStartTimestamp: TimeInterval?
    private var referenceAttitude: CMAttitude?
    
    // Tune thresholds later
    // Note: userAcceleration is in "g" units
    private let accelStillThreshold = 0.03 // g
    private let gyroStillThreshold = 0.20 // rad/s
    
    private let maxBuffer = 10000 //5000 * 50 = 250000 ms or 250 seconds of data can be buffered
    
    func start() {
        guard motion.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available on this device/simulator.")
            return
        }
        motion.deviceMotionUpdateInterval = tickMs / 1000.0 //setting the interval into manager
        isRunning = true
        recordingStartTimestamp = nil
        referenceAttitude = nil
        
        motion.startDeviceMotionUpdates(using: chosenReferenceFrame(), to: .main) { [weak self] dm, err in
            guard let self, let m = dm, err == nil else { return }

            if self.recordingStartTimestamp == nil {
                self.recordingStartTimestamp = m.timestamp
            }

            let s = self.makeSample(from: m)

            self.latest = s
            self.buffer.append(s)
            if self.buffer.count > self.maxBuffer {
                self.buffer.removeFirst(self.buffer.count - self.maxBuffer)
            }
        }
    }
        
    func stop() {
        prepWorkItem?.cancel()
        prepWorkItem = nil
        
        motion.stopDeviceMotionUpdates()
        isRunning = false
        
        isRecording = false
        allowStillnessCheck = false
        stillStartTimestamp = nil
        recordingStartTimestamp = nil
        referenceAttitude = nil
    }
    
    func clear() {
        buffer.removeAll()
        latest = nil
        recordingStartTimestamp = nil
        referenceAttitude = nil
    }
    
    func armAndStart(prepDelay: Double = 2.5, stillnessSeconds: Double = 0.5) {
        guard motion.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available on this device/simulator.")
            return
        }
        
        // If already running, reset cleanly
        if isRunning { stop() }
        clear()
        lastSaveMessage = nil
        
        isRunning = true
        isRecording = false
        allowStillnessCheck = false
        stillStartTimestamp = nil
        recordingStartTimestamp = nil
        referenceAttitude = nil
        
        motion.deviceMotionUpdateInterval = tickMs / 1000.0
        
        //After prepDelay, begin checking stillness
        prepWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.allowStillnessCheck = true
            self.stillStartTimestamp = nil
        }
        prepWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + prepDelay, execute: item)
        
        motion.startDeviceMotionUpdates(using: chosenReferenceFrame(), to: .main) { [weak self] dm, err in
            guard let self, let m = dm, err == nil else { return }
            
            let s = self.makeSample(from: m)
            
            self.latest = s
            
            // Once recording has started, append normally
            if self.isRecording {
                self.buffer.append(s)
                if self.buffer.count > self.maxBuffer {
                    self.buffer.removeFirst(self.buffer.count - self.maxBuffer)
                }
                return
            }
            
            // Otherwise we are arming, wait until prepDelay is done
            guard self.allowStillnessCheck else { return }
            
            let accMag = sqrt(s.ax*s.ax + s.ay*s.ay + s.az*s.az)
            let gyrMag = sqrt(s.gx*s.gx + s.gy*s.gy + s.gz*s.gz)
            let still = (accMag < self.accelStillThreshold) && (gyrMag < self.gyroStillThreshold)
            
            if still {
                if self.stillStartTimestamp == nil { self.stillStartTimestamp = m.timestamp }
                if let t0 = self.stillStartTimestamp, (m.timestamp - t0) >= stillnessSeconds {
                    WKInterfaceDevice.current().play(.start)

                    // define time zero + attitude zero at the beep
                    self.recordingStartTimestamp = m.timestamp
                    self.referenceAttitude = m.attitude.copy() as? CMAttitude

                    self.buffer.removeAll()

                    let startSample = self.makeSample(from: m)
                    self.latest = startSample
                    self.buffer.append(startSample)

                    self.isRecording = true
                    self.allowStillnessCheck = false
                    self.stillStartTimestamp = nil
                }
            } else {
                self.stillStartTimestamp = nil
            }
        }
    }
    
    // Update the tick rate; if we’re running, restart updates so it takes effect.
    /*
    func updateTick(ms: Double) {
        tickMs = ms
        if isRunning {
            stop()
            start()
        }
    }
     */
    
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

            var csv = "t,timestamp,ax,ay,az,gx,gy,gz,roll,pitch,yaw\n" //header row
            csv.reserveCapacity(buffer.count * 120) //hints how many characters to pre-allocate to reduce reallocations. 120 is a rough per-row guess; safe to tweak.

            for s in buffer {
                csv +=  "\(s.t),\(s.timestamp),\(s.ax),\(s.ay),\(s.az),\(s.gx),\(s.gy),\(s.gz),\(s.roll),\(s.pitch),\(s.yaw)\n"
                //solid readable lines of data that can be processed on phone
            }

            try csv.write(to: url, atomically: true, encoding: .utf8)
            //Try so that if there is error, jumps to catch
            //atomically: True writes to a temp file then renames → avoids partially written/corrupted files if something interrupts.
            //encoding: .utf8 makes the file a standard UTF-8 CSV
            WatchConnectivityManager.shared.transferFile(url)
            lastSaveMessage = "Sent to phone: \(fname)"
            
            print("CSV saved at: \(url)")
        } catch {
            lastSaveMessage = "Save failed: \(error.localizedDescription)"
            print("CSV save failed: \(error)")
        }
    }
    
    // Helper function that makes the sample
    private func makeSample(from m: CMDeviceMotion) -> MotionSample {
        let t0 = recordingStartTimestamp ?? m.timestamp
        let relativeT = m.timestamp - t0
        
        let roll: Double
        let pitch: Double
        let yaw: Double
        
        if let ref = referenceAttitude {
            let rel = m.attitude.copy() as! CMAttitude
            rel.multiply(byInverseOf: ref)
            roll = rel.roll
            pitch = rel.pitch
            yaw = rel.yaw
        } else {
            roll = m.attitude.roll
            pitch = m.attitude.pitch
            yaw = m.attitude.yaw
        }
        
        return MotionSample(
            timestamp: m.timestamp,
            t: relativeT,
            ax: m.userAcceleration.x,
            ay: m.userAcceleration.y,
            az: m.userAcceleration.z,
            gx: m.rotationRate.x,
            gy: m.rotationRate.y,
            gz: m.rotationRate.z,
            roll: roll,
            pitch: pitch,
            yaw: yaw
        )
    }


    //Checks if arbitrary corrected z vertical is even available
    private func chosenReferenceFrame() -> CMAttitudeReferenceFrame {
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        
        if available.contains(.xArbitraryCorrectedZVertical) {
            return .xArbitraryCorrectedZVertical
        }
        
        // Fallback if that frame is unavailable on the current watch
        return .xArbitraryZVertical
    }
}



