import SpriteKit
import UIKit
import QuartzCore

/// Chế độ Dance "Múa theo mẫu": nhạc vui chạy, màn hình hiện một tư thế đơn giản,
/// bé làm giống để nhận sao. Không bị phạt: làm chưa kịp thì sang tư thế sau.
/// Chỉ cần camera thấy hai tay (so với vai), nên đứng cách iPad ~1,5–2 m là được.
final class DanceScene: SKScene {

    // MARK: - Tinh chỉnh (dành cho bé 5–6 tuổi: dễ tha lỗi)

    private enum Tune {
        static let poseCount = 10
        static let beatsPerPose = 6                // ~3,6 giây mỗi tư thế ở 100 nhịp/phút
        static let restBeats = 1.5                 // nghỉ giữa hai tư thế
        static let holdTime: TimeInterval = 0.5    // giữ giống chừng này là được sao
        static let avgTolerance: CGFloat = 0.8     // sai số trung bình của hai cổ tay (đơn vị = bề rộng vai)
        static let maxTolerance: CGFloat = 1.2     // sai số tối đa của một cổ tay
        static let scale: CGFloat = 112            // px mỗi đơn vị trong khung người que
        static let handsUpHold: TimeInterval = 0.8
    }

    /// Tư thế: vị trí hai cổ tay so với ngực. x sang phải của người nhìn vào màn hình
    /// (như soi gương), y lên trên, đơn vị = bề rộng vai. Vai nằm ở x = ±0,5.
    /// Toàn tư thế tay, không có cái nào khó (không trồng cây chuối!).
    private struct Pose {
        let name: String
        let left: CGPoint    // tay bên trái màn hình
        let right: CGPoint   // tay bên phải màn hình
    }

    private static let poses: [Pose] = [
        Pose(name: "Giơ hai tay lên cao", left: CGPoint(x: -0.6, y: 1.6), right: CGPoint(x: 0.6, y: 1.6)),
        Pose(name: "Dang hai tay như cánh chim", left: CGPoint(x: -2.0, y: 0), right: CGPoint(x: 2.0, y: 0)),
        Pose(name: "Hai tay chữ V", left: CGPoint(x: -1.3, y: 1.3), right: CGPoint(x: 1.3, y: 1.3)),
        Pose(name: "Hai tay chống hông", left: CGPoint(x: -1.0, y: -1.3), right: CGPoint(x: 1.0, y: -1.3)),
        Pose(name: "Hai tay lên đầu", left: CGPoint(x: -0.35, y: 0.8), right: CGPoint(x: 0.35, y: 0.8)),
        Pose(name: "Vỗ tay trước ngực", left: CGPoint(x: -0.1, y: -0.5), right: CGPoint(x: 0.1, y: -0.5)),
        Pose(name: "Tay trái lên cao, tay phải dang ngang", left: CGPoint(x: -0.6, y: 1.6), right: CGPoint(x: 2.0, y: 0)),
        Pose(name: "Tay phải lên cao, tay trái dang ngang", left: CGPoint(x: -2.0, y: 0), right: CGPoint(x: 0.6, y: 1.6)),
        Pose(name: "Một tay lên, một tay xuống", left: CGPoint(x: -1.0, y: 1.5), right: CGPoint(x: 1.0, y: -1.4)),
        Pose(name: "Một tay xuống, một tay lên", left: CGPoint(x: -1.0, y: -1.4), right: CGPoint(x: 1.0, y: 1.5)),
    ]

    private enum Phase { case waiting, ready, countdown, playing, paused, gameOver }

    // MARK: - Trạng thái

    private let hub = InputHub.shared
    private var phase: Phase = .waiting
    private var phaseStart: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var built = false
    private var touchMode = false

    private var order: [Int] = []
    private var poseIndex = 0                 // đang ở tư thế thứ mấy trong ván
    private var poseStart: TimeInterval = 0   // lúc tư thế hiện ra
    private var matchSince: TimeInterval?
    private var poseDone = false
    private var stars = 0
    private var handsUpSince: TimeInterval?
    private var lostSince: TimeInterval?
    private var resuming = false
    private var gameOverTime: TimeInterval = 0
    private var lastBeat = -1
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "danceBest") }
        set { UserDefaults.standard.set(newValue, forKey: "danceBest") }
    }

    /// Cổ tay mới nhất của người chơi, đã đổi sang toạ độ theo thân người (như `Pose`).
    private var wristL: CGPoint?
    private var wristR: CGPoint?
    private var seenTime: TimeInterval = 0
    private var shownL = CGPoint(x: -0.6, y: -1.4)
    private var shownR = CGPoint(x: 0.6, y: -1.4)

    var onExit: (() -> Void)?

    // MARK: - Node

    private let world = SKNode()
    private let targetFigure = Figure(color: UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1))
    private let playerFigure = Figure(color: UIColor(red: 0.42, green: 0.88, blue: 1, alpha: 1))
    private let targetPanel = SKShapeNode()
    private let playerPanel = SKShapeNode()
    private let nameLabel = DanceScene.makeLabel(size: 54)
    private let starsLabel = DanceScene.makeLabel(size: 50)
    private let beatDots = (0..<Tune.beatsPerPose).map { _ in SKShapeNode(circleOfRadius: 16) }
    private let holdBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.2), size: CGSize(width: 1220, height: 26))
    private let holdFill = SKSpriteNode(color: .systemGreen, size: CGSize(width: 1220, height: 26))
    private let messagePanel = SKShapeNode()
    private let titleLabel = DanceScene.makeLabel(size: 62)
    private let subLabel = DanceScene.makeLabel(size: 32)
    private let progressBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.2), size: CGSize(width: 500, height: 14))
    private let progressFill = SKSpriteNode(color: .systemYellow, size: CGSize(width: 500, height: 14))
    private let againButton = DanceScene.makeLabel(size: 36)
    private let homeButton = DanceScene.makeLabel(size: 36)

    private var cx: CGFloat { size.width / 2 }
    private var targetCenter: CGPoint { CGPoint(x: 360, y: 500) }
    private var playerCenter: CGPoint { CGPoint(x: 1040, y: 500) }
    private let panelSize = CGSize(width: 560, height: 700)

    private static func makeLabel(size: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = size
        label.fontColor = .white
        return label
    }

    /// Người que: thân, hai chân cố định, hai tay theo vị trí cổ tay, đầu tròn (hoặc ảnh mặt).
    private final class Figure {
        let node = SKNode()
        private let body = SKShapeNode()
        private let arms = SKShapeNode()
        private let head = SKShapeNode(circleOfRadius: 38)
        private let face = SKSpriteNode()
        private let hands = [SKShapeNode(circleOfRadius: 16), SKShapeNode(circleOfRadius: 16)]

        init(color: UIColor) {
            // Gốc (0,0) là giữa hai vai.
            let s = Tune.scale
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: -1.4 * s))
            path.move(to: CGPoint(x: 0, y: -1.4 * s))
            path.addLine(to: CGPoint(x: -0.45 * s, y: -3.2 * s))
            path.move(to: CGPoint(x: 0, y: -1.4 * s))
            path.addLine(to: CGPoint(x: 0.45 * s, y: -3.2 * s))
            path.move(to: CGPoint(x: -0.5 * s, y: 0))
            path.addLine(to: CGPoint(x: 0.5 * s, y: 0))
            body.path = path
            for shape in [body, arms] {
                shape.strokeColor = color
                shape.lineWidth = 15
                shape.lineCap = .round
                shape.lineJoin = .round
            }
            head.fillColor = color
            head.strokeColor = .clear
            head.position = CGPoint(x: 0, y: 0.75 * s)
            face.size = CGSize(width: 84, height: 84)
            face.position = head.position
            face.isHidden = true
            for hand in hands {
                hand.fillColor = UIColor(red: 1, green: 0.42, blue: 0.62, alpha: 1)
                hand.strokeColor = .clear
            }
            node.addChild(body)
            node.addChild(arms)
            node.addChild(head)
            node.addChild(face)
            hands.forEach(node.addChild)
        }

        func setFace(_ image: UIImage?) {
            guard let image else { return }
            face.texture = SKTexture(image: image)
            face.isHidden = false
            head.fillColor = .clear
        }

        func update(left: CGPoint, right: CGPoint) {
            let s = Tune.scale
            let path = CGMutablePath()
            let l = CGPoint(x: left.x * s, y: left.y * s)
            let r = CGPoint(x: right.x * s, y: right.y * s)
            path.move(to: CGPoint(x: -0.5 * s, y: 0))
            path.addLine(to: l)
            path.move(to: CGPoint(x: 0.5 * s, y: 0))
            path.addLine(to: r)
            arms.path = path
            hands[0].position = l
            hands[1].position = r
        }
    }

    // MARK: - Dựng cảnh

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = UIColor(red: 0.1, green: 0.05, blue: 0.2, alpha: 1)
        addChild(world)
        buildBackground(view)
        buildPanels()
        buildHUD()
        enter(.waiting)
    }

    private func buildBackground(_ view: SKView) {
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.04, green: 0.04, blue: 0.18, alpha: 1).cgColor,
                          UIColor(red: 0.35, green: 0.1, blue: 0.4, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        let bg = SKSpriteNode(texture: SKTexture(image: image), size: size)
        bg.position = CGPoint(x: cx, y: size.height / 2)
        bg.zPosition = -100
        world.addChild(bg)
        // Vài nốt nhạc bay lơ lửng cho vui mắt.
        for i in 0..<8 {
            let note = SKLabelNode(text: ["🎵", "🎶", "✨"][i % 3])
            note.fontSize = 44
            note.alpha = 0.5
            note.position = CGPoint(x: CGFloat.random(in: 40...(size.width - 40)), y: CGFloat.random(in: 60...(size.height - 60)))
            note.zPosition = -90
            note.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 30, duration: Double.random(in: 1.2...2)),
                .moveBy(x: 0, y: -30, duration: Double.random(in: 1.2...2))
            ])))
            world.addChild(note)
        }
    }

    private func buildPanels() {
        for (panel, center, dashed) in [(targetPanel, targetCenter, false), (playerPanel, playerCenter, true)] {
            panel.path = CGPath(roundedRect: CGRect(x: -panelSize.width / 2, y: -panelSize.height / 2,
                                                    width: panelSize.width, height: panelSize.height),
                                cornerWidth: 40, cornerHeight: 40, transform: nil)
            panel.fillColor = UIColor(white: 1, alpha: dashed ? 0.07 : 0.12)
            panel.strokeColor = UIColor(white: 1, alpha: 0.35)
            panel.lineWidth = 3
            panel.position = center
            panel.zPosition = 10
            addChild(panel)
        }
        for (figure, center) in [(targetFigure, targetCenter), (playerFigure, playerCenter)] {
            figure.node.position = CGPoint(x: center.x, y: center.y + 120)
            figure.node.zPosition = 20
            addChild(figure.node)
        }
        playerFigure.setFace(FaceStore.current)
        for (title, center) in [("Tư thế mẫu", targetCenter), ("Bé làm đi nào!", playerCenter)] {
            let label = Self.makeLabel(size: 30)
            label.text = title
            label.position = CGPoint(x: center.x, y: center.y + panelSize.height / 2 - 48)
            label.zPosition = 21
            addChild(label)
        }
        let arrow = SKLabelNode(text: "➡️")
        arrow.fontSize = 80
        arrow.verticalAlignmentMode = .center
        arrow.position = CGPoint(x: cx, y: 500)
        arrow.zPosition = 20
        addChild(arrow)
    }

    private func buildHUD() {
        starsLabel.horizontalAlignmentMode = .left
        starsLabel.position = CGPoint(x: 80, y: size.height - 90)
        starsLabel.zPosition = 500
        addChild(starsLabel)

        nameLabel.position = CGPoint(x: cx, y: size.height - 100)
        nameLabel.fontSize = 48
        nameLabel.zPosition = 500
        addChild(nameLabel)

        // Các chấm nhịp: sáng lên theo nhịp nhạc để bé biết còn bao lâu.
        for (i, dot) in beatDots.enumerated() {
            dot.fillColor = UIColor(white: 1, alpha: 0.25)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: cx + (CGFloat(i) - CGFloat(beatDots.count - 1) / 2) * 52, y: 120)
            dot.zPosition = 500
            addChild(dot)
        }
        holdBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        holdBack.position = CGPoint(x: cx - 610, y: 70)
        holdBack.zPosition = 500
        addChild(holdBack)
        holdFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        holdFill.position = holdBack.position
        holdFill.zPosition = 501
        addChild(holdFill)

        messagePanel.fillColor = UIColor(white: 0, alpha: 0.6)
        messagePanel.strokeColor = UIColor(white: 1, alpha: 0.25)
        messagePanel.lineWidth = 2
        messagePanel.zPosition = 600
        addChild(messagePanel)
        for label in [titleLabel, subLabel] {
            label.verticalAlignmentMode = .top
            label.numberOfLines = 0
            label.preferredMaxLayoutWidth = size.width * 0.75
            label.zPosition = 601
            addChild(label)
        }
        subLabel.fontName = "AvenirNext-DemiBold"
        subLabel.fontColor = UIColor(white: 1, alpha: 0.88)

        progressBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressBack.zPosition = 601
        addChild(progressBack)
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.zPosition = 602
        addChild(progressFill)

        againButton.text = "▶︎ Chơi lại"
        againButton.fontColor = .systemYellow
        againButton.position = CGPoint(x: cx, y: 190)
        againButton.zPosition = 601
        addChild(againButton)

        homeButton.text = "🏠 Chọn chế độ khác"
        homeButton.fontColor = .systemYellow
        homeButton.position = CGPoint(x: cx, y: 110)
        homeButton.zPosition = 601
        addChild(homeButton)
    }

    // MARK: - Vòng lặp

    private func enter(_ next: Phase) {
        phase = next
        phaseStart = CACurrentMediaTime()
        handsUpSince = nil
        againButton.isHidden = next != .gameOver
        homeButton.isHidden = next != .gameOver && next != .waiting && next != .ready
        homeButton.position.y = next == .gameOver ? 110 : 90
    }

    override func update(_ currentTime: TimeInterval) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTime, 0), 1.0 / 20))
        lastTime = now
        let elapsed = now - phaseStart
        var progress: Double?

        readHands(now)
        let visible = now - seenTime < 0.6 && wristL != nil && wristR != nil
        let secondsPerBeat = 60.0 / DanceMusic.bpm

        switch phase {
        case .waiting:
            if let problem = hub.cameraProblem {
                show("Cần quyền camera", problem + "\nChạm màn hình để chơi bằng cách chạm.")
            } else if !hub.cameraReady {
                show("Đang mở camera…")
            } else if hub.hands != nil && now - hub.handsTime < 0.6 {
                enter(.ready)
            } else {
                show("Lùi ra xa khoảng 1,5–2 mét",
                     "Đứng sao cho camera thấy từ đầu tới hông và cả hai tay.\n(Chạm màn hình để chơi thử bằng cách chạm)")
            }

        case .ready:
            if !(hub.hands != nil && now - hub.handsTime < 0.6) { enter(.waiting); break }
            progress = handsUpProgress(now)
            show("Giơ hai tay lên cao để bắt đầu 🙌",
                 "Bé làm giống người que theo nhạc nhé.\nGiống là được ⭐")
            if (progress ?? 0) >= 1 { startCountdown(resume: false) }

        case .countdown:
            let total = resuming ? 2.0 : 3.0
            let left = total - elapsed
            show("\(Int(ceil(max(left, 0.01))))", "Chuẩn bị nhảy theo nhạc!")
            if left <= 0 {
                show(nil)
                beginPlaying()
            }

        case .playing:
            if !touchMode && !visible {
                let since = lostSince ?? now
                lostSince = since
                if now - since > 1.5 { lostSince = nil; pauseForLost(); break }
            } else {
                lostSince = nil
            }
            runPlaying(now, secondsPerBeat)

        case .paused:
            show("Không thấy bạn", "Quay lại khung hình để chơi tiếp.")
            if visible { startCountdown(resume: true) }

        case .gameOver:
            if elapsed > 1.5, handsUpProgress(now) >= 1 { startCountdown(resume: false) }
        }

        updateFigures(dt)
        updateHUD()
        progressBack.isHidden = progress == nil || messagePanel.isHidden
        progressFill.isHidden = progressBack.isHidden
        progressFill.xScale = CGFloat(min(max(progress ?? 0, 0), 1))
    }

    private func startCountdown(resume: Bool) {
        resuming = resume
        if !resume { resetGame() }
        DanceMusic.shared.start()
        enter(.countdown)
    }

    private func resetGame() {
        // Xáo thứ tự nhưng luôn bắt đầu bằng tư thế dễ nhất (giơ hai tay lên).
        var rest = Array(1..<Self.poses.count)
        rest.shuffle()
        order = [0] + rest
        poseIndex = 0
        stars = 0
        poseDone = false
        matchSince = nil
    }

    private func beginPlaying() {
        enter(.playing)
        poseStart = CACurrentMediaTime()
        poseDone = false
        matchSince = nil
        lastBeat = -1
        showPoseTarget()
    }

    private func pauseForLost() {
        enter(.paused)
    }

    private func showPoseTarget() {
        guard poseIndex < order.count else { return }
        let pose = Self.poses[order[poseIndex]]
        targetFigure.update(left: pose.left, right: pose.right)
        nameLabel.text = pose.name
    }

    private func runPlaying(_ now: TimeInterval, _ secondsPerBeat: Double) {
        let total = Double(Tune.beatsPerPose) * secondsPerBeat
        let rest = Tune.restBeats * secondsPerBeat
        let t = now - poseStart
        let pose = Self.poses[order[poseIndex]]

        // Đang trong thời gian làm tư thế.
        if t < total {
            if !poseDone, matches(pose) {
                let since = matchSince ?? now
                matchSince = since
                if now - since >= Tune.holdTime { succeed() }
            } else if !poseDone {
                matchSince = nil
            }
            // Chấm nhịp sáng dần theo từng nhịp nhạc.
            let beat = Int(t / secondsPerBeat)
            if beat != lastBeat {
                lastBeat = beat
                for (i, dot) in beatDots.enumerated() {
                    dot.fillColor = i <= beat ? .systemYellow : UIColor(white: 1, alpha: 0.25)
                }
                if beat >= 0 { bounceFigures() }
            }
        } else if t < total + rest {
            nameLabel.text = poseDone ? "Giỏi quá! ⭐" : "Không sao, tư thế tiếp nào!"
        } else {
            poseIndex += 1
            if poseIndex >= Tune.poseCount {
                finish(now)
                return
            }
            poseStart = now
            poseDone = false
            matchSince = nil
            lastBeat = -1
            playerPanel.fillColor = UIColor(white: 1, alpha: 0.07)
            showPoseTarget()
        }
    }

    private func succeed() {
        poseDone = true
        stars += 1
        playerPanel.fillColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.35)
        let star = SKLabelNode(text: "⭐")
        star.fontSize = 120
        star.position = CGPoint(x: playerCenter.x, y: playerCenter.y + 60)
        star.zPosition = 400
        star.setScale(0.3)
        addChild(star)
        star.run(.sequence([
            .group([.scale(to: 1.4, duration: 0.25), .moveBy(x: 0, y: 140, duration: 0.7)]),
            .fadeOut(withDuration: 0.3),
            .removeFromParent()
        ]))
        starsLabel.run(.sequence([.scale(to: 1.3, duration: 0.1), .scale(to: 1, duration: 0.15)]))
    }

    private func finish(_ now: TimeInterval) {
        DanceMusic.shared.stop()
        let newBest = stars > best
        best = max(best, stars)
        gameOverTime = now
        enter(.gameOver)
        let row = String(repeating: "⭐", count: stars) + String(repeating: "☆", count: Tune.poseCount - stars)
        show(newBest ? "Kỷ lục mới! 🎉" : "Bé múa giỏi lắm! 👏",
             "\(row)\n\(stars)/\(Tune.poseCount) tư thế   ·   Nhiều nhất: \(best)\n\nGiơ hai tay lên cao (hoặc chạm) để múa lại")
    }

    private func bounceFigures() {
        for figure in [targetFigure, playerFigure] {
            figure.node.removeAction(forKey: "bounce")
            let base = figure.node === targetFigure.node ? targetCenter.y + 120 : playerCenter.y + 120
            figure.node.position.y = base
            figure.node.run(.sequence([.moveTo(y: base + 14, duration: 0.12), .moveTo(y: base, duration: 0.18)]), withKey: "bounce")
        }
    }

    // MARK: - Chấm tư thế

    private func matches(_ pose: Pose) -> Bool {
        guard let l = wristL, let r = wristR else { return false }
        let dl = hypot(l.x - pose.left.x, l.y - pose.left.y)
        let dr = hypot(r.x - pose.right.x, r.y - pose.right.y)
        return (dl + dr) / 2 < Tune.avgTolerance && max(dl, dr) < Tune.maxTolerance
    }

    /// 0...1: hai tay giơ cao hơn đầu đủ lâu.
    private func handsUpProgress(_ now: TimeInterval) -> Double {
        guard now - seenTime < 0.4, let l = wristL, let r = wristR, l.y > 1.0, r.y > 1.0 else {
            handsUpSince = nil
            return 0
        }
        let since = handsUpSince ?? now
        handsUpSince = since
        return (now - since) / Tune.handsUpHold
    }

    private var lastHandsFrame = -1

    private func readHands(_ now: TimeInterval) {
        guard hub.handsFrame != lastHandsFrame, let hands = hub.hands else { return }
        lastHandsFrame = hub.handsFrame
        func local(_ p: CGPoint) -> CGPoint {
            let d = CGVector(dx: p.x - hands.chest.x, dy: p.y - hands.chest.y)
            let right = CGVector(dx: hands.up.dy, dy: -hands.up.dx)
            return CGPoint(x: (d.dx * right.dx + d.dy * right.dy) / hands.shoulderWidth,
                           y: (d.dx * hands.up.dx + d.dy * hands.up.dy) / hands.shoulderWidth)
        }
        guard let a = hands.left, let b = hands.right else { return }
        // Tay nào ở bên trái hình thì là "tay trái" (không phụ thuộc camera bị lật gương hay không).
        let pa = local(a), pb = local(b)
        wristL = pa.x <= pb.x ? pa : pb
        wristR = pa.x <= pb.x ? pb : pa
        seenTime = now
    }

    private func updateFigures(_ dt: CGFloat) {
        // Người chơi: vẽ tay theo cổ tay thật (làm mượt nhẹ). Mất dấu thì hạ tay xuống.
        let k = min(1, dt * 18)
        let targetL = wristL.flatMap { _ in CACurrentMediaTime() - seenTime < 0.6 ? wristL : nil } ?? CGPoint(x: -0.6, y: -1.4)
        let targetR = wristR.flatMap { _ in CACurrentMediaTime() - seenTime < 0.6 ? wristR : nil } ?? CGPoint(x: 0.6, y: -1.4)
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: max(-2.4, min(2.4, p.x)), y: max(-2.0, min(2.2, p.y)))
        }
        let l = clamp(targetL), r = clamp(targetR)
        shownL = CGPoint(x: shownL.x + (l.x - shownL.x) * k, y: shownL.y + (l.y - shownL.y) * k)
        shownR = CGPoint(x: shownR.x + (r.x - shownR.x) * k, y: shownR.y + (r.y - shownR.y) * k)
        playerFigure.update(left: shownL, right: shownR)
        if phase == .waiting || phase == .ready || phase == .countdown || phase == .gameOver {
            // Lúc chưa chơi, hiện sẵn một tư thế mẫu để bé biết trước.
            if phase != .playing { targetFigure.update(left: Self.poses[0].left, right: Self.poses[0].right) }
        }
    }

    private func updateHUD() {
        let playing = phase == .playing || phase == .paused || phase == .countdown
        setText(starsLabel, playing || phase == .gameOver ? "⭐ \(stars)/\(Tune.poseCount)" : "")
        if !(phase == .playing) { setText(nameLabel, "") }
        for dot in beatDots { dot.isHidden = phase != .playing }
        holdBack.isHidden = phase != .playing
        holdFill.isHidden = holdBack.isHidden
        if phase == .playing, let since = matchSince, !poseDone {
            holdFill.xScale = CGFloat(min(1, (CACurrentMediaTime() - since) / Tune.holdTime))
        } else {
            holdFill.xScale = poseDone ? 1 : 0.001
        }
    }

    private func setText(_ label: SKLabelNode, _ text: String) {
        if label.text != text { label.text = text }
    }

    // MARK: - Cảm ứng (dự phòng khi thử máy)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        let now = CACurrentMediaTime()
        switch phase {
        case .waiting, .ready:
            if !homeButton.isHidden, homeButton.frame.insetBy(dx: -40, dy: -20).contains(p) {
                exitToMenu()
                return
            }
            // Chạm màn hình: chơi thử không cần camera, mỗi lần chạm vào khung bên phải tính là làm đúng.
            touchMode = true
            startCountdown(resume: false)
        case .gameOver:
            guard now - gameOverTime > 1 else { return }
            if homeButton.frame.insetBy(dx: -40, dy: -20).contains(p) {
                exitToMenu()
            } else {
                startCountdown(resume: false)
            }
        case .playing:
            if touchMode, !poseDone, now - poseStart < Double(Tune.beatsPerPose) * 60.0 / DanceMusic.bpm { succeed() }
        case .countdown, .paused:
            break
        }
    }

    func exitToMenu() {
        touchMode = false
        DanceMusic.shared.stop()
        show(nil)
        enter(.waiting)
        onExit?()
    }

    // MARK: - Thông báo giữa màn hình

    private func show(_ title: String?, _ sub: String? = nil) {
        let t = title ?? "", s = sub ?? ""
        guard t != titleLabel.text || s != subLabel.text else { return }
        titleLabel.text = t
        subLabel.text = s
        let visible = !t.isEmpty || !s.isEmpty
        messagePanel.isHidden = !visible
        titleLabel.isHidden = !visible
        subLabel.isHidden = !visible
        guard visible else { return }
        titleLabel.position = CGPoint(x: cx, y: size.height * 0.78)
        subLabel.position = CGPoint(x: cx, y: titleLabel.frame.minY - 20)
        var frame = titleLabel.frame
        if !s.isEmpty { frame = frame.union(subLabel.frame) }
        frame = frame.insetBy(dx: -50, dy: -34)
        frame.size.height += 30
        frame.origin.y -= 30
        messagePanel.path = CGPath(roundedRect: frame, cornerWidth: 28, cornerHeight: 28, transform: nil)
        progressBack.position = CGPoint(x: cx - 250, y: frame.minY + 34)
        progressFill.position = progressBack.position
    }
}
