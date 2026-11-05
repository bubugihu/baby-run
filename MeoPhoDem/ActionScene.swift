import SpriteKit
import UIKit
import QuartzCore

/// Chế độ Action "Chém Lồng Đèn": lồng đèn và bánh ở lễ hội đêm bị tung lên,
/// vung tay thật nhanh để chém. Đừng chém pháo 🧨. Một ván 60 giây.
final class ActionScene: SKScene {

    // MARK: - Tinh chỉnh (chậm, dễ tha lỗi)

    private enum Tune {
        static let roundTime: Double = 60
        static let gravity: CGFloat = 620          // px/s², nhỏ → vật bay lơ lửng lâu
        static let firstGap: TimeInterval = 1.8    // giây giữa hai đợt lúc đầu
        static let minGap: TimeInterval = 0.95
        static let sliceSpeed: CGFloat = 1000      // tay đi nhanh hơn mức này (px/s) mới tính là chém
        static let touchSliceSpeed: CGFloat = 500
        static let maxJump: CGFloat = 480          // tay "nhảy" xa hơn thế trong 1 khung = Vision nhận nhầm, bỏ qua
        static let itemRadius: CGFloat = 78        // vùng chém trúng, rộng hơn hình một chút
        static let itemSize: CGFloat = 130
        static let reach: CGFloat = 2.0            // bao nhiêu bề rộng vai từ ngực tới mép màn hình
        static let bladeLife: TimeInterval = 0.2
        static let bodyLostPause: TimeInterval = 1.0
        static let bombPenalty = 5
        static let bombChance = 0.13
        static let comboWindow: TimeInterval = 0.35
        static let handsUpHold: TimeInterval = 0.8
    }

    private enum Phase { case waiting, ready, countdown, playing, paused, gameOver }

    private struct Kind {
        let emoji: String
        let color: UIColor
        let points: Int
        var bomb = false
    }

    private static let kinds: [Kind] = [
        Kind(emoji: "🏮", color: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1), points: 1),
        Kind(emoji: "🍡", color: UIColor(red: 1, green: 0.6, blue: 0.75, alpha: 1), points: 1),
        Kind(emoji: "🍙", color: UIColor(white: 0.96, alpha: 1), points: 1),
        Kind(emoji: "🎐", color: UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1), points: 1),
        Kind(emoji: "🍥", color: UIColor(red: 1, green: 0.75, blue: 0.85, alpha: 1), points: 1),
        Kind(emoji: "🌟", color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), points: 3), // hiếm
    ]
    private static let bombKind = Kind(emoji: "🧨", color: .systemOrange, points: 0, bomb: true)

    private final class Item {
        let node: SKSpriteNode
        let kind: Kind
        let kindIndex: Int
        var vel: CGVector
        let spin: CGFloat
        var dead = false
        init(node: SKSpriteNode, kind: Kind, kindIndex: Int, vel: CGVector, spin: CGFloat) {
            self.node = node; self.kind = kind; self.kindIndex = kindIndex; self.vel = vel; self.spin = spin
        }
    }

    /// Mảnh vỡ và giọt bắn ra khi chém, rơi theo trọng lực rồi mờ dần.
    private final class Piece {
        let node: SKSpriteNode
        var vel: CGVector
        let spin: CGFloat
        var life: CGFloat
        let maxLife: CGFloat
        init(node: SKSpriteNode, vel: CGVector, spin: CGFloat, life: CGFloat) {
            self.node = node; self.vel = vel; self.spin = spin; self.life = life; self.maxLife = life
        }
    }

    /// Một "lưỡi kiếm": tay trái, tay phải, hoặc ngón tay (chế độ cảm ứng).
    private final class Blade {
        struct Sample { let p: CGPoint; let t: TimeInterval; let fast: Bool }
        var samples: [Sample] = []
        var last: CGPoint?
        var lastTime: TimeInterval = 0
        var display: CGPoint?
        var seenTime: TimeInterval = 0
        let glow = SKShapeNode()
        let core = SKShapeNode()
        let cursor = SKShapeNode(circleOfRadius: 24)
    }

    // MARK: - Trạng thái

    private let hub = InputHub.shared
    private var phase: Phase = .waiting
    private var phaseStart: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var built = false
    private var touchMode = false

    private var chest = CGPoint(x: 0.66, y: 0.5)
    private var up = CGVector(dx: 0, dy: 1)
    private var shoulder: CGFloat = 0.15
    private var hasBody = false
    private var lastHandsFrame = -1
    private var lastHandsTime: TimeInterval = 0

    private let blades = [Blade(), Blade(), Blade()]   // 0 trái, 1 phải, 2 cảm ứng
    private var items: [Item] = []
    private var pieces: [Piece] = []
    private var itemTextures: [SKTexture] = []
    private var halfTextures: [(SKTexture, SKTexture)] = []
    private var bombTexture = SKTexture()
    private var dotTexture = SKTexture()

    private var timeLeft = Tune.roundTime
    private var playTime: Double = 0
    private var nextSpawn: TimeInterval = 0
    private var score = 0
    private var sliced = 0
    private var bombsHit = 0
    private var bestCombo = 0
    private var comboCount = 0
    private var comboTime: TimeInterval = 0
    private var handsUpSince: TimeInterval?
    private var resuming = false
    private var bodyLostSince: TimeInterval?
    private var gameOverTime: TimeInterval = 0
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "actionBest") }
        set { UserDefaults.standard.set(newValue, forKey: "actionBest") }
    }

    /// Gọi khi người chơi bấm "Chọn chế độ khác".
    var onExit: (() -> Void)?

    // MARK: - Node

    private let world = SKNode()
    private let scoreLabel = ActionScene.makeLabel(size: 50)
    private let timeLabel = ActionScene.makeLabel(size: 50)
    private let messagePanel = SKShapeNode()
    private let titleLabel = ActionScene.makeLabel(size: 62)
    private let subLabel = ActionScene.makeLabel(size: 32)
    private let progressBack = SKSpriteNode(color: UIColor(white: 1, alpha: 0.2), size: CGSize(width: 500, height: 14))
    private let progressFill = SKSpriteNode(color: .systemYellow, size: CGSize(width: 500, height: 14))
    private let againButton = ActionScene.makeLabel(size: 36)
    private let homeButton = ActionScene.makeLabel(size: 36)
    private let flash = SKSpriteNode(color: .systemRed, size: .zero)

    private var cx: CGFloat { size.width / 2 }

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
        backgroundColor = UIColor(red: 0.07, green: 0.05, blue: 0.14, alpha: 1)
        addChild(world)
        buildTextures(view)
        buildBackground(view)
        buildBlades()
        buildHUD()
        enter(.waiting)
    }

    /// Vẽ emoji thành ảnh một lần, sau đó chỉ dùng sprite (nhẹ hơn SKLabelNode rất nhiều).
    private func buildTextures(_ view: SKView) {
        func texture(_ emoji: String) -> SKTexture {
            let label = SKLabelNode(text: emoji)
            label.fontSize = Tune.itemSize * 2
            label.verticalAlignmentMode = .center
            return view.texture(from: label) ?? SKTexture()
        }
        for kind in Self.kinds {
            let t = texture(kind.emoji)
            itemTextures.append(t)
            halfTextures.append((SKTexture(rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), in: t),
                                 SKTexture(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), in: t)))
        }
        bombTexture = texture(Self.bombKind.emoji)
        let dot = SKShapeNode(circleOfRadius: 16)
        dot.fillColor = .white
        dot.strokeColor = .clear
        dotTexture = view.texture(from: dot) ?? SKTexture()
    }

    private func buildBackground(_ view: SKView) {
        let backdrop = SKNode()
        let skyImage = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.04, green: 0.04, blue: 0.16, alpha: 1).cgColor,
                          UIColor(red: 0.28, green: 0.09, blue: 0.30, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        let sky = SKSpriteNode(texture: SKTexture(image: skyImage), size: size)
        sky.position = CGPoint(x: cx, y: size.height / 2)
        backdrop.addChild(sky)

        for _ in 0..<50 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 1...2.4))
            star.fillColor = .white
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.25...0.8)
            star.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: size.height * 0.35...size.height))
            backdrop.addChild(star)
        }

        // Trăng tròn to sau núi.
        let glow = SKShapeNode(circleOfRadius: 150)
        glow.fillColor = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 0.1)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: size.width * 0.22, y: size.height * 0.58)
        backdrop.addChild(glow)
        let moon = SKShapeNode(circleOfRadius: 95)
        moon.fillColor = UIColor(red: 1, green: 0.93, blue: 0.78, alpha: 1)
        moon.strokeColor = .clear
        moon.position = glow.position
        backdrop.addChild(moon)

        // Hai lớp núi.
        for (layer, color) in [(0, UIColor(red: 0.13, green: 0.07, blue: 0.22, alpha: 1)),
                               (1, UIColor(red: 0.07, green: 0.04, blue: 0.12, alpha: 1))] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            var x: CGFloat = 0
            let base = layer == 0 ? size.height * 0.40 : size.height * 0.24
            path.addLine(to: CGPoint(x: 0, y: base))
            while x < size.width {
                let w = CGFloat.random(in: 160...300)
                path.addLine(to: CGPoint(x: x + w / 2, y: base + CGFloat.random(in: 40...140)))
                x += w
                path.addLine(to: CGPoint(x: x, y: base + CGFloat.random(in: -20...20)))
            }
            path.addLine(to: CGPoint(x: size.width, y: 0))
            path.closeSubpath()
            let mountain = SKShapeNode(path: path)
            mountain.fillColor = color
            mountain.strokeColor = .clear
            backdrop.addChild(mountain)
        }

        // Hai dây lồng đèn lễ hội võng ngang phía trên.
        for (i, height) in [size.height * 0.95, size.height * 0.86].enumerated() {
            let sag: CGFloat = 70
            let path = CGMutablePath()
            let x0: CGFloat = i == 0 ? -40 : size.width * 0.35
            let x1: CGFloat = i == 0 ? size.width * 0.7 : size.width + 40
            path.move(to: CGPoint(x: x0, y: height))
            path.addQuadCurve(to: CGPoint(x: x1, y: height), control: CGPoint(x: (x0 + x1) / 2, y: height - sag * 2))
            let rope = SKShapeNode(path: path)
            rope.strokeColor = UIColor(white: 0.1, alpha: 1)
            rope.lineWidth = 3
            backdrop.addChild(rope)
            for k in 1..<9 {
                let t = CGFloat(k) / 9
                let x = x0 + (x1 - x0) * t
                let y = height - sag * 4 * t * (1 - t)
                let lantern = SKLabelNode(text: "🏮")
                lantern.fontSize = 44
                lantern.verticalAlignmentMode = .top
                lantern.position = CGPoint(x: x, y: y)
                lantern.alpha = 0.85
                backdrop.addChild(lantern)
            }
        }

        let holder = SKNode()
        holder.setScale(2)
        holder.addChild(backdrop)
        if let texture = view.texture(from: holder) {
            let sprite = SKSpriteNode(texture: texture, size: size)
            sprite.position = CGPoint(x: cx, y: size.height / 2)
            sprite.zPosition = -100
            world.addChild(sprite)
        } else {
            backdrop.removeFromParent()
            backdrop.zPosition = -100
            world.addChild(backdrop)
        }
    }

    private func buildBlades() {
        let colors: [UIColor] = [UIColor(red: 0.4, green: 0.9, blue: 1, alpha: 1),
                                 UIColor(red: 1, green: 0.55, blue: 0.9, alpha: 1),
                                 UIColor(red: 0.6, green: 1, blue: 0.6, alpha: 1)]
        for (blade, color) in zip(blades, colors) {
            blade.glow.strokeColor = color.withAlphaComponent(0.45)
            blade.glow.lineWidth = 30
            blade.glow.lineCap = .round
            blade.glow.lineJoin = .round
            blade.glow.zPosition = 300
            blade.core.strokeColor = .white
            blade.core.lineWidth = 9
            blade.core.lineCap = .round
            blade.core.lineJoin = .round
            blade.core.zPosition = 301
            blade.cursor.strokeColor = color
            blade.cursor.lineWidth = 5
            blade.cursor.fillColor = color.withAlphaComponent(0.25)
            blade.cursor.zPosition = 302
            blade.cursor.isHidden = true
            addChild(blade.glow)
            addChild(blade.core)
            addChild(blade.cursor)
        }
    }

    private func buildHUD() {
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: 80, y: size.height - 90)
        scoreLabel.zPosition = 500
        addChild(scoreLabel)

        timeLabel.horizontalAlignmentMode = .right
        timeLabel.position = CGPoint(x: size.width - 80, y: size.height - 90)
        timeLabel.zPosition = 500
        addChild(timeLabel)

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
        let visible = hasBody && now - hub.handsTime < 0.6

        switch phase {
        case .waiting:
            if let problem = hub.cameraProblem {
                show("Cần quyền camera", problem + "\nChạm màn hình để chơi bằng ngón tay.")
            } else if !hub.cameraReady {
                show("Đang mở camera…")
            } else if visible {
                enter(.ready)
            } else {
                show("Lùi ra xa khoảng 1,5–2 mét",
                     "Đứng sao cho camera thấy từ đầu tới hông và cả hai tay.\n(Chạm màn hình để chơi bằng ngón tay)")
            }

        case .ready:
            if !visible {
                enter(.waiting)
                break
            }
            progress = handsUpProgress(now)
            show("Giơ hai tay lên cao để bắt đầu 🙌",
                 "Vung tay thật nhanh để chém lồng đèn và bánh.\nĐừng chém pháo 🧨")
            if progress ?? 0 >= 1 { startCountdown(resume: false) }

        case .countdown:
            let total = resuming ? 2.0 : 3.0
            let left = total - elapsed
            show("\(Int(ceil(max(left, 0.01))))", resuming ? "Chơi tiếp!" : "Vung tay để chém · Né pháo 🧨")
            if left <= 0 {
                show(nil)
                enter(.playing)
            }

        case .playing:
            if !touchMode && !visible {
                let since = bodyLostSince ?? now
                bodyLostSince = since
                if now - since > Tune.bodyLostPause {
                    bodyLostSince = nil
                    enter(.paused)
                    break
                }
            } else {
                bodyLostSince = nil
            }
            playTime += Double(dt)
            timeLeft -= Double(dt)
            if now >= nextSpawn { spawnWave(now) }
            if timeLeft <= 0 { finish(now) }

        case .paused:
            show("Không thấy bạn", "Quay lại khung hình để chơi tiếp.")
            if visible { startCountdown(resume: true) }

        case .gameOver:
            // Giơ hai tay lên để chơi lại (đợi một chút để không vô tình bắt đầu ngay).
            if elapsed > 1.5, visible, handsUpProgress(now) >= 1 { startCountdown(resume: false) }
        }

        // Vật vẫn bay khi đếm ngược/tạm dừng để màn hình không bị "đứng hình",
        // nhưng chỉ chém được lúc đang chơi.
        if phase == .playing || phase == .gameOver || phase == .countdown {
            updateItems(dt)
        }
        updatePieces(dt)
        updateCombo(now)
        drawBlades(now, dt)
        updateHUD()
        progressBack.isHidden = progress == nil || messagePanel.isHidden
        progressFill.isHidden = progressBack.isHidden
        progressFill.xScale = CGFloat(min(max(progress ?? 0, 0), 1))
    }

    private func startCountdown(resume: Bool) {
        resuming = resume
        if !resume { resetGame() }
        enter(.countdown)
    }

    private func resetGame() {
        for item in items { item.node.removeFromParent() }
        items.removeAll()
        timeLeft = Tune.roundTime
        playTime = 0
        score = 0
        sliced = 0
        bombsHit = 0
        bestCombo = 0
        comboCount = 0
        nextSpawn = CACurrentMediaTime() + 3.4
        bodyLostSince = nil
    }

    private func finish(_ now: TimeInterval) {
        timeLeft = 0
        let newBest = score > best
        best = max(best, score)
        gameOverTime = now
        enter(.gameOver)
        show(newBest ? "Kỷ lục mới! 🎉" : "Hết giờ! ⏱",
             "Điểm: \(score)   ·   Kỷ lục: \(best)\nChém trúng: \(sliced)   ·   Combo lớn nhất: \(bestCombo)   ·   Chém nhầm pháo: \(bombsHit)\n\nGiơ hai tay lên cao (hoặc chạm) để chơi lại")
    }

    /// 0...1: hai tay giơ cao hơn vai đủ lâu.
    private func handsUpProgress(_ now: TimeInterval) -> Double {
        guard let hands = hub.hands, now - hub.handsTime < 0.4,
              let l = hands.left, let r = hands.right,
              local(l).y > 0.9, local(r).y > 0.9 else {
            handsUpSince = nil
            return 0
        }
        let since = handsUpSince ?? now
        handsUpSince = since
        return (now - since) / Tune.handsUpHold
    }

    // MARK: - Tay → màn hình

    /// Toạ độ theo thân người: x sang phải, y lên trên, đơn vị = bề rộng vai, gốc ở ngực.
    private func local(_ p: CGPoint) -> CGPoint {
        let d = CGVector(dx: p.x - chest.x, dy: p.y - chest.y)
        let right = CGVector(dx: up.dy, dy: -up.dx)
        return CGPoint(x: (d.dx * right.dx + d.dy * right.dy) / shoulder,
                       y: (d.dx * up.dx + d.dy * up.dy) / shoulder)
    }

    /// Ngực ở giữa màn hình, hơi thấp; với tay sang ngang chạm mép màn hình.
    /// Vì đo theo bề rộng vai nên đứng xa hay gần đều như nhau.
    private func toScreen(_ p: CGPoint) -> CGPoint {
        let l = local(p)
        let scale = size.width * 0.5 / Tune.reach
        return CGPoint(x: cx + l.x * scale, y: size.height * 0.42 + l.y * scale)
    }

    private func readHands(_ now: TimeInterval) {
        guard hub.handsFrame != lastHandsFrame, let hands = hub.hands else { return }
        lastHandsFrame = hub.handsFrame
        // Ngực và vai được làm mượt để người lắc lư không làm cả khung toạ độ rung theo.
        // Mất người lâu rồi mới thấy lại (có thể là người khác): lấy luôn vị trí mới.
        if hub.handsTime - lastHandsTime > 1.5 { hasBody = false }
        lastHandsTime = hub.handsTime
        if hasBody {
            let a: CGFloat = 0.15
            chest = CGPoint(x: chest.x + (hands.chest.x - chest.x) * a, y: chest.y + (hands.chest.y - chest.y) * a)
            shoulder += (hands.shoulderWidth - shoulder) * 0.1
            var u = CGVector(dx: up.dx + (hands.up.dx - up.dx) * 0.1, dy: up.dy + (hands.up.dy - up.dy) * 0.1)
            let length = max(hypot(u.dx, u.dy), 0.001)
            u = CGVector(dx: u.dx / length, dy: u.dy / length)
            up = u
        } else {
            chest = hands.chest
            shoulder = hands.shoulderWidth
            up = hands.up
            hasBody = true
        }
        let t = hub.handsTime
        for (blade, wrist) in zip(blades.prefix(2), [hands.left, hands.right]) {
            guard let wrist else { continue }
            feed(blade, toScreen(wrist), t, minSpeed: Tune.sliceSpeed)
        }
    }

    /// Thêm một vị trí mới cho lưỡi kiếm. Đoạn từ vị trí cũ tới mới đủ nhanh thì chém.
    private func feed(_ blade: Blade, _ p: CGPoint, _ t: TimeInterval, minSpeed: CGFloat) {
        var fast = false
        if let last = blade.last, t - blade.lastTime < 0.25, t > blade.lastTime {
            let dist = hypot(p.x - last.x, p.y - last.y)
            if dist < Tune.maxJump {
                fast = dist / CGFloat(t - blade.lastTime) > minSpeed
                if fast && phase == .playing { slice(from: last, to: p, t) }
            } else {
                blade.samples.removeAll()
            }
        }
        blade.samples.append(.init(p: p, t: t, fast: fast))
        blade.last = p
        blade.lastTime = t
        blade.seenTime = t
        if blade.display == nil { blade.display = p }
    }

    private func drawBlades(_ now: TimeInterval, _ dt: CGFloat) {
        let showCursor = phase == .playing || phase == .countdown || phase == .ready || phase == .gameOver
        for (i, blade) in blades.enumerated() {
            blade.samples.removeAll { now - $0.t > Tune.bladeLife }
            let path = CGMutablePath()
            for (a, b) in zip(blade.samples, blade.samples.dropFirst()) where b.fast {
                if path.isEmpty || path.currentPoint != a.p { path.move(to: a.p) }
                path.addLine(to: b.p)
            }
            blade.glow.path = path
            blade.core.path = path

            // Vòng tròn chỉ chỗ tay đang ở (cảm ứng thì không cần).
            if i < 2, showCursor, !touchMode, let target = blade.last, now - blade.seenTime < 0.35 {
                var d = blade.display ?? target
                let k = min(1, dt * 22)
                d = CGPoint(x: d.x + (target.x - d.x) * k, y: d.y + (target.y - d.y) * k)
                blade.display = d
                blade.cursor.position = d
                blade.cursor.isHidden = false
            } else {
                blade.cursor.isHidden = true
                if now - blade.seenTime > 0.35 { blade.display = nil }
            }
        }
    }

    // MARK: - Vật bay

    private func spawnWave(_ now: TimeInterval) {
        let gap = max(Tune.minGap, Tune.firstGap - playTime / 60)
        nextSpawn = now + gap * Double.random(in: 0.85...1.15)
        let maxCount = min(4, 1 + Int(playTime / 15))
        let count = Int.random(in: 1...maxCount)
        for n in 0..<count {
            let bomb = playTime > 6 && n == 0 && Double.random(in: 0...1) < Tune.bombChance
            spawnItem(bomb: bomb, delayY: CGFloat(n) * -40)
        }
    }

    private func spawnItem(bomb: Bool, delayY: CGFloat) {
        let index: Int
        if bomb {
            index = -1
        } else {
            // Ngôi sao 3 điểm hiếm hơn các vật khác.
            index = Double.random(in: 0...1) < 0.08 ? Self.kinds.count - 1 : Int.random(in: 0..<(Self.kinds.count - 1))
        }
        let kind = bomb ? Self.bombKind : Self.kinds[index]
        let texture = bomb ? bombTexture : itemTextures[index]
        let node = SKSpriteNode(texture: texture)
        // Giữ đúng tỉ lệ ảnh emoji, cạnh dài nhất = itemSize.
        let ts = texture.size()
        let fit = Tune.itemSize / max(ts.width, ts.height, 1)
        node.size = CGSize(width: ts.width * fit, height: ts.height * fit)
        let x = CGFloat.random(in: 200...(size.width - 200))
        node.position = CGPoint(x: x, y: -90 + delayY)
        node.zPosition = bomb ? 210 : 200
        world.addChild(node)

        let apex = size.height * CGFloat.random(in: 0.55...0.85)
        let vy = sqrt(2 * Tune.gravity * (apex - node.position.y))
        let flight = 2 * vy / Tune.gravity
        let targetX = cx + CGFloat.random(in: -250...250)
        let vx = (targetX - x) / flight * CGFloat.random(in: 0.6...1.1)
        items.append(Item(node: node, kind: kind, kindIndex: index,
                          vel: CGVector(dx: vx, dy: vy), spin: CGFloat.random(in: -2.5...2.5)))
    }

    private func updateItems(_ dt: CGFloat) {
        for item in items {
            item.vel.dy -= Tune.gravity * dt
            item.node.position.x += item.vel.dx * dt
            item.node.position.y += item.vel.dy * dt
            item.node.zRotation += item.spin * dt
            if item.vel.dy < 0 && item.node.position.y < -160 {
                item.dead = true
                item.node.removeFromParent()
            }
        }
        items.removeAll { $0.dead }
    }

    private func slice(from a: CGPoint, to b: CGPoint, _ t: TimeInterval) {
        for item in items where !item.dead {
            guard distance(item.node.position, toSegment: a, b) < Tune.itemRadius else { continue }
            item.dead = true
            item.node.removeFromParent()
            let angle = atan2(b.y - a.y, b.x - a.x)
            if item.kind.bomb {
                explode(item)
            } else {
                cut(item, angle: angle)
            }
        }
        items.removeAll { $0.dead }
    }

    private func cut(_ item: Item, angle: CGFloat) {
        let now = CACurrentMediaTime()
        score += item.kind.points
        sliced += 1
        comboCount = now - comboTime < Tune.comboWindow ? comboCount + 1 : 1
        comboTime = now
        if item.kind.points > 1 { popup("+\(item.kind.points)", at: item.node.position, color: .systemYellow) }

        // Hai nửa bay tách ra hai bên đường chém. Xoay hai nửa cho đường cắt của ảnh
        // (cạnh dọc giữa ảnh) trùng với hướng tay vung.
        let (left, right) = halfTextures[item.kindIndex]
        let rotation = angle - .pi / 2
        let across = CGVector(dx: cos(rotation), dy: sin(rotation))  // vuông góc với đường chém
        let full = item.node.size
        for (texture, sign) in [(left, CGFloat(-1)), (right, CGFloat(1))] {
            let half = SKSpriteNode(texture: texture)
            half.size = CGSize(width: full.width / 2, height: full.height)
            half.zRotation = rotation
            let offset = full.width / 4 * sign
            half.position = CGPoint(x: item.node.position.x + across.dx * offset,
                                    y: item.node.position.y + across.dy * offset)
            half.zPosition = 205
            world.addChild(half)
            let push: CGFloat = 230
            pieces.append(Piece(node: half,
                                vel: CGVector(dx: item.vel.dx * 0.5 + across.dx * push * sign,
                                              dy: max(item.vel.dy * 0.4, 0) + across.dy * push * sign + 120),
                                spin: sign * CGFloat.random(in: 2...5), life: 1.1))
        }
        splash(at: item.node.position, color: item.kind.color, count: 9)
    }

    private func explode(_ item: Item) {
        score = max(0, score - Tune.bombPenalty)
        bombsHit += 1
        comboCount = 0
        popup("💥 -\(Tune.bombPenalty)", at: item.node.position, color: .systemRed)
        splash(at: item.node.position, color: .systemOrange, count: 16)
        flash.removeAllActions()
        flash.run(.sequence([.fadeAlpha(to: 0.4, duration: 0.05), .fadeOut(withDuration: 0.45)]))
        world.run(.sequence([.moveBy(x: 20, y: 0, duration: 0.04), .moveBy(x: -40, y: 0, duration: 0.08),
                             .moveBy(x: 20, y: 0, duration: 0.04)]))
    }

    private func splash(at p: CGPoint, color: UIColor, count: Int) {
        for _ in 0..<count {
            let drop = SKSpriteNode(texture: dotTexture)
            let r = CGFloat.random(in: 10...22)
            drop.size = CGSize(width: r, height: r)
            drop.color = color
            drop.colorBlendFactor = 1
            drop.position = p
            drop.zPosition = 204
            world.addChild(drop)
            let a = CGFloat.random(in: 0...(2 * .pi))
            let v = CGFloat.random(in: 150...450)
            pieces.append(Piece(node: drop, vel: CGVector(dx: cos(a) * v, dy: sin(a) * v + 100), spin: 0,
                                life: CGFloat.random(in: 0.4...0.7)))
        }
    }

    private func updatePieces(_ dt: CGFloat) {
        for piece in pieces {
            piece.life -= dt
            piece.vel.dy -= Tune.gravity * 1.3 * dt
            piece.node.position.x += piece.vel.dx * dt
            piece.node.position.y += piece.vel.dy * dt
            piece.node.zRotation += piece.spin * dt
            piece.node.alpha = max(0, min(1, piece.life / piece.maxLife * 1.5))
            if piece.life <= 0 { piece.node.removeFromParent() }
        }
        pieces.removeAll { $0.life <= 0 }
    }

    /// Chém liền 3 vật trở lên trong một nhát = thưởng thêm.
    private func updateCombo(_ now: TimeInterval) {
        guard comboCount > 0, now - comboTime > Tune.comboWindow else { return }
        if comboCount >= 3 {
            score += comboCount
            bestCombo = max(bestCombo, comboCount)
            popup("Combo x\(comboCount)! +\(comboCount)", at: CGPoint(x: cx, y: size.height * 0.62), color: .systemYellow, size: 64)
        }
        comboCount = 0
    }

    private func popup(_ text: String, at p: CGPoint, color: UIColor, size fontSize: CGFloat = 48) {
        let label = Self.makeLabel(size: fontSize)
        label.text = text
        label.fontColor = color
        label.position = p
        label.zPosition = 400
        addChild(label)
        label.setScale(0.6)
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.12), .moveBy(x: 0, y: 90, duration: 0.8)]),
            .fadeOut(withDuration: 0.25),
            .removeFromParent()
        ]))
    }

    private func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let lengthSq = ab.dx * ab.dx + ab.dy * ab.dy
        var t: CGFloat = 0
        if lengthSq > 0 { t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / lengthSq)) }
        return hypot(p.x - (a.x + ab.dx * t), p.y - (a.y + ab.dy * t))
    }

    // MARK: - Cảm ứng (dự phòng, chạy được trên Simulator)

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
            touchMode = true
            startCountdown(resume: false)
        case .gameOver:
            guard now - gameOverTime > 1 else { return }
            if homeButton.frame.insetBy(dx: -40, dy: -20).contains(p) {
                exitToMenu()
            } else {
                startCountdown(resume: false)
            }
        case .playing, .countdown, .paused:
            let blade = blades[2]
            blade.last = p
            blade.lastTime = touch.timestamp
            blade.samples.removeAll()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, phase == .playing else { return }
        // Dùng mốc thời gian của cảm ứng cho tốc độ, còn đuôi kiếm dùng đồng hồ của game.
        let blade = blades[2]
        let p = touch.location(in: self)
        let t = touch.timestamp
        if let last = blade.last, t > blade.lastTime {
            let dist = hypot(p.x - last.x, p.y - last.y)
            let fast = dist / CGFloat(t - blade.lastTime) > Tune.touchSliceSpeed
            if fast { slice(from: last, to: p, t) }
            blade.samples.append(.init(p: p, t: CACurrentMediaTime(), fast: fast))
        }
        blade.last = p
        blade.lastTime = t
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        blades[2].last = nil
    }

    private func exitToMenu() {
        touchMode = false
        resetGame()
        show(nil)
        enter(.waiting)
        onExit?()
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
        frame.size.height += 30
        frame.origin.y -= 30
        messagePanel.path = CGPath(roundedRect: frame, cornerWidth: 28, cornerHeight: 28, transform: nil)
        progressBack.position = CGPoint(x: cx - 250, y: frame.minY + 34)
        progressFill.position = progressBack.position
    }

    private func updateHUD() {
        let showScore = phase == .playing || phase == .countdown || phase == .paused || phase == .gameOver
        setText(scoreLabel, showScore ? "Điểm: \(score)" : "")
        setText(timeLabel, showScore ? "⏱ \(Int(ceil(max(timeLeft, 0))))" : "")
        timeLabel.fontColor = timeLeft <= 10 && phase == .playing ? .systemOrange : .white
    }

    private func setText(_ label: SKLabelNode, _ text: String) {
        if label.text != text { label.text = text }
    }
}
