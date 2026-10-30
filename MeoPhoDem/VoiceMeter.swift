import AVFoundation

/// Đo âm lượng micro liên tục (không ghi âm), cập nhật ~45 lần/giây.
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

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
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
