# Kế hoạch bàn giao: app "Bu chơi" (3 chế độ)

Dành cho phiên Claude chạy trên máy Mac của người dùng (có Xcode, build được). Code dưới đây được viết trên cloud, **chưa từng được biên dịch hay chạy thử**. Việc chính: build, sửa lỗi biên dịch, chạy thử trên iPad, chỉnh cho mượt.

## Bối cảnh
- App iPad native (Swift, SwiftUI + SpriteKit, iPadOS 17+, Xcode 16+). Tên hiển thị "Bu chơi" (chủ đã đặt: app học là "Bu học" – repo learnfirst, app này là "Bu chơi"; icon chữ bubu giống app học), target `MeoPhoDem`, project dùng synchronized folder nên file `.swift` mới trong `MeoPhoDem/` tự được thêm vào target.
- Người chơi chính: **bé 5–6 tuổi**. Game chậm, dễ tha lỗi, không phạt nặng.
- Điều khiển bằng camera trước + Vision body pose. **Không dùng micro** (bé la ồn, người dùng không muốn). Mọi xử lý trên máy, không cần mạng.
- Quy trình git: commit thẳng vào `main`, không tạo nhánh hay PR.
- Mirror ra TV qua AirPlay chỉ để xem lớn.

## Cấu trúc
| File | Việc |
|---|---|
| `ContentView.swift` | Màn chọn chế độ (`ModeMenu`) và 3 view: `RunningView`, `ActionView`, `DanceView`. Mỗi game có nút về màn chọn. |
| `BodyTracker.swift` | Camera + Vision. Ghi `InputHub.bodyPoint` (hông) và `InputHub.hands` (`HandPose`: ngực, bề rộng vai, hướng lên, hai cổ tay). |
| `GameScene.swift`, `Calibration.swift` | **Running** "Mèo Phố Đêm". |
| `ActionScene.swift` | **Action** "Chém Lồng Đèn". |
| `DanceScene.swift`, `DanceMusic.swift` | **Dance** "Múa theo mẫu" + nhạc tự tổng hợp. |
| `FacePicker.swift`, `FaceCapture.swift` | Chụp ảnh mặt (dùng cho Running và đầu người que ở Dance). |
| `VoiceMeter.swift` | **Không còn dùng** (Running đã bỏ hét). Có thể xoá. |

## Ba game

### 1. Running (đã có từ trước, vừa đổi cách nhảy)
Chạy vô tận 3 làn trên phố Nhật về đêm, né thùng gỗ, 3 mạng. Bước ngang = đổi làn (hiệu chỉnh 3 bước: đứng giữa, bước trái, bước phải). **Nhảy = nhảy thật** (hông nhích lên so với mức đứng, `Tune.jumpRise`) hoặc chạm màn hình. Ảnh mặt bé thay con mèo.

### 2. Action "Chém Lồng Đèn"
Lồng đèn, bánh, onigiri… bị tung lên, vung tay thật nhanh để chém, né pháo 🧨 (trừ 5 điểm). 60 giây, combo từ 3 vật/nhát. Cổ tay được đổi sang toạ độ theo thân người (đơn vị = bề rộng vai) nên đứng xa gần đều được. Chém khi tốc độ cổ tay > `Tune.sliceSpeed`. Giơ hai tay để bắt đầu/chơi lại. Chạm vuốt ngón tay là chế độ dự phòng.

### 3. Dance "Múa theo mẫu"
Nhạc 100 BPM (tổng hợp bằng `AVAudioSourceNode`, không có file nhạc). Mỗi ván 10 tư thế tay đơn giản; người que mẫu bên trái, hình người que của bé bên phải (vẽ theo cổ tay thật). Giống trong ~0,5 giây là được ⭐, không phạt. Tư thế là vị trí hai cổ tay so với ngực trong `DanceScene.poses`: dễ thêm/bớt. Chạm màn hình = chơi thử không cần camera. Quy tắc: **không tư thế khó** (không hip hop, trồng cây chuối, không dùng chân).

## Tiến độ trên máy Mac (05/11/2026)
- [x] Bước 1 build: chỉ có 1 lỗi biên dịch (`private var speed` trùng `SKNode.speed` → đổi `runSpeed`). Đã cài lên iPad.
- [x] Bước 2 dọn: xoá `VoiceMeter.swift`, bỏ `noiseDB`/`shoutDB`/`jumpThresholdDB`, `levelDB`/`micReady`/`micProblem`.
- [x] Thêm icon bubu (`Assets.xcassets`), tên "Bu chơi".
- [ ] Bước 3–5: cần chạy thử với bé trên iPad thật.

## Việc cần làm (theo thứ tự)
1. **Build**: mở `MeoPhoDem.xcodeproj`, chọn Team, Run trên iPad thật. Sửa lỗi biên dịch (nhiều khả năng ở `DanceMusic.swift`, `DanceScene.swift`, `ActionScene.swift`; đây là code chưa từng chạy).
2. **Dọn**: xoá `VoiceMeter.swift`; trong `Calibration.swift` bỏ `noiseDB`/`shoutDB`/`jumpThresholdDB` nếu không còn ai dùng (đã bỏ khỏi `GameScene`).
3. **Chạy thử từng game trên iPad thật**, đứng cách ~1,5–2 m:
   - Running: nhảy thật có nhận không? Bước ngang bị nhảy nhầm không? (`Tune.jumpRise` 0.05 là số đoán; hông cũng nhích khi bước.) Nếu nhảy thật quá khó với bé thì cân nhắc cho nhảy tự động khi gặp thùng hoặc chỉ dùng chạm.
   - Action: vòng tròn tay có đi đúng tay bé không (kiểm tra trái/phải, lên/xuống, nhất là khi iPad xoay)? Vung bình thường có chém được không (`sliceSpeed`)? Vision hay mất cổ tay khi vung nhanh: nếu hay mất, thử nội suy hoặc hạ ngưỡng tin cậy (`handPose` trong `BodyTracker.swift`).
   - Dance: tư thế có nhận đúng không? Các số trong `poses` là ước lượng theo tỉ lệ cơ thể người lớn, cần đo lại với bé thật (bé tay ngắn tương đối). Chỉnh `avgTolerance`/`maxTolerance`. Nhạc có nghe êm tai không, có bị rè/giật không; `DanceMusic` không đụng `AVAudioSession`, nếu không nghe tiếng thì xem lại category.
4. **Độ mượt**: đo FPS và độ trễ camera → màn hình (ước lượng chưa đo: ~0,1 giây, AirPlay thêm 0,1–0,2 giây). Nếu giật, xem `BodyTracker` (VGA 640x480) và số node trong từng scene.
5. **Hoàn thiện** (sau khi 3 game chạy ổn): âm thanh hiệu ứng, thêm tư thế cho Dance, hình nhân vật hoạt hình thay người que, màn thống kê/kỷ lục chung.

## Điểm rủi ro đã biết
- `BodyTracker` nhân toạ độ x với tỉ lệ khung hình (`aspect`) để đơn vị x và y bằng nhau; nếu iPad xoay mà ảnh lệch thì kiểm tra `videoRotationAngle`.
- Trái/phải trong Action và Dance dựa vào vị trí trên màn hình (cổ tay nào ở bên trái hình), không dựa vào tên khớp, để khỏi phụ thuộc camera có lật gương hay không.
- Dance cần thấy cả hai cổ tay và hai vai; thiếu một cổ tay thì không chấm. Bé đứng gần quá sẽ mất tay.
- `GameScene.swift` rất lớn (~1000 dòng); cân nhắc tách khi có thời gian, nhưng đừng làm trước khi mọi thứ chạy.

## Câu hỏi còn mở cho người dùng
- Dance: có muốn thêm nhạc thật (bài thiếu nhi) thay nhạc tổng hợp? Nếu có cần file nhạc và bản quyền.
- Nhân vật Dance: giữ người que + ảnh mặt hay đổi sang nhân vật hoạt hình?
- Running: nhảy bằng nhảy thật hay chạm hay tự nhảy?
- "Đĩa bay / người ngoài hành tinh bé hét đuổi" người dùng nhắc **không có trong code**; hỏi lại họ có muốn làm không (hiện micro đã bỏ).
