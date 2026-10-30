import CoreGraphics

/// Ngưỡng đo được ở bước hiệu chỉnh đầu ván.
struct Calibration {
    // Vị trí thân người khi đứng giữa / bước trái / bước phải (toạ độ ảnh camera).
    private(set) var center = CGPoint(x: 0.5, y: 0.5)
    private var axis = CGVector(dx: 0.3, dy: 0)
    private(set) var leftT: CGFloat = -1
    private(set) var rightT: CGFloat = 1

    var noiseDB: Float = -50
    var shoutDB: Float = -15

    /// Mức to cần vượt để tính là một tiếng hét.
    var jumpThresholdDB: Float {
        noiseDB + max(8, (shoutDB - noiseDB) * 0.45)
    }

    /// Lưu 3 vị trí. Trả về false nếu trái và phải không nằm hai bên vị trí giữa.
    mutating func setPositions(center: CGPoint, left: CGPoint, right: CGPoint) -> Bool {
        let newAxis = CGVector(dx: right.x - left.x, dy: right.y - left.y)
        let lengthSq = newAxis.dx * newAxis.dx + newAxis.dy * newAxis.dy
        guard lengthSq > 0.06 * 0.06 else { return false }
        let old = (self.center, axis)
        self.center = center
        axis = newAxis
        let l = projection(left), r = projection(right)
        guard l < -0.25, r > 0.25 else {
            (self.center, axis) = old
            return false
        }
        leftT = l
        rightT = r
        return true
    }

    /// Vị trí người dọc theo hướng trái→phải: khoảng -1 là chỗ bước trái, +1 là chỗ bước phải.
    /// Tự đúng dù camera có lật gương hay xoay, vì hướng được đo lúc hiệu chỉnh.
    func projection(_ p: CGPoint) -> CGFloat {
        let lengthSq = axis.dx * axis.dx + axis.dy * axis.dy
        let d = (p.x - center.x) * axis.dx + (p.y - center.y) * axis.dy
        return d / (lengthSq / 2)
    }

    /// Làn 0 (trái), 1 (giữa), 2 (phải). Ranh giới nằm giữa vị trí giữa và vị trí bước,
    /// lệch về phía làn hiện tại một chút để không bị nhảy làn khi đứng sát ranh giới.
    func lane(for p: CGPoint, current: Int) -> Int {
        let t = projection(p)
        let margin: CGFloat = 0.12
        let leftEdge = leftT * 0.5 + (current == 0 ? margin : -margin)
        let rightEdge = rightT * 0.5 + (current == 2 ? -margin : margin)
        if t < leftEdge { return 0 }
        if t > rightEdge { return 2 }
        return 1
    }
}
