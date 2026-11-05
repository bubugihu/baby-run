import SwiftUI
import SpriteKit

/// Ba chế độ chơi của app.
enum GameMode {
    case running, action, dance
}

struct ContentView: View {
    @State private var mode: GameMode?

    var body: some View {
        Group {
            switch mode {
            case nil:
                ModeMenu { mode = $0 }
            case .running?:
                RunningView { mode = nil }
            case .action?:
                ActionView { mode = nil }
            case .dance?:
                DanceComingSoon { mode = nil }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            BodyTracker.shared.start()
        }
    }
}

/// Khung camera nhỏ ở góc để người chơi biết mình còn trong hình.
private struct CornerCamera: View {
    var body: some View {
        CameraPreview(session: BodyTracker.shared.session)
            .frame(width: 220, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.6), lineWidth: 2))
            .padding(24)
            .allowsHitTesting(false)
    }
}

// MARK: - Running: game chạy 3 làn (Mèo Phố Đêm)

struct RunningView: View {
    var onExit: () -> Void

    // Scene cố định 1400x1000, phóng cho vừa màn hình iPad (cắt nhẹ hai mép nếu màn 4:3).
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 1400, height: 1000))
        scene.scaleMode = .aspectFill
        return scene
    }()
    @State private var choosingFace = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ignoresSiblingOrder: thứ tự vẽ chỉ theo zPosition, SpriteKit gom lệnh vẽ được nhiều hơn.
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            if choosingFace {
                FacePicker(onBack: onExit) { face in
                    scene.setFace(face)
                    choosingFace = false
                }
            } else {
                // Chỉ một khung camera hiện ra mỗi lúc (màn chọn nhân vật có khung riêng).
                CornerCamera()
            }
        }
        .onAppear {
            scene.onChangeFace = { choosingFace = true }
            scene.onExit = onExit
            // Chỉ chế độ Running cần micro (hét để nhảy).
            VoiceMeter.shared.start()
        }
    }
}

// MARK: - Action: vung tay chém lồng đèn

struct ActionView: View {
    var onExit: () -> Void

    @State private var scene: ActionScene = {
        let scene = ActionScene(size: CGSize(width: 1400, height: 1000))
        scene.scaleMode = .aspectFill
        return scene
    }()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
            CornerCamera()
        }
        .onAppear { scene.onExit = onExit }
    }
}

// MARK: - Màn chọn chế độ

struct ModeMenu: View {
    var onPick: (GameMode) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.16), Color(red: 0.22, green: 0.09, blue: 0.30)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Text("bu học")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                    Text("Chọn trò chơi · chơi bằng cả cơ thể")
                        .font(.system(size: 24, weight: .semibold))
                        .opacity(0.8)
                }
                HStack(spacing: 28) {
                    ModeCard(icon: "🏃", title: "Running", subtitle: "Bước ngang để đổi làn\nHét để nhảy",
                             color: .orange) { onPick(.running) }
                    ModeCard(icon: "⚔️", title: "Action", subtitle: "Vung tay thật nhanh\nchém lồng đèn bay lên",
                             color: .pink) { onPick(.action) }
                    ModeCard(icon: "💃", title: "Dance", subtitle: "Sắp ra mắt", color: .purple,
                             comingSoon: true) { onPick(.dance) }
                }
            }
            .foregroundStyle(.white)
            .padding(40)
        }
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var comingSoon = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Text(icon).font(.system(size: 96))
                Text(title).font(.system(size: 40, weight: .heavy, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
            }
            .frame(width: 280, height: 360)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(color.opacity(comingSoon ? 0.25 : 0.55))
            )
            .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.35), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dance: chỗ để sẵn

struct DanceComingSoon: View {
    var onBack: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.18, green: 0.06, blue: 0.30), Color(red: 0.05, green: 0.05, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Text("💃🕺").font(.system(size: 110))
                Text("Dance").font(.system(size: 60, weight: .heavy, design: .rounded))
                Text("Sắp ra mắt! Trò chơi nhảy theo nhạc đang được lên ý tưởng.")
                    .font(.system(size: 26, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
                Button(action: onBack) {
                    Text("← Quay lại")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 18)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(40)
        }
    }
}
