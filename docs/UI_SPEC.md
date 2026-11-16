# ViVuView — Yêu cầu giao diện

Xem [PLAN.md](PLAN.md) cho phạm vi, [TECH_SPEC.md](TECH_SPEC.md) cho kỹ thuật.

Tham chiếu: LilyView (cửa sổ chỉ có ảnh, cử chỉ, hiệu ứng chuyển ảnh), Pixea (status bar, panel thông tin, hàng thumbnail). Pixea đã cài trên máy; khi làm từng phần liên quan thì mở Pixea đối chiếu, các kích thước dưới đây là điểm khởi đầu.

## 1. Nguyên tắc

- Ảnh là giao diện. Mọi thành phần khác (thanh tiêu đề, status bar, filmstrip, panel) mặc định ẩn, chỉ hiện khi cần, và không bao giờ làm ảnh nhảy vị trí.
- Mọi thao tác phản hồi trong 1 frame; việc nặng chạy nền, hình mờ hiện trước rồi nét dần.
- Các lớp phủ (thanh tiêu đề, status bar, filmstrip, panel) dùng vật liệu kính của hệ thống trên macOS 26 trở lên và nền mờ tối trên macOS 14–15; bố cục và kích thước giống nhau ở mọi phiên bản. Chữ trắng. Cửa sổ Settings theo chế độ sáng/tối của hệ thống.
- Giao diện có tiếng Việt và tiếng Anh, theo ngôn ngữ hệ thống. Chuỗi trong tài liệu này là bản tiếng Việt.
- Mọi thời lượng, kích thước nằm trong `Tuning.swift`.

## 2. Cửa sổ xem ảnh

```
        (rê chuột vào cửa sổ → hai thanh hiện ra, phủ lên ảnh)
┌────────────────────────────────────────────────────────────┐
│ ● ● ●            IMG_0421.CR3                    ⓘ  ▦  ▭  │ ← thanh tiêu đề, 28pt
│                                                            │
│                                                            │
│                          ẢNH                               │
│                                                            │
│                                                            │
│ 12/384 · 6000×4000 · 24,5 MB · 150% · 14/03/2026 09:12 · ƒ/2.8 1/250s ISO 200 35mm │ ← status bar, 24pt
└────────────────────────────────────────────────────────────┘
```

### 2.1 Khung cửa sổ
- `NSWindow` có `.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable`; thanh tiêu đề trong suốt, ẩn tiêu đề chuẩn. Bo góc và bóng theo hệ thống. Nền đen.
- Một cửa sổ chính duy nhất; mở file khác thì thay nội dung.
- **Kích thước theo ảnh:** ảnh nhỏ hơn vùng khả dụng → cửa sổ đúng 100% (theo chế độ Point/Pixel, mục 3); lớn hơn → thu vừa vùng khả dụng. Vùng khả dụng = `visibleFrame` của màn hình trừ chiều cao filmstrip nếu đang hiện. Tối thiểu 320×240pt (ảnh nhỏ hơn thì canh giữa trên nền đen).
- Chuyển ảnh: tâm cửa sổ giữ nguyên, kẹp trong vùng khả dụng.
- Zoom ở chế độ cửa sổ: cửa sổ lớn dần theo ảnh tới khi chạm vùng khả dụng, sau đó ảnh pan bên trong.
- Người dùng tự kéo giãn cửa sổ → "khung cố định": các ảnh sau fit trong khung đó. Trở về tự co theo ảnh bằng mục menu **Cửa sổ → Theo kích thước ảnh** (có dấu tích, cũng có trong menu chuột phải); nhấn `\` hai lần liên tiếp là lối tắt cho cùng việc đó.
- Kéo chuột: đang fit → di chuyển cửa sổ; đang zoom → pan ảnh.
- Fullscreen (`F`): nền đen, ảnh fit; mọi thao tác như cũ.

### 2.2 Thanh tiêu đề (hover)
- Hiện khi chuột ở trong cửa sổ và vừa di chuyển; ẩn sau 2s chuột đứng yên hoặc khi chuột rời cửa sổ. Fade 150ms.
- Trái: 3 nút đèn giao thông chuẩn. Giữa: tên file. Phải: 3 nút biểu tượng: ⓘ panel thông tin, ▦ gallery, ▭ filmstrip.
- Nền kính mờ, cao 28pt, phủ lên ảnh (không đẩy ảnh).

### 2.3 Status bar
- Một dòng, cao 24pt, sát đáy cửa sổ, phủ lên ảnh, nền kính mờ, chữ 11pt dạng số đơn cách (monospaced digits).
- **Khi nào hiện** (Settings → Hiển thị → Status bar):
  - *Khi rê chuột* (mặc định): hiện/ẩn cùng lúc với thanh tiêu đề.
  - *Luôn hiện*.
  - *Không bao giờ*.
  - Ở mọi chế độ trừ "Không bao giờ": **click một lần lên ảnh** để ghim/bỏ ghim status bar (đang ghim thì luôn hiện cho tới khi click lại). Click chỉ tính khi không kéo và không phải double-click.
- **Nội dung**, cách nhau bằng ` · `, theo thứ tự ưu tiên; cửa sổ hẹp thì bỏ dần từ phải sang:
  1. Vị trí trong thư mục: `12/384`
  2. Kích thước pixel: `6000×4000`
  3. Dung lượng: `24,5 MB`
  4. Mức zoom: `150%` (ghi `Fit` khi đang fit)
  5. Ngày chụp (EXIF), không có thì ngày sửa file
  6. Thông số chụp nếu có: `ƒ/2.8 1/250s ISO 200 35mm`
  7. Máy ảnh: `Canon EOS R5`
  8. Trạng thái đặc biệt: `đang nạp…`, `tối đa 1/2` (ảnh bị giới hạn độ phân giải), `kéo giãn` (ảnh 16-bit), `khung 3/24` (ảnh động)
- Tên file không lặp ở status bar (đã có ở thanh tiêu đề); ở fullscreen, nơi không có thanh tiêu đề, tên file đứng đầu status bar.
- Khi zoom thay đổi mà status bar đang ẩn: hiện một nhãn nhỏ mức zoom ở góc dưới phải trong 1s.

## 3. Chế độ render Point / Pixel

- **Point (mặc định):** 100% = 1 pixel ảnh ứng với 1 point. Trên màn Retina 2×, ảnh 1200×800 hiển thị 1200×800pt (2400×1600 pixel màn hình), cùng cỡ với Preview và trình duyệt.
- **Pixel:** 100% = 1 pixel ảnh ứng với 1 pixel màn hình. Ảnh 1200×800 hiển thị 600×400pt trên Retina, nét từng pixel.
- Ảnh hưởng tới: phím `0`, chạm đúp, kích thước cửa sổ khi ảnh nhỏ hơn màn hình, con số % trên status bar.
- Đổi trong Settings có hiệu lực ngay với ảnh đang xem.

## 4. Hiệu ứng chuyển ảnh (kiểu LilyView)

Mô tả theo trí nhớ của người dùng về LilyView; sẽ tinh chỉnh ở mốc M4 khi thử tay.

- Sang ảnh **kế tiếp**: ảnh cũ trượt sang **trái** màn hình và mờ dần; ảnh mới xuất hiện từ phía **phải**, rõ dần cho tới khi vào đúng vị trí. Lùi thì ngược lại.
- Chuyển động diễn ra trên **cả màn hình**, không bị cắt bởi khung cửa sổ (kỹ thuật: lớp phủ trong suốt toàn màn hình, TECH_SPEC mục 6).
- Quãng trượt: 35% chiều rộng màn hình. Alpha ảnh cũ 1 → 0, ảnh mới 0 → 1. Ảnh mới đổi kích thước dần từ khung của ảnh cũ sang khung fit của nó.
- **Bằng trackpad:** ảnh bám theo ngón tay (tiến độ = quãng vuốt / 35% chiều rộng). Thả tay khi quá 30% hoặc vuốt nhanh → hoàn tất (ease-out, tối đa 160ms); chưa tới → bật ngược về. Vuốt tiếp ngay khi hiệu ứng trước chưa xong thì hiệu ứng trước nhảy tới đích và hiệu ứng mới bắt đầu.
- **Bằng phím:** chạy tự động 160ms ease-out (chỉnh trong Settings: 0–300ms). **Giữ phím** (từ lần lặp thứ hai) → không hiệu ứng, đổi ảnh tức thì để lướt nhanh.
- Settings → *Hiệu ứng chuyển ảnh*: Trượt + mờ (mặc định) / Chỉ mờ / Không.
- Tôn trọng "Giảm chuyển động" của hệ thống: tự chuyển sang "Chỉ mờ".
- Đánh đổi có chủ ý: vì ảnh bám theo ngón tay, mỗi lần vuốt chỉ chuyển 1 ảnh. Lướt nhanh nhiều ảnh thì giữ phím ←/→ hoặc dùng filmstrip. Xem lại ở mốc M4 khi thử tay.
- Phương án lùi nếu bản thử ở M0.5 cho thấy hiệu ứng toàn màn hình bị chớp: cùng hiệu ứng nhưng diễn ra trong khung cửa sổ.

## 5. Trackpad và chuột

| Cử chỉ | Đang fit | Đang zoom |
|---|---|---|
| Vuốt 2 ngón ngang | Chuyển ảnh, ảnh bám theo ngón tay (mục 4) | Pan |
| Vuốt 2 ngón dọc | Lên: hiện filmstrip · Xuống: ẩn filmstrip | Pan |
| Pinch | Zoom quanh con trỏ; thu nhỏ quá mức fit rồi thả → vào Gallery | Zoom quanh con trỏ |
| Xoay 2 ngón | Xoay theo tay; thả ra bắt dính bội số 90° | như bên |
| Chạm đúp 2 ngón / double-click | Fit ↔ 100% tại con trỏ | như bên |
| Vuốt 3 ngón ngang | Chuyển ảnh (nếu hệ thống bật) | như bên |
| Click | Ghim/bỏ ghim status bar | như bên |
| Kéo chuột | Di chuyển cửa sổ | Pan |
| Lăn chuột thường (không phải trackpad) | Theo Settings: zoom (mặc định) hoặc chuyển ảnh | Zoom |
| Chuột phải | Menu: Mở bằng…, Hiện trong Finder, Copy ảnh, Copy đường dẫn, Xoay trái/phải, Chuyển vào Thùng rác | như bên |

Khoá trục cuộn theo 8pt đầu tiên của mỗi cử chỉ. Vuốt ngang trong pha quán tính bị bỏ qua.

## 6. Bàn phím

| Phím | Chức năng |
|---|---|
| ← → · Space, ⇧Space · PageUp, PageDown | Ảnh trước / sau (giữ để lướt nhanh) |
| Home / End | Ảnh đầu / cuối thư mục |
| ↑ ↓ hoặc + − | Zoom to / nhỏ (bước ×1.25, quanh tâm) |
| `0` | 100% (theo chế độ Point/Pixel) |
| `\` | Fit |
| Mũi tên khi đang zoom | Pan; khi đó dùng ⌘← / ⌘→ để chuyển ảnh |
| `[` / `]` | Xoay trái / phải 90° |
| F | Fullscreen |
| T | Hiện/ẩn filmstrip |
| G hoặc Enter | Vào/ra Gallery |
| I | Hiện/ẩn panel thông tin |
| E | Bật/tắt kéo giãn tương phản (ảnh 16-bit/float) |
| `,` `.` | Ảnh động: lùi/tiến 1 khung; Space tạm dừng/phát khi là ảnh động |
| ⌘O · ⌘W · ⌘Q · ⌘, | Mở · Đóng · Thoát · Settings |
| ⌘C · ⌘⇧C | Copy ảnh · Copy đường dẫn |
| ⌘⇧R | Hiện trong Finder |
| ⌘⌫ | Chuyển vào Thùng rác (hỏi xác nhận, tắt được trong Settings), rồi sang ảnh kế |
| Esc | Đóng panel thông tin → thoát Gallery → thoát fullscreen → đóng cửa sổ |

Không có phím `1`, `2`, `R`. Bảng phím nằm ở một nơi (`KeyBindings.swift`) và mọi lệnh cũng có trong menu chính.

## 7. Filmstrip (hàng thumbnail sát đáy màn hình)

```
 màn hình
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│                    ┌───────────────────────┐                             │
│                    │   cửa sổ ảnh chính    │                             │
│                    └───────────────────────┘                             │
│                                                                          │
│┌────────────────────────────────────────────────────────────────────────┐│
││ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢   ← filmstrip, 1 hàng  ││
│└────────────────────────────────────────────────────────────────────────┘│
│                              (Dock)                                      │
└──────────────────────────────────────────────────────────────────────────┘
```

- Một **panel riêng** (`NSPanel` không viền, không nhận focus, nổi trên cửa sổ thường), **nằm ngoài cửa sổ chính**, đặt sát đáy `visibleFrame` của màn hình đang chứa cửa sổ chính (ngay trên Dock nếu Dock hiện), rộng **toàn bộ chiều ngang màn hình**.
- Một hàng duy nhất. Chiều cao thumbnail theo Settings: Nhỏ 48 / Vừa 72 (mặc định) / Lớn 104pt; panel cao hơn thumbnail 16pt. Thumbnail rộng theo tỉ lệ ảnh (kẹp 0.5–2.5 lần chiều cao), cách nhau 4pt, bo góc 4pt. Nền kính mờ tối.
- Ảnh hiện tại nằm **giữa** hàng, viền trắng 2pt; hàng trượt mượt (120ms) khi chuyển ảnh; đầu và cuối thư mục thì hàng dừng ở mép.
- Tương tác: click thumbnail → nhảy tới ảnh đó; cuộn 2 ngón (ngang hoặc dọc) trên hàng → lướt hàng mà chưa đổi ảnh; rê chuột → tooltip tên file; chuột phải → cùng menu với ảnh.
- **Hiện/ẩn** (Settings → Filmstrip):
  - *Tự ẩn* (mặc định): hiện khi nhấn `T`, vuốt 2 ngón lên, hoặc đưa chuột xuống sát đáy màn hình; tự trượt xuống ẩn sau 2s chuột rời panel.
  - *Luôn hiện*: panel cố định; vùng khả dụng của cửa sổ chính trừ đi chiều cao panel.
  - `T` luôn bật/tắt trạng thái ghim.
- Khi filmstrip hiện, cửa sổ chính bị đẩy lên nếu đang chồng lên panel (không bao giờ che nhau).
- Fullscreen: panel phủ lên đáy ảnh (tự ẩn).
- Thumbnail chỉ nằm trong RAM; ô chưa có thumbnail hiện nền xám, ô chưa biết tỉ lệ coi là 1:1.
- Ẩn cùng app (khi app không còn ở trước, panel cũng ẩn).
- Vùng nóng "đưa chuột xuống sát đáy màn hình" nằm cùng chỗ với vùng tự hiện của Dock. Quy tắc: nếu Dock ở đáy và đang tự ẩn, vùng nóng của filmstrip là dải 4pt ngay trên mép đáy và chỉ kích hoạt khi cửa sổ ViVuView đang ở trước. Hành vi này được thử ở M0.5; nếu không ổn định thì bỏ vùng nóng, filmstrip chỉ hiện bằng `T` hoặc vuốt 2 ngón lên.

## 8. Gallery (masonry)

```
┌────────────────────────────────────────────────────────────────────┐
│ ● ● ●   ~/Photos/DaLat-2026 · 384 ảnh · IMG_0421.CR3      [− cỡ +] │
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                     │
│ │     │ │     │ │     │ │     │ │     │ │     │  mọi cột cùng       │
│ │     │ └─────┘ │     │ └─────┘ │     │ │     │  chiều ngang        │
│ └─────┘ ┌─────┐ │     │ ┌─────┐ └─────┘ │     │                     │
│ ┌─────┐ │     │ └─────┘ │▓▓▓▓▓│ ┌─────┐ └─────┘  chiều dọc theo     │
│ │     │ │     │ ┌─────┐ │▓▓▓▓▓│ │     │ ┌─────┐  tỉ lệ ảnh          │
│ └─────┘ └─────┘ │     │ └─────┘ │     │ │     │  ▓ = đang chọn      │
└────────────────────────────────────────────────────────────────────┘
```

- **Cửa sổ tự phóng to:** vào Gallery, cửa sổ animate 200ms ra toàn bộ vùng khả dụng của màn hình (không phải fullscreen hệ thống); frame cũ được ghi nhớ. Chọn ảnh để thoát → cửa sổ thu về khung fit của ảnh được chọn, tâm tại tâm cũ. Đang fullscreen thì giữ fullscreen. Filmstrip ẩn trong lúc ở Gallery.
- **Bố cục:** chiều rộng cột mục tiêu theo Settings (mặc định 220pt, 120–480pt), khe 6pt, lề 12pt. `số cột = floor((W − 2·lề + khe) / (mục tiêu + khe))`; chiều rộng cột thực chia đều phần còn lại nên mọi ô **cùng chiều ngang**. Mỗi ảnh theo thứ tự thư mục vào **cột đang thấp nhất** (hoà thì cột trái hơn). Chiều cao ô = rộng cột × (cao/rộng của ảnh), kẹp trong [0.3, 3.0] × rộng cột; ảnh vượt giới hạn thì cắt giữa.
- **Khi kích thước ảnh chưa đọc xong:** thư mục ≤ 2.000 ảnh thì chờ đủ rồi mới hiện lưới (thường dưới 0,5s; quá 300ms thì hiện lưới giữ chỗ trước). Thư mục lớn hơn: phần đầu đã biết kích thước được xếp chính thức, phần còn lại là ô giữ chỗ tỉ lệ 3:2 màu xám, kèm vạch tiến độ mảnh ở thanh trên. Ô đã xếp chính thức **không bao giờ nhảy cột**; khi ô giữ chỗ được thay bằng ô thật, ô đang chọn được giữ đứng yên trên màn hình.
- Ô bo góc 4pt; ô đang chọn viền trắng 2pt; ô đang rê sáng lên nhẹ. Thanh trên hiện đường dẫn thư mục, số ảnh, tên file của ô đang chọn/rê, và nút đổi cỡ ô.
- **Chuyển cảnh:** vào — ảnh đang xem thu nhỏ (220ms, ease-out) về đúng ô của nó, các ô khác hiện dần; chọn — ô phóng to thành chế độ xem.
- **Điều khiển:** cuộn 2 ngón dọc; ←/→ = ô trước/sau theo thứ tự thư mục; ↑/↓ = ô gần nhất phía trên/dưới trong cùng cột; PageUp/PageDown; Home/End; gõ chữ để nhảy tới file có tên bắt đầu bằng chuỗi gõ; pinch hoặc ⌘+/⌘− đổi cỡ ô; Enter/click/pinch-out trên ô = mở; Esc hoặc G = quay lại ảnh trước đó.

## 9. Panel thông tin (phím I, kiểu Pixea)

```
┌──────────────────────────────┬───────────────────────┐
│                              │ ▁▂▅▇▅▃▂▁  histogram   │
│                              │ ───────────────────── │
│            ẢNH               │ Chung                 │
│                              │  Tên      IMG_0421.CR3│
│                              │  Loại     Canon RAW   │
│                              │  Kích thước 6000×4000 │
│                              │  Dung lượng 24,5 MB   │
│                              │  …                    │
│                              │ Máy ảnh               │
│                              │  ƒ/2.8 · 1/250s · ISO…│
│                              │ Vị trí   [bản đồ nhỏ] │
└──────────────────────────────┴───────────────────────┘
   cửa sổ ảnh (không đổi)         panel 280pt, gắn bên phải
```

- Panel rộng 280pt, **gắn vào cạnh phải cửa sổ ảnh** như một cửa sổ con (đi theo khi cửa sổ di chuyển/đổi cỡ), cao bằng cửa sổ ảnh (tối thiểu 360pt), không che ảnh. Không đủ chỗ bên phải màn hình thì gắn bên trái. Ở fullscreen và Gallery: phủ lên mép phải.
- Nền kính mờ, cuộn dọc khi nội dung dài. Nội dung đổi ngay khi chuyển ảnh.
- Các nhóm (nhóm trống thì ẩn):
  1. **Histogram** RGB chồng nhau + luma, cao 80pt.
  2. **Chung:** tên, thư mục (click → hiện trong Finder), loại, kích thước pixel + megapixel, dung lượng, DPI, độ sâu bit, profile màu, ngày chụp, ngày sửa.
  3. **Máy ảnh:** hãng/model, ống kính, tiêu cự, khẩu độ, tốc độ, ISO, bù phơi sáng, flash, cân bằng trắng.
  4. **Vị trí:** bản đồ nhỏ 160pt + toạ độ (click → mở Maps). Chỉ khi ảnh có GPS.
  5. **Hiển thị:** mức zoom, độ phân giải đang hiển thị (với ảnh khổng lồ: level và trạng thái nạp), số khung (ảnh động).
- Mọi giá trị chọn và copy được. `I` hoặc Esc để đóng; trạng thái mở/đóng được nhớ.

## 10. Cửa sổ cấu hình (⌘,)

Cửa sổ Settings chuẩn macOS, viết bằng SwiftUI `Form` kiểu grouped, 5 tab (Chung, Hiển thị, Điều khiển, Định dạng, Hiệu năng), rộng 520pt. Mọi thay đổi có hiệu lực ngay, không có nút Lưu. Chỉ gồm các tham số cần thiết:

```
┌───────────────────────────────────────────────────────┐
│  Chung   Hiển thị   Điều khiển   Định dạng   Hiệu năng │
├───────────────────────────────────────────────────────┤
│ Kích thước 100%          (•) Point   ( ) Pixel        │
│ Khi mở ảnh               [Vừa màn hình, tối đa 100% ▾]│
│ Nền                      [Đen ▾]                      │
│ Status bar               [Khi rê chuột ▾]             │
│ Hiệu ứng chuyển ảnh      [Trượt + mờ ▾]               │
│ Thời lượng hiệu ứng      ──●────── 160 ms             │
│ ───────────────────────────────────────────────────── │
│ Filmstrip                [Tự ẩn ▾]                    │
│ Cỡ thumbnail filmstrip   [Vừa ▾]                      │
│ Độ rộng cột Gallery      ────●──── 220 pt             │
└───────────────────────────────────────────────────────┘
```

| Tab | Tham số | Giá trị (mặc định in đậm) |
|---|---|---|
| **Chung** | Sắp xếp ảnh trong thư mục | **Tên (như Finder)** / Ngày sửa / Ngày chụp / Dung lượng; tăng/giảm |
| | Khi tới ảnh cuối | **Dừng lại** / Quay vòng về đầu |
| | Hỏi trước khi chuyển vào Thùng rác | **Bật** / Tắt |
| | Thoát app khi đóng cửa sổ | **Bật** / Tắt |
| **Hiển thị** | Kích thước 100% | **Point** / Pixel |
| | Khi mở ảnh | **Vừa màn hình, tối đa 100%** / Luôn vừa màn hình / Luôn 100% |
| | Nền | **Đen** / Xám đậm / Ô caro (cho ảnh trong suốt) |
| | Status bar | **Khi rê chuột** / Luôn hiện / Không bao giờ |
| | Hiệu ứng chuyển ảnh | **Trượt + mờ** / Chỉ mờ / Không |
| | Thời lượng hiệu ứng | 0–300ms, **160ms** |
| | Filmstrip | **Tự ẩn** / Luôn hiện |
| | Cỡ thumbnail filmstrip | Nhỏ / **Vừa** / Lớn |
| | Độ rộng cột Gallery | 120–480pt, **220pt** |
| **Điều khiển** | Lăn chuột thường | **Zoom** / Chuyển ảnh |
| | Đảo chiều vuốt chuyển ảnh | **Tắt** / Bật |
| | Bước zoom bằng phím | 1.1 / **1.25** / 1.5 / 2 |
| | Giữ mức zoom khi chuyển ảnh | **Tắt** (mỗi ảnh về fit) / Bật |
| **Hiệu năng** | Số ảnh nạp trước mỗi phía | 1 / **2** / 3 / 4 |
| | Bộ nhớ cho thumbnail | 128 / 256 / **384** / 768 MB (384 MB ≈ 9.000 ảnh) |
| | Bộ nhớ cho ảnh lớn (tile) | 256 / **512** / 1024 / 2048 MB |
| | RAW | **Dùng ảnh xem trước nhúng** / Luôn xử lý RAW đầy đủ |
| | Dòng ghi chú | "ViVuView không lưu thumbnail hay bộ nhớ đệm ra đĩa." |

Bảng phím tắt không chỉnh được trong đợt này; xem ở menu Trợ giúp → Phím tắt.

### 10.1 Tab Định dạng — gắn định dạng file với ViVuView

Chọn những loại file mà double-click trong Finder sẽ mở bằng ViVuView.

```
┌───────────────────────────────────────────────────────┐
│  Chung   Hiển thị   Điều khiển   Định dạng   Hiệu năng │
├───────────────────────────────────────────────────────┤
│ Mở bằng ViVuView khi double-click trong Finder:       │
│                                                       │
│ Ảnh thông dụng                        [Chọn cả nhóm]  │
│  ☑ JPEG  .jpg .jpeg                                   │
│  ☑ PNG   .png                                         │
│  ☑ HEIC  .heic .heif              đang mở bằng: Preview│
│  ☐ GIF   .gif                                         │
│  ☑ WebP  .webp                                        │
│  …                                                    │
│ RAW máy ảnh                           [Chọn cả nhóm]  │
│  ☐ Canon .cr2 .cr3                                    │
│  …                                                    │
│ Chuyên dụng                           [Chọn cả nhóm]  │
│  ☑ TIFF  .tif .tiff                                   │
│  ☐ PSD/PSB .psd .psb                                  │
│                                                       │
│ [Chọn tất cả]  [Bỏ chọn tất cả]                       │
└───────────────────────────────────────────────────────┘
```

- Danh sách cuộn, chia 3 nhóm:
  - **Ảnh thông dụng:** JPEG, PNG, HEIC/HEIF, GIF, WebP, AVIF, BMP, JPEG XL, ICO/ICNS.
  - **RAW máy ảnh:** Canon (CR2, CR3), Nikon (NEF), Sony (ARW), Fujifilm (RAF), Adobe DNG, Olympus/OM (ORF), Panasonic (RW2), Pentax (PEF); thêm một dòng "RAW khác" gộp các loại còn lại mà hệ thống đọc được.
  - **Chuyên dụng:** TIFF/BigTIFF, PSD/PSB, OpenEXR, JPEG 2000, TGA.
- Mỗi dòng: ô chọn, tên định dạng, các đuôi file, và bên phải tên app hiện đang là mặc định của loại đó (chữ mờ; ghi "ViVuView" khi đã gắn).
- **Trạng thái ô chọn phản ánh hệ thống**, không phải một giá trị lưu riêng: mỗi lần mở tab, app hỏi macOS xem trình mặc định của từng loại là gì. Nếu người dùng đổi trong Finder (Get Info → Open with) thì tab này hiển thị đúng theo.
- **Tích:** đặt ViVuView làm mặc định cho loại đó, có hiệu lực ngay. macOS có thể hiện hộp thoại xác nhận của hệ thống; nếu người dùng từ chối thì ô tự bỏ tích.
- **Bỏ tích:** trả về app đã là mặc định trước khi ViVuView nhận (app được ghi nhớ lúc tích); nếu không còn app đó thì trả về Preview.
- Nút "Chọn cả nhóm", "Chọn tất cả", "Bỏ chọn tất cả" áp dụng hàng loạt; khi đó chỉ hiện một dòng tổng kết lỗi (nếu có) thay vì từng thông báo.
- Mặc định khi mới cài: **không tích gì**. ViVuView không tự chiếm định dạng nào; file vẫn mở được bằng ViVuView qua "Open With", kéo-thả, ⌘O.
- Dòng ghi chú cuối tab: "Bạn cũng có thể đổi trong Finder: chọn file → Get Info → Open with → Change All."

## 11. Trạng thái đặc biệt

- **Chưa mở ảnh:** cửa sổ 480×320pt nền đen, dòng chữ "Kéo ảnh vào đây hoặc nhấn ⌘O".
- **Đang nạp, chưa có hình nào:** giữ ảnh cũ; status bar ghi tên file mới + `đang nạp…`. Nếu quá 300ms: vòng tiến độ nhỏ ở giữa.
- **Ảnh khổng lồ đang dựng:** ảnh mờ hiện trước; vạch tiến độ 2pt ở mép dưới ảnh; vùng đang zoom nét dần từng mảng.
- **File lỗi / không hỗ trợ:** biểu tượng cảnh báo + tên file + lý do ngắn; vẫn chuyển ảnh bình thường.
- **Thư mục chỉ có 1 ảnh:** vuốt/phím chuyển ảnh làm ảnh nhún nhẹ rồi về chỗ cũ.
- **Hết thư mục** (khi không quay vòng): cùng hiệu ứng nhún.
