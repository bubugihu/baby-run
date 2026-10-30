import SpriteKit
import UIKit
import QuartzCore

/// Mèo chạy phố Nhật về đêm: 3 làn, né thùng gỗ.
/// Bước ngang = đổi làn, hét = nhảy (to/dài = cao hơn).
final class GameScene: SKScene {

    // MARK: - Tinh chỉnh (game chậm, dễ tha lỗi)

    private enum Tune {
        static let startSpeed: CGFloat = 6        // đơn vị đường/giây
        static let maxSpeed: CGFloat = 11
        static let speedRamp: CGFloat = 0.05      // tăng tốc mỗi giây
        static let spawnZ: CGFloat = 26           // thùng xuất hiện ở xa
        static let firstGap: TimeInterval = 3.4   // giây giữa hai đợt thùng lúc đầu
        static let minGap: TimeInterval = 1.9
        static let crateHeight: CGFloat = 0.6
        static let hitDepth: CGFloat = 0.4
        static let gravity: CGFloat = 12
        static let heldGravity: CGFloat = 6       // còn hét khi đang bay lên → bay cao hơn
        static let jumpMin: CGFloat = 6
        static let jumpMax: CGFloat = 8.5
        static let invincible: TimeInterval = 2
        static let bodyLostPause: TimeInterval = 1.2
        static let lives = 3
    }

    private enum Phase {
        case waiting, calibStill, calibLeft, calibRight, calibShout, countdown, playing, paused, gameOver
    }

    private final class Obstacle {
        let node: SKNode
        let lane: Int
        var z: CGFloat
        var passed = false
        var dead = false
        init(node: SKNode, lane: Int, z: CGFloat) { self.node = node; self.lane = lane; self.z = z }
    }

    private final class Decor {
        let node: SKNode
        var z: CGFloat
        let side: CGFloat
        init(node: SKNode, z: CGFloat, side: CGFloat) { self.node = node; self.z = z; self.side = side }
    }

    // MARK: - Bố cục giả 3D (scene 1400x1000)

    private var cx: CGFloat { size.width / 2 }
    private var horizonY: CGFloat { size.height * 0.60 }
    private var groundY0: CGFloat { size.height * 0.13 }
    private var roadHalf0: CGFloat { size.width * 0.42 }
    private var laneW0: CGFloat { roadHalf0 * 2 / 3 }
    private var unitPx0: CGFloat { size.width * 0.22 }

    private func depthScale(_ z: CGFloat) -> CGFloat { 1 / (1 + max(z, -2) * 0.25) }
    private func groundY(_ s: CGFloat) -> CGFloat { horizonY - (horizonY - groundY0) * s }

    // MARK: - Trạng thái

    private let hub = InputHub.shared
    private var calib = Calibration()
    private var phase: Phase = .waiting
    private var phaseStart: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var touchMode = false
    private var built = false

    private var level: Float = -80
    private var wasLoud = false
    private var lastShoutTime: TimeInterval = 0
    private var shoutEvent = false

    private var pointSamples: [CGPoint] = []
    private var levelSamples: [Float] = []
    private var calibPeak: Float = -80
    private var calibPeakTime: TimeInterval = 0
    private var calibCenter = CGPoint(x: 0.5, y: 0.5)
    private var calibLeftPoint = CGPoint.zero
    private var calibNote: String?

    private var targetLane = 1
    private var laneX: CGFloat = 0
    private var laneVel: CGFloat = 0
    private var jumpY: CGFloat = 0
    private var jumpV: CGFloat = 0
    private var airborne = false
    private var jumpStart: TimeInterval = 0
    private var speed: CGFloat = Tune.startSpeed
    private var distance: CGFloat = 0
    private var dodged = 0
    private var lives = Tune.lives
    private var invincibleUntil: TimeInterval = 0
    private var nextSpawn: TimeInterval = 0
    private var obstacles: [Obstacle] = []
    private var shoutCount = 0
    private var loudestDB: Float = -80
    private var bodyLostSince: TimeInterval?
    private var resuming = false
    private var gameOverTime: TimeInterval = 0
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "best") }
        set { UserDefaults.standard.set(newValue, forKey: "best") }
    }
    private var score: Int { Int(distance) + dodged * 10 }

    // MARK: - Node

    private let world = SKNode()
    private let player = SKNode()
    private let cat = SKLabelNode(text: "🐱")
    private let playerShadow = SKShapeNode(ellipseOf: CGSize(width: 180, height: 40))
    private var lanterns: [Decor] = []
    private var lanternTemplate = SKNode()
    private var crateTemplate = SKNode()
    private var dashes: [Decor] = []

    private let scoreLabel = GameScene.makeLabel(size: 50)
    private let livesLabel = GameScene.makeLabel(size: 46)
    private var laneSlots: [SKShapeNode] = []
    private let laneDot = SKShapeNode(circleOfRadius: 9)
    private let volumeFill = SKSpriteNode(color: .systemGreen, size: CGSize(width: 40, height: 300))
    private let volumeThreshold = SKSpriteNode(color: .systemOrange, size: CGSize(width: 60, height: 5))
    private let messagePanel = SKShapeNode()
    private let titleLabel = GameScene.makeLabel(size: 62)
    private let subLabel = GameScene.makeLabel(size: 32)
    private let progressBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.2), size: CGSize(width: 500, height: 14))
    private let progressFill = SKSpriteNode(color: .systemYellow, size: CGSize(width: 500, height: 14))
    private let recalibButton = GameScene.makeLabel(size: 34)
    private let flash = SKSpriteNode(color: .systemRed, size: .zero)

    private static func makeLabel(size: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = size
        label.fontColor = .white
        return label
    }

    // MARK: - Dựng cảnh

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1)
        addChild(world)
        buildBackground(view)
        buildRoad(view)
        buildDecor(view)
        buildPlayer()
        buildHUD()
        layoutDecor()
        enter(.waiting)
    }

    private func gradientTexture(size: CGSize, top: UIColor, bottom: UIColor) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        return SKTexture(image: image)
    }

    private func buildBackground(_ view: SKView) {
        // Trời, sao, trăng, dãy nhà: dựng bằng nhiều node rồi gộp thành một ảnh duy nhất.
        let backdrop = SKNode()
        let skySize = CGSize(width: size.width, height: size.height - horizonY)
        let sky = SKSpriteNode(texture: gradientTexture(size: skySize,
                                                        top: UIColor(red: 0.04, green: 0.06, blue: 0.19, alpha: 1),
                                                        bottom: UIColor(red: 0.23, green: 0.12, blue: 0.36, alpha: 1)))
        sky.size = skySize
        sky.position = CGPoint(x: cx, y: horizonY + skySize.height / 2)
        sky.zPosition = -100
        backdrop.addChild(sky)

        for _ in 0..<40 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 1...2.2))
            star.fillColor = .white
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.3...0.8)
            star.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: (horizonY + 120)...size.height))
            star.zPosition = -99
            backdrop.addChild(star)
        }

        let moonGlow = SKShapeNode(circleOfRadius: 90)
        moonGlow.fillColor = UIColor(red: 1, green: 0.96, blue: 0.78, alpha: 0.12)
        moonGlow.strokeColor = .clear
        let moon = SKShapeNode(circleOfRadius: 50)
        moon.fillColor = UIColor(red: 1, green: 0.96, blue: 0.78, alpha: 1)
        moon.strokeColor = .clear
        moonGlow.position = CGPoint(x: size.width * 0.8, y: size.height * 0.86)
        moonGlow.zPosition = -98
        moon.zPosition = 1
        moonGlow.addChild(moon)
        backdrop.addChild(moonGlow)

        // Dãy nhà phía chân trời, cửa sổ sáng đèn ngẫu nhiên.
        let buildingColor = UIColor(red: 0.06, green: 0.08, blue: 0.18, alpha: 1)
        let windowColor = UIColor(red: 1, green: 0.83, blue: 0.42, alpha: 1)
        var x: CGFloat = -20
        var signIndex = 0
        let signs: [(String, UIColor)] = [("ラーメン", .systemPink), ("ねこ", .cyan), ("よる", .systemYellow)]
        while x < size.width + 20 {
            let w = CGFloat.random(in: 70...160)
            let h = CGFloat.random(in: 70...260)
            let building = SKSpriteNode(color: buildingColor, size: CGSize(width: w, height: h))
            building.anchorPoint = CGPoint(x: 0, y: 0)
            building.position = CGPoint(x: x, y: horizonY)
            building.zPosition = -90
            backdrop.addChild(building)
            var wy: CGFloat = 14
            while wy < h - 20 {
                var wx: CGFloat = 10
                while wx < w - 20 {
                    if Int.random(in: 0..<3) == 0 {
                        let window = SKSpriteNode(color: windowColor, size: CGSize(width: 10, height: 13))
                        window.anchorPoint = .zero
                        window.alpha = .random(in: 0.4...0.9)
                        window.position = CGPoint(x: wx, y: wy)
                        window.zPosition = 1
                        building.addChild(window)
                    }
                    wx += 22
                }
                wy += 26
            }
            if h > 180, signIndex < signs.count, Bool.random() {
                let (text, color) = signs[signIndex]
                signIndex += 1
                let sign = SKLabelNode(fontNamed: "HiraginoSans-W6")
                sign.text = text.map(String.init).joined(separator: "\n")
                sign.numberOfLines = 0
                sign.fontSize = 28
                sign.fontColor = color
                sign.verticalAlignmentMode = .top
                sign.position = CGPoint(x: w - 22, y: h - 16)
                sign.zPosition = 1
                building.addChild(sign)
            }
            x += w + 4
        }
        let baked = bake(backdrop, in: view)
        baked.zPosition = -100
        world.addChild(baked)
    }

    /// Vẽ một cụm node thành một sprite duy nhất (ở độ phân giải `detail` lần) để SpriteKit
    /// gom được lệnh vẽ. SKShapeNode và hàng trăm node nhỏ là nguyên nhân giật hình phổ biến nhất.
    private func bake(_ node: SKNode, in view: SKView, detail: CGFloat = 2) -> SKNode {
        let holder = SKNode()
        holder.setScale(detail)
        holder.addChild(node)
        let frame = holder.calculateAccumulatedFrame()
        guard frame.width > 0, frame.height > 0, let texture = view.texture(from: holder) else {
            node.removeFromParent()
            return node
        }
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: frame.width / detail, height: frame.height / detail))
        sprite.anchorPoint = CGPoint(x: -frame.minX / frame.width, y: -frame.minY / frame.height)
        return sprite
    }

    private func buildRoad(_ view: SKView) {
        // Mép đường là đường thẳng hội tụ về điểm biến mất (cx, horizonY).
        let s0 = horizonY / (horizonY - groundY0)
        func trapezoid(halfWidth: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx - halfWidth * s0, y: 0))
            path.addLine(to: CGPoint(x: cx + halfWidth * s0, y: 0))
            path.addLine(to: CGPoint(x: cx, y: horizonY))
            path.closeSubpath()
            return path
        }
        let sidewalk = SKShapeNode(path: trapezoid(halfWidth: roadHalf0 * 1.4))
        sidewalk.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.23, alpha: 1)
        sidewalk.strokeColor = .clear
        let ground = SKNode()
        ground.addChild(sidewalk)

        let road = SKShapeNode(path: trapezoid(halfWidth: roadHalf0))
        road.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.26, alpha: 1)
        road.strokeColor = UIColor(white: 1, alpha: 0.25)
        road.lineWidth = 3
        road.zPosition = 1
        ground.addChild(road)
        let baked = bake(ground, in: view, detail: 1)
        baked.zPosition = -50
        world.addChild(baked)
    }

    private func buildDecor(_ view: SKView) {
        lanternTemplate = bake(makeLantern(), in: view)
        crateTemplate = bake(makeCrate(), in: view)
        // Vạch chia làn.
        for side in [CGFloat(-0.5), 0.5] {
            var z: CGFloat = -1
            while z < 30 {
                let dash = SKSpriteNode(color: UIColor(white: 0.92, alpha: 0.7), size: CGSize(width: 10, height: 10))
                dash.zPosition = -40
                world.addChild(dash)
                dashes.append(Decor(node: dash, z: z, side: side))
                z += 2.5
            }
        }
        // Đèn lồng đỏ hai bên đường.
        for side in [CGFloat(-1), 1] {
            var z: CGFloat = 0.5
            while z < 32 {
                let lantern = lanternTemplate.copy() as! SKNode
                world.addChild(lantern)
                lanterns.append(Decor(node: lantern, z: z, side: side))
                z += 4
            }
        }
    }

    private func makeLantern() -> SKNode {
        let node = SKNode()
        let pole = SKSpriteNode(color: UIColor(red: 0.23, green: 0.16, blue: 0.12, alpha: 1), size: CGSize(width: 8, height: 260))
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.zPosition = 1
        node.addChild(pole)
        let glow = SKShapeNode(circleOfRadius: 80)
        glow.fillColor = UIColor(red: 1, green: 0.7, blue: 0.28, alpha: 0.18)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: 270)
        node.addChild(glow)
        let body = SKShapeNode(ellipseOf: CGSize(width: 52, height: 68))
        body.fillColor = UIColor(red: 0.88, green: 0.19, blue: 0.17, alpha: 1)
        body.strokeColor = UIColor(red: 0.5, green: 0.08, blue: 0.06, alpha: 1)
        body.lineWidth = 3
        body.position = CGPoint(x: 0, y: 270)
        body.zPosition = 2
        node.addChild(body)
        for y in [CGFloat(236), 304] {
            let cap = SKSpriteNode(color: UIColor(white: 0.12, alpha: 1), size: CGSize(width: 28, height: 6))
            cap.position = CGPoint(x: 0, y: y)
            cap.zPosition = 3
            node.addChild(cap)
        }
        return node
    }

    private func makeCrate() -> SKNode {
        let w = laneW0 * 0.72
        let h = Tune.crateHeight * unitPx0
        let dark = UIColor(red: 0.3, green: 0.18, blue: 0.08, alpha: 1)
        let node = SKNode()

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.1, height: w * 0.2))
        shadow.fillColor = UIColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        node.addChild(shadow)

        let top = CGMutablePath()
        top.move(to: CGPoint(x: -w / 2, y: h))
        top.addLine(to: CGPoint(x: w / 2, y: h))
        top.addLine(to: CGPoint(x: w / 2 - w * 0.08, y: h + h * 0.15))
        top.addLine(to: CGPoint(x: -w / 2 + w * 0.08, y: h + h * 0.15))
        top.closeSubpath()
        let lid = SKShapeNode(path: top)
        lid.fillColor = UIColor(red: 0.69, green: 0.48, blue: 0.27, alpha: 1)
        lid.strokeColor = dark
        lid.lineWidth = 4
        lid.zPosition = 1
        node.addChild(lid)

        let box = SKShapeNode(rect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerRadius: 6)
        box.fillColor = UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1)
        box.strokeColor = dark
        box.lineWidth = 6
        box.zPosition = 2
        node.addChild(box)

        let planks = CGMutablePath()
        planks.move(to: CGPoint(x: -w / 2, y: h / 3)); planks.addLine(to: CGPoint(x: w / 2, y: h / 3))
        planks.move(to: CGPoint(x: -w / 2, y: h * 2 / 3)); planks.addLine(to: CGPoint(x: w / 2, y: h * 2 / 3))
        planks.move(to: CGPoint(x: -w / 2, y: 0)); planks.addLine(to: CGPoint(x: w / 2, y: h))
        let lines = SKShapeNode(path: planks)
        lines.strokeColor = dark
        lines.lineWidth = 6
        lines.zPosition = 3
        node.addChild(lines)
        return node
    }

    private func buildPlayer() {
        playerShadow.fillColor = UIColor(white: 0, alpha: 0.4)
        playerShadow.strokeColor = .clear
        playerShadow.zPosition = 99
        world.addChild(playerShadow)

        cat.fontSize = 170
        cat.verticalAlignmentMode = .bottom
        cat.position = CGPoint(x: 0, y: -18)
        player.addChild(cat)
        player.zPosition = 100
        world.addChild(player)
    }

    private func buildHUD() {
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 80, y: size.height - 90)
        scoreLabel.zPosition = 500
        addChild(scoreLabel)

        livesLabel.horizontalAlignmentMode = .right
        livesLabel.position = CGPoint(x: size.width - 80, y: size.height - 90)
        livesLabel.zPosition = 500
        addChild(livesLabel)

        // Ô báo làn mà camera thấy bạn đang đứng.
        for i in 0..<3 {
            let slot = SKShapeNode(rectOf: CGSize(width: 54, height: 34), cornerRadius: 8)
            slot.position = CGPoint(x: cx + CGFloat(i - 1) * 64, y: size.height - 70)
            slot.strokeColor = .clear
            slot.zPosition = 500
            addChild(slot)
            laneSlots.append(slot)
        }
        laneDot.fillColor = .white
        laneDot.strokeColor = .clear
        laneDot.zPosition = 501
        addChild(laneDot)

        // Cột âm lượng + vạch ngưỡng hét.
        let volumeBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.18), size: CGSize(width: 40, height: 300))
        volumeBack.anchorPoint = CGPoint(x: 0.5, y: 0)
        volumeBack.position = CGPoint(x: 100, y: 120)
        volumeBack.zPosition = 500
        addChild(volumeBack)
        volumeFill.anchorPoint = CGPoint(x: 0.5, y: 0)
        volumeFill.position = volumeBack.position
        volumeFill.zPosition = 501
        addChild(volumeFill)
        volumeThreshold.zPosition = 502
        addChild(volumeThreshold)
        let mic = SKLabelNode(text: "🎤")
        mic.fontSize = 36
        mic.position = CGPoint(x: 100, y: 70)
        mic.zPosition = 500
        addChild(mic)

        // Bảng thông báo giữa màn hình.
        messagePanel.fillColor = UIColor(white: 0, alpha: 0.55)
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

        recalibButton.text = "↻ Hiệu chỉnh lại"
        recalibButton.fontColor = .systemYellow
        recalibButton.position = CGPoint(x: cx, y: 150)
        recalibButton.zPosition = 601
        recalibButton.isHidden = true
        addChild(recalibButton)

        flash.size = size
        flash.position = CGPoint(x: cx, y: size.height / 2)
        flash.alpha = 0
        flash.zPosition = 450
        addChild(flash)
    }

    // MARK: - Vòng lặp

    private func enter(_ next: Phase) {
        phase = next
        phaseStart = CACurrentMediaTime()
        pointSamples.removeAll()
        levelSamples.removeAll()
        calibPeak = -80
        recalibButton.isHidden = next != .gameOver
    }

    override func update(_ currentTime: TimeInterval) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastTime, 0), 1.0 / 20))
        lastTime = now
        readVoice(now)
        let elapsed = now - phaseStart
        var progress: Double?

        switch phase {
        case .waiting:
            // Thiếu micro vẫn chơi được bằng camera (chạm giữa màn hình để nhảy).
            if let problem = hub.cameraProblem {
                show("Cần quyền camera", problem + "\nChạm màn hình để chơi thử bằng cảm ứng.")
            } else if hub.cameraReady && (hub.micReady || hub.micProblem != nil) {
                enter(.calibStill)
            } else {
                show("Đang mở camera và micro…")
            }

        case .calibStill:
            progress = runCalibStill(now, elapsed)

        case .calibLeft:
            progress = runSideStep(now, elapsed, title: "Bước 2/4 · Bước sang TRÁI một bước dài") { point in
                calibLeftPoint = point
                enter(.calibRight)
            }

        case .calibRight:
            progress = runSideStep(now, elapsed, title: "Bước 3/4 · Bước sang PHẢI một bước dài") { point in
                if calib.setPositions(center: calibCenter, left: calibLeftPoint, right: point) {
                    enter(.calibShout)
                } else {
                    calibNote = "Chưa rõ trái/phải, mình làm lại nhé: bước sang TRÁI."
                    enter(.calibLeft)
                }
            }

        case .calibShout:
            progress = runCalibShout(now, elapsed)

        case .countdown:
            let total = resuming ? 2.0 : 3.0
            let left = total - elapsed
            show("\(Int(ceil(max(left, 0.01))))",
                 resuming ? "Chơi tiếp!" : "Bước ngang để đổi làn · Hét để nhảy")
            updatePlayer(dt, now, allowJump: false)
            if left <= 0 {
                show(nil)
                enter(.playing)
            }

        case .playing:
            runPlaying(dt, now)

        case .paused:
            show("Không thấy bạn", "Quay lại khung hình để chơi tiếp.")
            if hub.bodyVisible(at: now) { startCountdown(resume: true) }

        case .gameOver:
            if shoutEvent && elapsed > 2 { startCountdown(resume: false) }
        }

        updateHUD(now, progress: progress)
    }

    private func readVoice(_ now: TimeInterval) {
        level = hub.levelDB
        let threshold = calib.jumpThresholdDB
        let loud = level > threshold
        shoutEvent = false
        if loud && !wasLoud && now - lastShoutTime > 0.35 {
            shoutEvent = true
            lastShoutTime = now
        }
        // Trễ 4 dB để một tiếng hét không bị đếm thành nhiều lần.
        if loud { wasLoud = true } else if level < threshold - 4 { wasLoud = false }
    }

    // MARK: - Hiệu chỉnh

    private let skipHint = "\n(Chạm màn hình để bỏ qua và chơi bằng cảm ứng)"

    private func notVisibleYet() -> Double {
        show("Chưa thấy bạn", "Đứng cách iPad khoảng 2 mét để camera thấy cả người." + skipHint)
        phaseStart = CACurrentMediaTime()
        pointSamples.removeAll()
        levelSamples.removeAll()
        return 0
    }

    private func runCalibStill(_ now: TimeInterval, _ elapsed: TimeInterval) -> Double {
        guard hub.bodyVisible(at: now), let point = hub.bodyPoint else { return notVisibleYet() }
        pointSamples.append(point)
        levelSamples.append(level)
        show("Bước 1/4 · Đứng yên ở GIỮA", "Giữ im lặng 3 giây để đo tiếng ồn trong phòng." + skipHint)
        if elapsed >= 3 {
            calibCenter = mean(pointSamples)
            calib.noiseDB = percentile(levelSamples, 0.9)
            calibNote = nil
            enter(.calibLeft)
        }
        return elapsed / 3
    }

    private func runSideStep(_ now: TimeInterval, _ elapsed: TimeInterval, title: String, done: (CGPoint) -> Void) -> Double {
        guard hub.bodyVisible(at: now), let point = hub.bodyPoint else { return notVisibleYet() }
        show(title, calibNote ?? "Bước xong thì đứng yên ở đó một chút.")
        if elapsed >= 1.8 { pointSamples.append(point) }
        if elapsed >= 3 {
            let p = mean(pointSamples)
            if hypot(p.x - calibCenter.x, p.y - calibCenter.y) < 0.04 {
                calibNote = "Chưa thấy bạn di chuyển, bước dài hơn chút nhé!"
                enter(phase)
            } else {
                calibNote = nil
                done(p)
            }
        }
        return elapsed / 3
    }

    private func runCalibShout(_ now: TimeInterval, _ elapsed: TimeInterval) -> Double {
        if !hub.micReady {
            startCountdown(resume: false)
            return 1
        }
        if level > calibPeak {
            calibPeak = level
            calibPeakTime = now
        }
        let needed = calib.noiseDB + 12
        show("Bước 4/4 · Về GIỮA rồi HÉT thật to!", calibNote ?? "Ví dụ: \"NHẢY!\"")
        if calibPeak >= needed && now - calibPeakTime > 0.4 {
            calib.shoutDB = calibPeak
            calibNote = nil
            startCountdown(resume: false)
        } else if elapsed > 6 {
            calibNote = "Chưa nghe rõ, hét to hơn nữa nào!"
            enter(.calibShout)
        }
        return Double(min(1, max(0, (calibPeak - calib.noiseDB) / 12)))
    }

    // MARK: - Chơi

    private func startCountdown(resume: Bool) {
        resuming = resume
        if !resume { resetGame() }
        enter(.countdown)
    }

    private func resetGame() {
        for obstacle in obstacles { obstacle.node.removeFromParent() }
        obstacles.removeAll()
        speed = Tune.startSpeed
        distance = 0
        dodged = 0
        lives = Tune.lives
        invincibleUntil = 0
        shoutCount = 0
        loudestDB = -80
        jumpY = 0
        jumpV = 0
        airborne = false
        bodyLostSince = nil
        nextSpawn = CACurrentMediaTime() + 3 + 1.5
        cat.text = "🐱"
    }

    private func runPlaying(_ dt: CGFloat, _ now: TimeInterval) {
        if !touchMode && hub.cameraReady {
            if hub.bodyVisible(at: now) {
                bodyLostSince = nil
            } else if let since = bodyLostSince {
                if now - since > Tune.bodyLostPause {
                    enter(.paused)
                    return
                }
            } else {
                bodyLostSince = now
            }
        }

        if shoutEvent { shoutCount += 1 }
        loudestDB = max(loudestDB, level)

        speed = min(Tune.maxSpeed, speed + Tune.speedRamp * dt)
        distance += speed * dt
        updatePlayer(dt, now, allowJump: true)
        updateObstacles(dt, now)
        moveDecor(dt)
    }

    private func loudFraction() -> CGFloat {
        let threshold = calib.jumpThresholdDB
        let range = max(calib.shoutDB - threshold, 6)
        return CGFloat(min(max((level - threshold) / range, 0), 1))
    }

    private func jumpVelocity(_ fraction: CGFloat) -> CGFloat {
        Tune.jumpMin + (Tune.jumpMax - Tune.jumpMin) * fraction
    }

    private func startJump(_ fraction: CGFloat, _ now: TimeInterval) {
        airborne = true
        jumpStart = now
        jumpV = jumpVelocity(fraction)
    }

    private func updatePlayer(_ dt: CGFloat, _ now: TimeInterval, allowJump: Bool) {
        if !touchMode, hub.bodyVisible(at: now), let point = hub.bodyPoint {
            targetLane = calib.lane(for: point, current: targetLane)
        }

        // Lò xo tắt dần: mèo lướt sang làn mới trong ~0,25 giây.
        let goal = CGFloat(targetLane - 1)
        laneVel += ((goal - laneX) * 80 - laneVel * 18) * dt
        laneX += laneVel * dt

        if allowJump && shoutEvent && !airborne { startJump(loudFraction(), now) }

        if airborne {
            let loud = level > calib.jumpThresholdDB
            // Tiếng hét thường to dần trong 0,2 giây đầu: cho cú nhảy mạnh thêm theo.
            if hub.micReady && now - jumpStart < 0.2 {
                let catchUp = jumpVelocity(loudFraction()) - Tune.gravity * CGFloat(now - jumpStart)
                jumpV = max(jumpV, catchUp)
            }
            let g = (loud && jumpV > 0) ? Tune.heldGravity : Tune.gravity
            jumpV -= g * dt
            jumpY += jumpV * dt
            if jumpY <= 0 {
                jumpY = 0
                jumpV = 0
                airborne = false
                cat.run(.sequence([.scaleX(to: 1.15, y: 0.85, duration: 0.06), .scale(to: 1, duration: 0.12)]))
            }
        }

        let x = cx + laneX * laneW0
        let bob = (phase == .playing && !airborne) ? abs(sin(CGFloat(now) * 11)) * 10 : 0
        player.position = CGPoint(x: x, y: groundY0 + jumpY * unitPx0 + bob)
        player.zRotation = max(-0.3, min(0.3, -laneVel * 0.08))
        playerShadow.position = CGPoint(x: x, y: groundY0)
        playerShadow.setScale(1 / (1 + jumpY * 0.6))

        if now < invincibleUntil {
            player.alpha = Int(now * 10) % 2 == 0 ? 0.35 : 1
        } else {
            player.alpha = 1
            if cat.text != "🐱" { cat.text = "🐱" }
        }
    }

    private func updateObstacles(_ dt: CGFloat, _ now: TimeInterval) {
        if now >= nextSpawn {
            spawnWave()
            let gap = max(Tune.minGap, Tune.firstGap - Double(distance) / 400)
            nextSpawn = now + gap
        }

        for obstacle in obstacles {
            obstacle.z -= speed * dt
            let s = depthScale(obstacle.z)
            obstacle.node.position = CGPoint(x: cx + CGFloat(obstacle.lane - 1) * laneW0 * s, y: groundY(s))
            obstacle.node.setScale(s)
            obstacle.node.zPosition = 100 - obstacle.z
            obstacle.node.alpha = min(1, (Tune.spawnZ - obstacle.z) / 4)

            let sameLane = abs(laneX - CGFloat(obstacle.lane - 1)) < 0.5
            if abs(obstacle.z) < Tune.hitDepth && sameLane && jumpY < Tune.crateHeight && now >= invincibleUntil {
                crash(obstacle, now)
            } else if !obstacle.passed && obstacle.z < -Tune.hitDepth {
                obstacle.passed = true
                dodged += 1
            }
            if obstacle.z < -2.5 {
                obstacle.dead = true
                obstacle.node.removeFromParent()
            }
        }
        obstacles.removeAll { $0.dead }
    }

    private func spawnWave() {
        var lanes = [Int.random(in: 0...2)]
        // Sau một lúc, đôi khi có 2 thùng: luôn chừa một làn trống.
        if distance > 250 && Int.random(in: 0..<100) < 35 {
            lanes.append(([0, 1, 2].filter { $0 != lanes[0] }).randomElement()!)
        }
        for lane in lanes {
            let node = crateTemplate.copy() as! SKNode
            node.alpha = 0
            world.addChild(node)
            obstacles.append(Obstacle(node: node, lane: lane, z: Tune.spawnZ))
        }
    }

    private func crash(_ obstacle: Obstacle, _ now: TimeInterval) {
        lives -= 1
        invincibleUntil = now + Tune.invincible
        obstacle.dead = true
        obstacle.passed = true
        obstacle.node.run(.sequence([
            .group([.moveBy(x: CGFloat.random(in: -200...200), y: 160, duration: 0.35),
                    .rotate(byAngle: .pi, duration: 0.35),
                    .fadeOut(withDuration: 0.35)]),
            .removeFromParent()
        ]))
        cat.text = "🙀"
        flash.removeAllActions()
        flash.run(.sequence([.fadeAlpha(to: 0.35, duration: 0.05), .fadeOut(withDuration: 0.4)]))
        world.run(.sequence([.moveBy(x: 18, y: 0, duration: 0.04), .moveBy(x: -36, y: 0, duration: 0.08),
                             .moveBy(x: 18, y: 0, duration: 0.04)]))

        if lives <= 0 {
            best = max(best, score)
            gameOverTime = now
            enter(.gameOver)
            let louder = max(0, Int(loudestDB - calib.noiseDB))
            show("Hết ván! 🐾",
                 "Điểm: \(score)   ·   Kỷ lục: \(best)\nSố lần hét: \(shoutCount)   ·   To nhất: +\(louder) dB\n\nHét thật to (hoặc chạm màn hình) để chơi lại")
        }
    }

    private func moveDecor(_ dt: CGFloat) {
        // Vạch và đèn chạy về phía người chơi, qua khỏi thì quay lại phía xa.
        for lantern in lanterns {
            lantern.z -= speed * dt
            if lantern.z < -2 { lantern.z += 32 }
        }
        for dash in dashes {
            dash.z -= speed * dt
            if dash.z < -2 { dash.z += 32.5 }
        }
        layoutDecor()
    }

    private func layoutDecor() {
        for lantern in lanterns {
            let s = depthScale(lantern.z)
            lantern.node.position = CGPoint(x: cx + lantern.side * roadHalf0 * 1.18 * s, y: groundY(s))
            lantern.node.setScale(s)
            lantern.node.zPosition = 50 - lantern.z
        }
        for dash in dashes {
            let s1 = depthScale(dash.z), s2 = depthScale(dash.z + 1)
            let a = CGPoint(x: cx + dash.side * laneW0 * s1, y: groundY(s1))
            let b = CGPoint(x: cx + dash.side * laneW0 * s2, y: groundY(s2))
            dash.node.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            dash.node.zRotation = -atan2(b.x - a.x, b.y - a.y)
            (dash.node as? SKSpriteNode)?.size = CGSize(width: 10 * s1, height: hypot(b.x - a.x, b.y - a.y))
        }
    }

    // MARK: - Cảm ứng (dự phòng khi thử máy)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        let now = CACurrentMediaTime()
        switch phase {
        case .waiting, .calibStill, .calibLeft, .calibRight, .calibShout:
            touchMode = true
            startCountdown(resume: false)
        case .playing:
            if touchMode || !hub.bodyVisible(at: now) {
                if p.x < size.width / 3 { targetLane = max(0, targetLane - 1); return }
                if p.x > size.width * 2 / 3 { targetLane = min(2, targetLane + 1); return }
            }
            if !airborne { startJump(0.5, now) }
        case .gameOver:
            guard now - gameOverTime > 1 else { return }
            if recalibButton.frame.insetBy(dx: -40, dy: -30).contains(p) {
                touchMode = false
                show(nil)
                enter(hub.cameraReady ? .calibStill : .waiting)
            } else {
                startCountdown(resume: false)
            }
        case .countdown, .paused:
            break
        }
    }

    // MARK: - HUD

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
        frame.size.height += 30 // chỗ cho thanh tiến trình
        frame.origin.y -= 30
        messagePanel.path = CGPath(roundedRect: frame, cornerWidth: 28, cornerHeight: 28, transform: nil)
        progressBack.position = CGPoint(x: cx - 250, y: frame.minY + 34)
        progressFill.position = progressBack.position
    }

    private func updateHUD(_ now: TimeInterval, progress: Double?) {
        let showScore = phase == .playing || phase == .countdown || phase == .paused || phase == .gameOver
        // Chỉ gán chữ khi đổi: mỗi lần gán, SKLabelNode phải vẽ lại chữ thành ảnh.
        setText(scoreLabel, showScore ? "Điểm: \(score)" : "")
        setText(livesLabel, showScore ? String(repeating: "❤️" as String, count: max(lives, 0)) + String(repeating: "🤍" as String, count: Tune.lives - max(lives, 0)) : "")

        progressBack.isHidden = progress == nil || messagePanel.isHidden
        progressFill.isHidden = progressBack.isHidden
        progressFill.xScale = CGFloat(min(max(progress ?? 0, 0), 1))

        let calibrated = phase != .waiting && phase != .calibStill && phase != .calibLeft && phase != .calibRight
        for (i, slot) in laneSlots.enumerated() {
            let color: UIColor = i == targetLane ? .systemYellow : UIColor(white: 1, alpha: 0.22)
            if slot.fillColor != color { slot.fillColor = color }
            slot.isHidden = !calibrated
        }
        if calibrated, !touchMode, hub.bodyVisible(at: now), let point = hub.bodyPoint {
            let t = max(-1.6, min(1.6, calib.projection(point)))
            laneDot.isHidden = false
            laneDot.position = CGPoint(x: cx + t * 64, y: size.height - 70 - 34)
        } else {
            laneDot.isHidden = true
        }

        let low = calib.noiseDB - 5
        let high = max(calib.shoutDB, calib.jumpThresholdDB + 6) + 5
        func barFraction(_ db: Float) -> CGFloat { CGFloat(min(max((db - low) / (high - low), 0), 1)) }
        volumeFill.yScale = max(barFraction(level), 0.01)
        volumeFill.color = level > calib.jumpThresholdDB ? .systemOrange : .systemGreen
        volumeThreshold.position = CGPoint(x: 100, y: 120 + 300 * barFraction(calib.jumpThresholdDB))
    }

    // MARK: - Tiện ích

    private func setText(_ label: SKLabelNode, _ text: String) {
        if label.text != text { label.text = text }
    }

    private func mean(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let n = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }

    private func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return -50 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Float(sorted.count) * p))]
    }
}
