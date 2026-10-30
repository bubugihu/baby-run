import AVFoundation
import Vision
import QuartzCore

/// Camera trước + Vision body pose → vị trí thân người, ~20 lần/giây.
final class BodyTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = BodyTracker()

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "body.session")
    private let videoQueue = DispatchQueue(label: "body.video")
    private let request = VNDetectHumanBodyPoseRequest()
    private var lastProcess: CFTimeInterval = 0
    private var started = false

    private var output: AVCaptureVideoDataOutput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    func start() {
        guard !started else { return }
        started = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.fail("Chưa cho phép camera. Vào Cài đặt → Mèo Phố Đêm → bật Camera.") }
                }
            }
        default:
            fail("Chưa cho phép camera. Vào Cài đặt → Mèo Phố Đêm → bật Camera.")
        }
    }

    private func fail(_ message: String) {
        InputHub.shared.cameraProblem = message
    }

    private func configureAndRun() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            fail("Không mở được camera trước.")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // đủ cho Vision, nhẹ máy
        if session.canAddInput(input) { session.addInput(input) }

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(out) { session.addOutput(out) }
        if let connection = out.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        session.commitConfiguration()
        output = out

        // Xoay ảnh theo hướng iPad. Không bắt buộc đúng tuyệt đối vì bước hiệu chỉnh
        // tự đo hướng trái/phải, nhưng giúp Vision nhận người tốt hơn.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation()
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyRotation() }
        }

        sessionQueue.async { self.session.startRunning() }
        InputHub.shared.cameraReady = true
    }

    private func applyRotation() {
        guard let coordinator = rotationCoordinator,
              let connection = output?.connection(with: .video) else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastProcess >= 1.0 / 20 else { return }
        lastProcess = now

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return }
        let point = Self.bodyCenter(of: Self.mainPerson(request.results ?? []))

        DispatchQueue.main.async {
            guard let point else { return }
            InputHub.shared.bodyPoint = point
            InputHub.shared.lastBodyTime = now
        }
    }

    /// Nếu có nhiều người trong hình, lấy người to nhất (đứng gần nhất).
    private static func mainPerson(_ people: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        people.max { spread(of: $0) < spread(of: $1) }
    }

    private static func spread(of person: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? person.recognizedPoints(.all) else { return 0 }
        let good = points.values.filter { $0.confidence > 0.3 }.map(\.location)
        guard let minY = good.map(\.y).min(), let maxY = good.map(\.y).max(),
              let minX = good.map(\.x).min(), let maxX = good.map(\.x).max() else { return 0 }
        return max(maxY - minY, maxX - minX)
    }

    /// Ưu tiên hông (ổn định nhất khi bước ngang), không có thì dùng vai/cổ.
    private static func bodyCenter(of person: VNHumanBodyPoseObservation?) -> CGPoint? {
        guard let person, let points = try? person.recognizedPoints(.all) else { return nil }
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            return p.location
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

        if let root = joint(.root) { return root }
        if let l = joint(.leftHip), let r = joint(.rightHip) { return mid(l, r) }
        if let l = joint(.leftShoulder), let r = joint(.rightShoulder) { return mid(l, r) }
        return joint(.neck)
    }
}
