import AVFoundation
import QuartzCore

/// Nhạc nền vui tai tự tổng hợp (trống, bass, giai điệu ngũ cung), không cần file âm thanh
/// nên không vướng bản quyền. Chạy ở nhịp `bpm`, lặp lại mãi.
final class DanceMusic {
    static let shared = DanceMusic()
    static let bpm = 100.0

    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private(set) var startTime: CFTimeInterval = 0

    private let sampleRate = 44100.0
    private var frame: Int64 = 0
    private var noiseState: UInt32 = 12345

    /// Giai điệu: mỗi phần tử là một nốt móc đơn (nửa nhịp), -1 là nghỉ. 16 nốt = 2 ô nhịp.
    private let melody = [0, 2, 4, 2, 3, 2, 1, -1,   0, 2, 4, 5, 4, 2, 3, -1]
    private let melodyHz: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    /// Bass theo từng nhịp (Hz): C - C - G - A.
    private let bassHz: [Double] = [65.41, 65.41, 98.0, 110.0]

    var isRunning: Bool { engine.isRunning }

    func start() {
        guard !engine.isRunning else { return }
        if node == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
            let source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
                self.render(frameCount: Int(frameCount), audioBufferList)
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            node = source
        }
        frame = 0
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            startTime = CACurrentMediaTime()
        } catch {
            // Không có nhạc thì game vẫn chơi được.
        }
    }

    func stop() {
        engine.stop()
    }

    private func noise() -> Double {
        noiseState = noiseState &* 1664525 &+ 1013904223
        return Double(noiseState >> 8) / Double(1 << 24) * 2 - 1
    }

    private func render(frameCount: Int, _ list: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let secondsPerBeat = 60.0 / Self.bpm
        for i in 0..<frameCount {
            let t = Double(frame + Int64(i)) / sampleRate
            let beat = t / secondsPerBeat
            let beatIndex = Int(beat)
            let tb = (beat - Double(beatIndex)) * secondsPerBeat              // giây từ đầu nhịp
            let eighth = Int(beat * 2)
            let te = (beat * 2 - Double(eighth)) * secondsPerBeat / 2         // giây từ đầu nốt móc

            // Trống đạp mỗi nhịp.
            let kick = sin(2 * .pi * (45 * tb + 2 * (1 - exp(-30 * tb)))) * exp(-9 * tb) * 0.55

            // Chũm chọe: nhỏ ở nốt chẵn, to hơn ở nốt lẻ (đánh ngược nhịp).
            let hatLevel = eighth % 2 == 1 ? 0.14 : 0.06
            let hat = noise() * exp(-70 * te) * hatLevel

            // Bass tam giác theo nhịp.
            let bf = bassHz[beatIndex % bassHz.count]
            let bassPhase = (t * bf).truncatingRemainder(dividingBy: 1)
            let bass = (abs(bassPhase * 4 - 2) - 1) * exp(-3 * tb) * 0.22

            // Giai điệu: sóng sin + họa âm nhẹ, vào nhanh, tắt dần.
            var lead = 0.0
            let note = melody[eighth % melody.count]
            if note >= 0 {
                let f = melodyHz[note]
                let env = min(te / 0.005, 1) * exp(-5 * te)
                lead = (sin(2 * .pi * f * te) + 0.3 * sin(4 * .pi * f * te)) * env * 0.16
            }

            let mixed = tanh((kick + hat + bass + lead) * 0.9)
            let sample = Float(mixed * 0.6)
            for buffer in buffers {
                let out = buffer.mData?.assumingMemoryBound(to: Float.self)
                out?[i] = sample
            }
        }
        frame += Int64(frameCount)
    }
}
