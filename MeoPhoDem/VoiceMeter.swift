import AVFoundation
import UIKit
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

        // Bật AirPlay/đổi tai nghe làm engine dừng; cuộc gọi hay Siri làm micro bị ngắt.
        // Cả hai trường hợp đều khởi động lại để tiếng hét không "mất" giữa ván.
        let center = NotificationCenter.default
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restart()
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, InputHub.shared.micReady, !self.engine.isRunning else { return }
            self.restart()
        }

        startEngine()
    }

    private func restart() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngine()
    }

    private func startEngine() {
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
