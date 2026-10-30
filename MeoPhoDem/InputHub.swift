import CoreGraphics
import QuartzCore

/// Đầu vào mới nhất từ camera và micro. Chỉ đọc/ghi trên main thread.
final class InputHub {
    static let shared = InputHub()

    /// Vị trí thân người (hông) trong ảnh camera, toạ độ chuẩn hoá 0...1.
    var bodyPoint: CGPoint?
    var lastBodyTime: CFTimeInterval = 0
    /// Camera thấy cả hông và đầu gối (người đứng đủ xa để chơi).
    var fullBodyVisible = false
    /// Âm lượng hiện tại, dBFS (khoảng -80 im lặng tới 0 rất to).
    var levelDB: Float = -80

    var cameraReady = false
    var micReady = false
    var cameraProblem: String?
    var micProblem: String?

    func bodyVisible(at now: CFTimeInterval) -> Bool {
        bodyPoint != nil && now - lastBodyTime < 0.6
    }
}
