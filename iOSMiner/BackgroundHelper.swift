//
//  BackgroundHelper.swift
//  iOSMiner
//
//  Keeps the app alive in the background using a silent audio session.
//  On jailbroken devices this is the most reliable approach.
//

import AVFoundation
import Foundation

@Observable
final class BackgroundHelper {
    private(set) var isBackgroundEnabled = false
    private var audioPlayer: AVAudioPlayer?

    func enableBackground() {
        guard !isBackgroundEnabled else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)

            // Generate a tiny silent WAV in memory (1 second, 8kHz, mono, 8-bit silence)
            let sampleRate: Double = 8000
            let duration: Double = 1.0
            let numSamples = Int(sampleRate * duration)

            var wavData = Data()
            // RIFF header
            let dataSize = UInt32(numSamples)
            let fileSize = UInt32(36 + numSamples)
            wavData.append("RIFF".data(using: .ascii)!)
            wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
            wavData.append("WAVE".data(using: .ascii)!)
            // fmt chunk
            wavData.append("fmt ".data(using: .ascii)!)
            wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // chunk size
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })   // PCM
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })   // mono
            wavData.append(withUnsafeBytes(of: UInt32(8000).littleEndian) { Data($0) }) // sample rate
            wavData.append(withUnsafeBytes(of: UInt32(8000).littleEndian) { Data($0) }) // byte rate
            wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })   // block align
            wavData.append(withUnsafeBytes(of: UInt16(8).littleEndian) { Data($0) })   // bits per sample
            // data chunk
            wavData.append("data".data(using: .ascii)!)
            wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
            wavData.append(Data(repeating: 128, count: numSamples)) // 128 = silence for unsigned 8-bit

            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1  // loop forever
            player.volume = 0.0
            player.play()
            audioPlayer = player
            isBackgroundEnabled = true
            print("[Background] Silent audio session started")
        } catch {
            print("[Background] Failed to start audio session: \(error)")
        }
    }

    func disableBackground() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isBackgroundEnabled = false
        print("[Background] Audio session stopped")
    }
}
