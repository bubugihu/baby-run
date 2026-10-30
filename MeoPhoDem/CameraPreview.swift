import SwiftUI
import AVFoundation

/// Khung xem camera trước (soi gương) ở góc màn hình.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = UIColor(white: 0.15, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        override func layoutSubviews() {
            super.layoutSubviews()
            setUpRotationIfNeeded()
            applyRotation()
        }

        private func setUpRotationIfNeeded() {
            guard coordinator == nil, window != nil,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyRotation() }
            }
        }

        private func applyRotation() {
            guard let coordinator, let connection = previewLayer.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}
