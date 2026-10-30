import UIKit
import Vision
import CoreImage

/// Cắt khuôn mặt từ một khung hình camera thành ảnh tròn để làm nhân vật.
enum FaceCropper {
    struct Result {
        let image: UIImage
        let foundFace: Bool
    }

    private static let context = CIContext()

    static func crop(_ buffer: CVPixelBuffer) -> Result? {
        let frame = CIImage(cvPixelBuffer: buffer)
        let extent = frame.extent

        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])

        var square: CGRect
        let face = request.results?.max { $0.boundingBox.width < $1.boundingBox.width }
        if let face {
            // Vision và CIImage cùng gốc toạ độ ở góc dưới trái.
            let box = face.boundingBox
            let rect = CGRect(x: box.minX * extent.width, y: box.minY * extent.height,
                              width: box.width * extent.width, height: box.height * extent.height)
            let side = max(rect.width, rect.height) * 1.7 // lấy thêm tóc và cằm
            square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2 + rect.height * 0.1, width: side, height: side)
        } else {
            let side = min(extent.width, extent.height) * 0.6
            square = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2, width: side, height: side)
        }
        square = square.intersection(extent).integral
        guard !square.isEmpty, let cgImage = context.createCGImage(frame, from: square) else { return nil }

        let size = CGSize(width: 360, height: 360)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            ctx.cgContext.saveGState()
            UIBezierPath(ovalIn: circle).addClip()
            UIImage(cgImage: cgImage).draw(in: circle)
            ctx.cgContext.restoreGState()
            let ring = UIBezierPath(ovalIn: circle)
            ring.lineWidth = 12
            UIColor.white.setStroke()
            ring.stroke()
        }
        return Result(image: image, foundFace: face != nil)
    }
}

/// Lưu ảnh khuôn mặt lần trước để lần sau khỏi chụp lại.
enum FaceStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("face.png")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func save(_ image: UIImage) {
        try? image.pngData()?.write(to: url, options: .atomic)
    }
}
