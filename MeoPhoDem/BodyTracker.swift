import AVFoundation
import Vision
import QuartzCore

/// Camera trước + Vision body pose → vị trí thân người, mỗi khung hình camera (~30 lần/giây).
final class BodyTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = BodyTracker()

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "body.session")
    private let videoQueue = DispatchQueue(label: "body.video")
    private let request = VNDetectHumanBodyPoseRequest()
    private var started = false
    private let photoLock = NSLock()
    private var pendingPhoto: ((FaceCropper.Result?) -> Void)?

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
                    if granted { self.configureAndRun() } else { self.fail("Chưa cho phép camera. Vào Cài đặt → bu học → bật Camera.") }
                }
            }
        default:
            fail("Chưa cho phép camera. Vào Cài đặt → bu học → bật Camera.")
        }
    }

    /// Lấy khung hình camera kế tiếp, cắt khuôn mặt, trả kết quả trên main thread.
    func captureFace(_ completion: @escaping (FaceCropper.Result?) -> Void) {
        photoLock.lock()
        pendingPhoto = completion
        photoLock.unlock()
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
        // Xử lý mọi khung hình: hàng đợi tuần tự + alwaysDiscardsLateVideoFrames tự bỏ
        // khung cũ nếu Vision chưa xong, nên không bị dồn trễ.
        let now = CACurrentMediaTime()

        photoLock.lock()
        let photo = pendingPhoto
        pendingPhoto = nil
        photoLock.unlock()
        if let photo {
            let result = CMSampleBufferGetImageBuffer(sampleBuffer).flatMap(FaceCropper.crop)
            DispatchQueue.main.async { photo(result) }
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return }
        let person = Self.mainPerson(request.results ?? [])
        let body = Self.bodyCenter(of: person)
        var aspect: CGFloat = 4.0 / 3.0
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
            // Ảnh đã được xoay theo videoRotationAngle nên bộ đệm có thể là dọc hoặc ngang.
            if h > 0 { aspect = w / h }
        }
        let hands = Self.handPose(of: person, aspect: aspect)

        DispatchQueue.main.async {
            if let hands {
                InputHub.shared.hands = hands
                InputHub.shared.handsTime = now
                InputHub.shared.handsFrame &+= 1
            }
            guard let body else { return }
            InputHub.shared.bodyPoint = body.point
            InputHub.shared.fullBodyVisible = body.fullBody
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

    /// Vị trí hai cổ tay so với ngực. Cổ tay hay bị mờ khi vung nhanh nên ngưỡng tin cậy thấp hơn.
    private static func handPose(of person: VNHumanBodyPoseObservation?, aspect: CGFloat) -> HandPose? {
        guard let person, let points = try? person.recognizedPoints(.all) else { return nil }
        func joint(_ name: VNHumanBodyPoseObservation.JointName, _ minConfidence: Float = 0.3) -> CGPoint? {
            guard let p = points[name], p.confidence > minConfidence else { return nil }
            return CGPoint(x: p.location.x * aspect, y: p.location.y)
        }
        guard let ls = joint(.leftShoulder), let rs = joint(.rightShoulder) else { return nil }
        let width = hypot(rs.x - ls.x, rs.y - ls.y)
        guard width > 0.02 else { return nil }
        let chest = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        // Hướng lên: từ hông tới ngực, không thấy hông thì từ ngực tới mũi.
        var up = CGVector(dx: 0, dy: 1)
        if let lh = joint(.leftHip), let rh = joint(.rightHip) {
            up = CGVector(dx: chest.x - (lh.x + rh.x) / 2, dy: chest.y - (lh.y + rh.y) / 2)
        } else if let nose = joint(.nose) {
            up = CGVector(dx: nose.x - chest.x, dy: nose.y - chest.y)
        }
        let length = hypot(up.dx, up.dy)
        up = length > 0.01 ? CGVector(dx: up.dx / length, dy: up.dy / length) : CGVector(dx: 0, dy: 1)
        return HandPose(chest: chest, shoulderWidth: width, up: up,
                        left: joint(.leftWrist, 0.15), right: joint(.rightWrist, 0.15))
    }

    /// Ưu tiên hông (ổn định nhất khi bước ngang), không có thì dùng vai/cổ.
    /// `fullBody` = thấy cả hông lẫn đầu gối, tức là người đứng đủ xa.
    private static func bodyCenter(of person: VNHumanBodyPoseObservation?) -> (point: CGPoint, fullBody: Bool)? {
        guard let person, let points = try? person.recognizedPoints(.all) else { return nil }
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            return p.location
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

        let fullBody = (joint(.leftHip) != nil || joint(.rightHip) != nil)
            && (joint(.leftKnee) != nil || joint(.rightKnee) != nil)
        if let root = joint(.root) { return (root, fullBody) }
        if let l = joint(.leftHip), let r = joint(.rightHip) { return (mid(l, r), fullBody) }
        if let l = joint(.leftShoulder), let r = joint(.rightShoulder) { return (mid(l, r), false) }
        return joint(.neck).map { ($0, false) }
    }
}
