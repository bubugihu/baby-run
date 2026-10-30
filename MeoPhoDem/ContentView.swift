import SwiftUI
import SpriteKit

struct ContentView: View {
    // Scene cố định 1400x1000, phóng cho vừa màn hình iPad (cắt nhẹ hai mép nếu màn 4:3).
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 1400, height: 1000))
        scene.scaleMode = .aspectFill
        return scene
    }()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()

            // Khung camera nhỏ để người chơi biết mình còn trong hình.
            CameraPreview(session: BodyTracker.shared.session)
                .frame(width: 220, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.6), lineWidth: 2))
                .padding(24)
                .allowsHitTesting(false)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            BodyTracker.shared.start()
            VoiceMeter.shared.start()
        }
    }
}
