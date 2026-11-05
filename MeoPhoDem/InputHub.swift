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
    /// Tay và vai (cho game Action). Toạ độ ảnh camera nhưng x đã nhân với tỉ lệ khung
    /// (rộng/cao) để một đơn vị theo x dài bằng một đơn vị theo y. y hướng lên.
    var hands: HandPose?
    var handsTime: CFTimeInterval = 0
    /// Tăng 1 mỗi khi có khung hình camera mới đã xử lý (để game biết có mẫu tay mới).
    var handsFrame = 0
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

struct HandPose {
    /// Giữa hai vai (hoặc cổ).
    var chest: CGPoint
    /// Khoảng cách hai vai, dùng làm thước đo để không phụ thuộc người đứng xa hay gần.
    var shoulderWidth: CGFloat
    /// Hướng "lên" của thân người trong ảnh (vector đơn vị). Đúng cả khi camera bị xoay.
    var up: CGVector
    var left: CGPoint?
    var right: CGPoint?
}
