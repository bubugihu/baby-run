import SwiftUI

/// Màn chọn nhân vật trước khi vào game: chụp ảnh khuôn mặt hoặc dùng con mèo.
struct FacePicker: View {
    var onDone: (UIImage?) -> Void

    @State private var captured: UIImage?
    @State private var countdown: Int?
    @State private var note: String?
    @State private var saved = FaceStore.load()

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.14).ignoresSafeArea()
            VStack(spacing: 26) {
                Text("Chọn nhân vật")
                    .font(.system(size: 46, weight: .heavy))
                Text(note ?? (captured == nil ? "Lại gần iPad, nhìn vào camera rồi bấm Chụp" : "Ảnh này được chưa?"))
                    .font(.system(size: 24, weight: .semibold))
                    .opacity(0.85)

                ZStack {
                    if let captured {
                        Image(uiImage: captured).resizable().scaledToFit()
                    } else {
                        CameraPreview(session: BodyTracker.shared.session)
                            .clipShape(Circle())
                        Circle()
                            .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 6, dash: [16, 10]))
                        if let countdown {
                            Text("\(countdown)")
                                .font(.system(size: 130, weight: .heavy))
                                .shadow(radius: 8)
                        }
                    }
                }
                .frame(width: 380, height: 380)

                HStack(spacing: 18) {
                    if let captured {
                        PickerButton(title: "✅ Dùng ảnh này", primary: true) {
                            FaceStore.save(captured)
                            onDone(captured)
                        }
                        PickerButton(title: "↻ Chụp lại") {
                            self.captured = nil
                            note = nil
                        }
                    } else {
                        PickerButton(title: "📸 Chụp", primary: true) { takePhoto() }
                            .disabled(countdown != nil)
                        if let saved {
                            PickerButton(title: "Dùng ảnh cũ", image: saved) { onDone(saved) }
                        }
                        PickerButton(title: "🐱 Dùng mèo") { onDone(nil) }
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func takePhoto() {
        guard InputHub.shared.cameraReady else {
            note = "Camera chưa sẵn sàng, thử lại sau giây lát nhé"
            return
        }
        note = nil
        Task { @MainActor in
            for n in [3, 2, 1] {
                countdown = n
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            countdown = nil
            BodyTracker.shared.captureFace { result in
                guard let result else {
                    note = "Chụp chưa được, thử lại nhé"
                    return
                }
                captured = result.image
                if !result.foundFace { note = "Chưa thấy rõ mặt. Lại gần hơn rồi chụp lại nhé" }
            }
        }
    }
}

private struct PickerButton: View {
    let title: String
    var image: UIImage? = nil
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let image {
                    Image(uiImage: image).resizable().frame(width: 40, height: 40)
                }
                Text(title).font(.system(size: 26, weight: .bold))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(primary ? Color.orange : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
