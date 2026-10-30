import AVFoundation
import Accelerate

/// Đo âm lượng micro liên tục (không ghi âm), cập nhật ~100 lần/giây.
final class VoiceMeter {
    static let shared = VoiceMeter()

    private let engine = AVAudioEngine()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted { self.configureAndRun() } else { self.fail("Chưa cho phép micro. Vào Cài đặt → Mèo Phố Đêm → bật Micro.") }
            }
        }
    }

    private func fail(_ message: String) {
        InputHub.shared.micProblem = message
    }

    private func configureAndRun() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // .measurement tắt tự động chỉnh âm lượng để độ to tiếng hét được đo đúng.
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowAirPlay])
            // Bộ đệm nhỏ → tiếng hét tới game sớm hơn (~10 ms thay vì ~23 ms).
            try? audioSession.setPreferredIOBufferDuration(0.01)
            try audioSession.setActive(true)
        } catch {
            fail("Không mở được micro: \(error.localizedDescription)")
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("Không tìm thấy micro.")
            return
        }

        input.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
            let db = 20 * log10(max(rms, 0.000_01))
            DispatchQueue.main.async { InputHub.shared.levelDB = db }
        }

        do {
            try engine.start()
            InputHub.shared.micReady = true
        } catch {
            fail("Không mở được micro: \(error.localizedDescription)")
        }
    }
}
