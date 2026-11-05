# Bu chơi 🐱🏮

App trò chơi vận động cho iPad, điều khiển bằng cả cơ thể qua camera trước. Mở app sẽ thấy màn **chọn chế độ**:

| Chế độ | Trò chơi |
|---|---|
| 🏃 **Running** | *Mèo Phố Đêm*: chạy vô tận 3 làn, bước ngang để đổi làn, nhảy thật để nhảy (chi tiết bên dưới). |
| ⚔️ **Action** | *Chém Lồng Đèn*: lồng đèn, bánh dango, onigiri… bị tung lên từ dưới, **vung tay thật nhanh** để chém. Đừng chém pháo 🧨 (trừ 5 điểm). Ván 60 giây, chém liền 3 vật trở lên trong một nhát được thưởng combo. Giơ hai tay lên cao để bắt đầu / chơi lại. |
| 💃 **Dance** | *Múa theo mẫu*: nhạc vui chạy, màn hình hiện người que làm một tư thế tay đơn giản (giơ tay, dang tay, chữ V, chống hông, vỗ tay…), bé làm giống trong khoảng 3 giây thì được ⭐. 10 tư thế mỗi ván, không bị phạt, dành cho bé 5–6 tuổi. Nhạc tự tổng hợp trong app, không cần file nhạc. |

## Running: Mèo Phố Đêm

Game chạy vô tận, **không dùng tay**: một chú mèo chạy trên phố Nhật về đêm, 3 làn, né thùng gỗ.

- **Bước sang trái/phải** → mèo đổi làn (đứng chỗ nào, mèo chạy làn đó). Dùng camera trước + Apple Vision.
- **Nhảy thật** (hông nhích lên) hoặc chạm màn hình → mèo nhảy. Không còn đo âm thanh, không dùng micro.
- **Nhân vật bằng khuôn mặt bạn**: trước khi vào game, chụp ảnh khuôn mặt (đếm ngược 3 giây) để thay con mèo. Mặt sẽ lắc lư khi chạy và đung đưa khi đổi làn. Ảnh được lưu lại cho lần sau; muốn đổi thì bấm "🙂 Đổi nhân vật" ở màn hết ván.
- 3 mạng, đụng thùng mất 1 mạng. Điểm = quãng đường + 10 điểm mỗi thùng né được. Có lưu kỷ lục.
- Đầu ván hiệu chỉnh ~12 giây: đứng yên → bước trái → bước phải (3 bước).
- Mọi xử lý nằm trên iPad, không cần mạng, không gọi API.

## Cần có

- Máy Mac có **Xcode 16 trở lên** (tải miễn phí trên App Store).
- iPad chạy **iPadOS 17 trở lên**, cáp USB‑C/Lightning nối với Mac.
- Một Apple ID (tài khoản miễn phí cũng được; app cài kiểu miễn phí sẽ hết hạn sau 7 ngày, chỉ cần bấm Run lại).

## Build và cài lên iPad

1. Giải nén, mở file `MeoPhoDem.xcodeproj` bằng Xcode.
2. Bấm vào project **MeoPhoDem** ở cột trái → tab **Signing & Capabilities**:
   - Tick **Automatically manage signing**.
   - **Team**: chọn Apple ID của bạn (nếu chưa có: Xcode → Settings → Accounts → bấm `+` để thêm).
   - Nếu báo lỗi Bundle Identifier đã bị dùng, đổi `com.bubugihu.MeoPhoDem` thành tên khác, ví dụ `com.tenban.MeoPhoDem`.
3. Cắm iPad vào Mac, mở khoá iPad, bấm **Tin cậy (Trust)** nếu được hỏi.
4. Trên iPad: **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển (Developer Mode)** → bật, iPad sẽ khởi động lại.
5. Ở thanh trên cùng của Xcode, chọn iPad của bạn làm thiết bị chạy, rồi bấm nút ▶︎ (Run).
6. Lần đầu mở app, nếu iPad báo "Nhà phát triển không được tin cậy": vào **Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị** → chọn Apple ID của bạn → **Tin cậy**. Sau đó mở lại app.
7. Cho phép **Camera** khi app hỏi (app không dùng micro).

## Cách chơi

1. Chọn nhân vật: lại gần iPad, bấm **📸 Chụp** (hoặc dùng mèo).
2. Dựng iPad **nằm ngang** trên giá, camera trước hướng về phía bạn, ngang tầm hông/ngực.
3. Đứng lùi ra **khoảng 2 mét**, sao cho khung camera nhỏ ở góc thấy được cả người.
4. (Tuỳ chọn) Mirror lên TV: kéo Trung tâm điều khiển → **Phản chiếu màn hình** → chọn Apple TV / TV hỗ trợ AirPlay.
5. Làm theo màn hiệu chỉnh, rồi chơi.
6. Hết ván: nhảy lên (hoặc chạm) để chơi lại. Chạm "↻ Hiệu chỉnh lại" nếu đổi chỗ đứng hoặc đổi người chơi.

**Thử nhanh không cần đứng xa:** chạm màn hình trong lúc hiệu chỉnh để chuyển sang chế độ cảm ứng (chạm 1/3 trái/phải để đổi làn, chạm giữa để nhảy). Chế độ này cũng chạy được trên Simulator.

### Cách chơi Action

1. Ở màn chọn chế độ, chạm **Action**.
2. Đứng cách iPad khoảng **1,5–2 mét**, camera thấy từ đầu tới hông và cả hai tay.
3. Giơ hai tay lên cao khoảng 1 giây để bắt đầu. Hai vòng tròn trên màn hình là vị trí hai tay bạn.
4. Vung tay thật nhanh qua vật đang bay để chém. Tay đi chậm thì không chém (để không chém nhầm khi chỉ đưa tay).
5. Thử nhanh không cần đứng xa: chạm màn hình ở màn chờ để chơi bằng cách vuốt ngón tay (chạy được trên Simulator).

## Chỉnh độ khó

Các con số nằm ở `Tune` đầu file `MeoPhoDem/GameScene.swift`: tốc độ (`startSpeed`, `maxSpeed`), khoảng cách giữa các thùng (`firstGap`, `minGap`), độ cao nhảy (`jumpSpeed`, `jumpRise` (nhảy thật phải cao cỡ nào mới tính)), số mạng (`lives`).
Action: `Tune` đầu file `MeoPhoDem/ActionScene.swift`: thời gian ván (`roundTime`), trọng lực (`gravity`, nhỏ thì vật bay chậm hơn), tốc độ vung tay tối thiểu để chém (`sliceSpeed`, giảm xuống thì vung nhẹ cũng chém), độ rộng vùng trúng (`itemRadius`), tỉ lệ pháo (`bombChance`).

## Cấu trúc code

| File | Việc |
|---|---|
| `MeoPhoDemApp.swift`, `ContentView.swift` | Khởi động app, màn chọn chế độ, hiện từng game + khung camera nhỏ, màn Dance "sắp ra mắt" |
| `BodyTracker.swift` | Camera trước + Vision body pose → vị trí hông, vai, hai cổ tay, ~30 lần/giây |
| `ActionScene.swift` | SpriteKit: chế độ Action (chém lồng đèn bằng vung tay) |
| `VoiceMeter.swift` | AVAudioEngine → âm lượng (dB) liên tục |
| `Calibration.swift` | Hướng trái/phải, chia làn |
| `GameScene.swift` | SpriteKit: chế độ Running, cảnh phố đêm giả 3D, mèo, thùng gỗ, điểm, mạng, màn hiệu chỉnh |
| `CameraPreview.swift` | Khung xem camera ở góc |
| `FacePicker.swift`, `FaceCapture.swift` | Màn chọn nhân vật: chụp, cắt khuôn mặt tròn, lưu ảnh |
