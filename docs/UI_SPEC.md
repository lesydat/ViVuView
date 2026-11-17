# ViVuView — Yêu cầu giao diện

Xem [PLAN.md](PLAN.md) cho phạm vi, [TECH_SPEC.md](TECH_SPEC.md) cho kỹ thuật.

Tham chiếu: LilyView (cửa sổ chỉ có ảnh, cử chỉ, hiệu ứng chuyển ảnh), Pixea (status bar, panel thông tin, hàng thumbnail). Pixea đã cài trên máy; khi làm từng phần liên quan thì mở Pixea đối chiếu, các kích thước dưới đây là điểm khởi đầu.

## 1. Nguyên tắc

- Ảnh là giao diện. Mọi thành phần khác (thanh tiêu đề, status bar, filmstrip, panel) mặc định ẩn, chỉ hiện khi cần, và không bao giờ làm ảnh nhảy vị trí.
- Mọi thao tác phản hồi trong 1 frame; việc nặng chạy nền, hình mờ hiện trước rồi nét dần.
- Các lớp phủ (thanh tiêu đề, status bar, filmstrip, panel) dùng vật liệu kính của hệ thống trên macOS 26 trở lên và nền mờ tối trên macOS 14–15; bố cục và kích thước giống nhau ở mọi phiên bản. Chữ trắng. Cửa sổ Settings theo chế độ sáng/tối của hệ thống.
- Giao diện đa ngữ (mục 12), mặc định theo ngôn ngữ hệ thống, không có thì tiếng Anh. Chuỗi trong tài liệu này là bản tiếng Việt.
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
- `NSWindow` có `.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable`; thanh tiêu đề trong suốt, ẩn tiêu đề chuẩn. Bo góc và bóng theo hệ thống. Nền theo Settings → Nền (cửa sổ, view nội dung và lớp Metal cùng một màu, áp dụng ngay từ khung hình đầu).
- Gắn một `NSToolbar` rỗng, kiểu `.unifiedCompact`, không vạch ngăn: nút đèn giao thông thụt vào khỏi góc theo kiểu hệ thống hiện tại mà thanh tiêu đề vẫn thấp (cửa sổ chỉ có thanh tiêu đề thì nút nằm sát góc). Toolbar không vẽ gì, click dưới nó vẫn tới ảnh. Giữ toolbar cả khi fullscreen (ẩn/hiện nó quanh fullscreen làm thanh tiêu đề đổi chiều cao sau đó).
- Fullscreen: thanh tiêu đề (có toolbar) tự ẩn cùng thanh menu (`autoHideToolbar`), chỉ trượt xuống khi đưa chuột lên đỉnh màn hình, và khi đó có đủ nút đèn giao thông cùng tiêu đề `tên file — ViVuView` (ở chế độ cửa sổ tiêu đề hệ thống bị ẩn, thanh tiêu đề hover hiện tên file).
- Vào/thoát fullscreen không tính là người dùng tự kéo giãn cửa sổ: thoát ra cửa sổ vẫn tự co theo ảnh.
- Một cửa sổ chính duy nhất; mở file khác thì thay nội dung.
- **Vị trí:** mở app hoặc mở một file (⌘O, Finder, kéo-thả) thì cửa sổ nằm đúng giữa vùng khả dụng của màn hình (không dùng `NSWindow.center()`, vốn đặt cao hơn giữa).
- **Kích thước theo ảnh:** ảnh nhỏ hơn vùng khả dụng → cửa sổ đúng 100% (theo chế độ Point/Pixel, mục 3); lớn hơn → thu vừa vùng khả dụng. Vùng khả dụng = `visibleFrame` của màn hình trừ chiều cao filmstrip nếu đang hiện. Tối thiểu 320×240pt (ảnh nhỏ hơn thì canh giữa trên nền đen).
- Chuyển ảnh: tâm cửa sổ giữ nguyên, kẹp trong vùng khả dụng.
- Zoom ở chế độ cửa sổ: cửa sổ lớn dần theo ảnh tới khi chạm vùng khả dụng, sau đó ảnh pan bên trong.
- Người dùng tự kéo giãn cửa sổ → "khung cố định": các ảnh sau fit trong khung đó. Trở về tự co theo ảnh bằng mục menu **Cửa sổ → Theo kích thước ảnh** (có dấu tích, cũng có trong menu chuột phải); nhấn `\` hai lần liên tiếp là lối tắt cho cùng việc đó.
- Kéo chuột: đang fit → di chuyển cửa sổ; đang zoom → pan ảnh.
- Fullscreen (`F`): nền đen, ảnh fit; mọi thao tác như cũ.

### 2.2 Thanh tiêu đề (hover)
- Hiện khi chuột ở trong cửa sổ và vừa di chuyển thật; ẩn sau 2s chuột đứng yên hoặc khi chuột rời cửa sổ. Fade 150ms.
- Chuyển ảnh mà chuột đứng yên trên cửa sổ thì **không** hiện thanh tiêu đề và status bar: cửa sổ đổi cỡ/dời chỗ dưới con trỏ sinh sự kiện chuột vào/di chuyển giả, chỉ tính khi toạ độ con trỏ trên màn hình đổi.
- Trái: 3 nút đèn giao thông chuẩn. Giữa: tên file. Phải: 3 nút biểu tượng: ⓘ panel thông tin, ▦ gallery, ▭ filmstrip.
- Nền kính mờ, cao bằng thanh tiêu đề hệ thống có toolbar gọn (40pt trên macOS 27, tối thiểu 28pt; đo khi ở cửa sổ, giữ nguyên qua fullscreen) để nút nằm giữa dải, phủ lên ảnh (không đẩy ảnh).

### 2.3 Status bar
- Một dòng, cao 24pt, sát đáy cửa sổ, phủ lên ảnh, nền kính mờ, chữ 11pt dạng số đơn cách (monospaced digits).
- **Khi nào hiện** (Settings → Hiển thị → Status bar):
  - *Khi rê chuột* (mặc định): hiện/ẩn cùng lúc với thanh tiêu đề.
  - *Luôn hiện*.
  - *Không bao giờ*.
  - Chế độ *Khi rê chuột*, khi bật Settings → Hiển thị → "Click lên ảnh để ghim status bar" (**mặc định tắt**): **click một lần lên ảnh** để ghim/bỏ ghim status bar (đang ghim thì luôn hiện cho tới khi click lại). Click chỉ tính khi không kéo, không phải double-click và không phải cú click đưa cửa sổ lên trước (cửa sổ đang ở sau). Đang ghim thì status bar có biểu tượng ghim ở mép phải.
- **Nội dung**, cách nhau bằng ` · `, theo thứ tự ưu tiên; cửa sổ hẹp thì bỏ dần từ phải sang:
  1. Vị trí trong thư mục: `12/384`
  2. Kích thước pixel: `6000×4000`
  3. Dung lượng: `24,5 MB`
  4. Mức zoom: `150%` (ghi `Fit` khi đang fit)
  5. Ngày chụp (EXIF), không có thì ngày sửa file
  6. Thông số chụp nếu có: `ƒ/2.8 1/250s ISO 200 35mm`
  7. Máy ảnh: `Canon EOS R5`
  8. Trạng thái đặc biệt: `đang nạp…`, `tối đa 1/2` (ảnh bị giới hạn độ phân giải), `kéo giãn` (ảnh 16-bit), `khung 3/24` (ảnh động)
- Tên file không lặp ở status bar (đã có ở thanh tiêu đề); ở fullscreen, nơi thanh tiêu đề chỉ hiện khi đưa chuột lên đỉnh màn hình, tên file đứng đầu status bar.
- Khi zoom thay đổi mà status bar đang ẩn: hiện một nhãn nhỏ mức zoom ở góc dưới phải trong 1s.

## 3. Chế độ render Point / Pixel

- **Point (mặc định):** 100% = 1 pixel ảnh ứng với 1 point. Trên màn Retina 2×, ảnh 1200×800 hiển thị 1200×800pt (2400×1600 pixel màn hình), cùng cỡ với Preview và trình duyệt.
- **Pixel:** 100% = 1 pixel ảnh ứng với 1 pixel màn hình. Ảnh 1200×800 hiển thị 600×400pt trên Retina, nét từng pixel.
- Ảnh hưởng tới: phím `0`, chạm đúp, kích thước cửa sổ khi ảnh nhỏ hơn màn hình, con số % trên status bar.
- Đổi trong Settings có hiệu lực ngay với ảnh đang xem.

## 4. Hiệu ứng chuyển ảnh (kiểu LilyView)

Mô tả theo trí nhớ của người dùng về LilyView; sẽ tinh chỉnh ở mốc M4 khi thử tay.

- Sang ảnh **kế tiếp**: ảnh cũ trượt sang **trái** màn hình và mờ dần; ảnh mới xuất hiện từ phía **phải**, rõ dần cho tới khi vào đúng vị trí. Lùi thì ngược lại.
- Chuyển động diễn ra trên **cả màn hình**, không bị cắt bởi khung cửa sổ (kỹ thuật: lớp phủ trong suốt toàn màn hình, TECH_SPEC mục 6). Ở chế độ cửa sổ, ảnh trên lớp phủ được bo góc bằng góc cửa sổ (17pt trên macOS 26+, ~10pt trước đó) để lúc trao lại cho cửa sổ không đổi từ góc vuông sang góc bo.
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
| Click | Ghim/bỏ ghim status bar (nếu bật trong Settings, mặc định tắt) | như bên |
| Kéo chuột | Di chuyển cửa sổ | Pan |
| Lăn chuột (chuột có con lăn) | Không làm gì (không có gì để cuộn) | Cuộn ảnh (pan) dọc; ⇧ hoặc lăn ngang để cuộn ngang |
| Giữ ⌘ (hoặc ⌃) + lăn chuột / cuộn 2 ngón | Zoom quanh con trỏ, mỗi nấc ×1.1 | như bên |
| Chuột phải (hoặc Control-click) | Menu hệ thống (kính lỏng trên macOS 26+), phím tắt hiện ở bên phải từng mục: Mở bằng ▸ (app mặc định đầu tiên, các app mở được loại file này, "Ứng dụng khác…"), Hiện trong Finder, Chia sẻ ▸ · Copy ảnh, Copy đường dẫn · Phóng to, Thu nhỏ, Kích thước thật, Vừa cửa sổ, Xoay trái/phải (Phát/tạm dừng nếu là ảnh động) · Thông tin, Filmstrip, Gallery, Toàn màn hình (✓ khi đang bật), Theo kích thước ảnh (✓, chỉ ở chế độ cửa sổ) · Chuyển vào Thùng rác · Phím tắt | như bên |

Khoá trục cuộn theo 8pt đầu tiên của mỗi cử chỉ. Vuốt ngang trong pha quán tính bị bỏ qua.

## 6. Bàn phím

| Phím | Chức năng |
|---|---|
| ← → · Space, ⇧Space · PageUp, PageDown | Ảnh trước / sau (giữ để lướt nhanh) |
| Home / End | Ảnh đầu / cuối thư mục |
| + − (hoặc ⌘+ ⌘−) | Zoom to / nhỏ (bước ×1.25, quanh tâm). ↑ ↓ không zoom: chúng chỉ pan khi đang zoom (trước đây ↑ ↓ zoom khi ảnh vừa cửa sổ rồi lại pan khi đã zoom, dễ nhầm) |
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
| `?` · ⌘/ | Bảng phím tắt (mục 6.1) |

Không có phím `1`, `2`, `R`. Bảng phím nằm ở một nơi (`KeyBindings.swift`) và mọi lệnh cũng có trong menu chính. Tên lệnh và phím tắt hiển thị của menu chính và menu chuột phải lấy từ một bảng (`MenuCommand`); phím tắt hiện ở cột bên phải, không viết trong ngoặc ở tên. Phím không kèm ⌘/⌃/⌥ (`[` `]` `T` `G` Home End…) chỉ để hiển thị trong menu, phím thật vẫn do `KeyBindings` xử lý (để không cướp phím gõ-tìm trong Gallery).

### 6.1 Bảng phím tắt

Một chức năng thường có nhiều phím (Ảnh sau: → · Space · Page Down · ⌘→ · vuốt 2 ngón), mà menu macOS chỉ hiện được một phím mỗi mục. Bảng phím tắt liệt kê đủ:

- Mở bằng `?`, ⌘/ (menu Trợ giúp → Phím tắt), mục "Phím tắt" cuối menu chuột phải, hoặc nút "Xem phím tắt…" ở tab Điều khiển của Settings. Đóng bằng Esc, `?`, ⌘/ hoặc click ra ngoài.
- Panel kính lỏng (cùng nền và cài đặt Kính lỏng / Độ tối với các thanh, thêm lớp tối 40% cho dễ đọc), bo góc 20pt, nằm giữa cửa sổ xem ảnh và đi theo nó (cửa sổ con, cả khi fullscreen). Màn hình nhỏ thì cuộn được.
- Hai cột, theo nhóm: Chuyển ảnh · Zoom và di chuyển · Xoay và hiển thị · Ảnh động | Cửa sổ · Tệp · Gallery. Mỗi dòng: tên lệnh (lấy từ `MenuCommand`, giống menu) bên trái; bên phải là các phím dạng nút phím, rồi cử chỉ (chữ mờ, có biểu tượng bàn tay). Phím chỉ dùng được trong một tình huống có ghi chú nhỏ bên cạnh: "khi chưa zoom", "khi đang zoom", "ảnh tĩnh", "ảnh động"; cả dòng cùng một ghi chú thì ghi một lần dưới tên lệnh.
- Phím của chế độ xem ảnh không viết tay: bảng hỏi `KeyBindings` với từng phím và tổ hợp ⇧/⌘ ở ba tình huống (ảnh tĩnh chưa zoom, đang zoom, ảnh động), rồi thêm phím ⌘ của menu. Tổ hợp làm đúng như phím gốc (⇧→ = →) không được liệt kê. Đổi phím trong `KeyBindings` thì bảng tự đổi theo. Phần Gallery và cử chỉ (mục 5, 8) ghi tay.

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
- Ảnh hiện tại nằm **giữa** hàng, có vòng màu nhấn của hệ thống (accent) dày 2pt nằm ngoài ảnh 2,5pt (trên nền tối nên thấy rõ cả với ảnh trắng); hàng trượt mượt (120ms) khi chuyển ảnh; đầu và cuối thư mục thì hàng dừng ở mép.
- Tương tác: click thumbnail → nhảy tới ảnh đó; cuộn 2 ngón (ngang hoặc dọc) trên hàng → lướt hàng mà chưa đổi ảnh; rê chuột → tooltip tên file; chuột phải → chuyển tới ảnh đó rồi hiện cùng menu với ảnh.
- **Hiện/ẩn** (Settings → Filmstrip):
  - *Tự ẩn* (mặc định): hiện khi nhấn `T`, vuốt 2 ngón lên, hoặc đưa chuột xuống sát đáy màn hình; tự trượt xuống ẩn sau 2s chuột rời panel.
  - *Luôn hiện*: panel cố định; vùng khả dụng của cửa sổ chính trừ đi chiều cao panel.
  - `T` luôn bật/tắt trạng thái ghim.
- Khi filmstrip hiện, cửa sổ chính bị đẩy lên nếu đang chồng lên panel (không bao giờ che nhau).
- Fullscreen: filmstrip đang bật (`T`, vuốt lên, hoặc chế độ *Luôn hiện*) chiếm phần đáy màn hình, ảnh fit trong phần còn lại, không bị đè; status bar nằm ngay trên filmstrip. Lúc chỉ ló ra vì chuột chạm đáy màn hình (tự ẩn) thì vẫn phủ lên ảnh để ảnh không nhảy.
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

- **Cửa sổ tự phóng to:** vào Gallery, cửa sổ mở ra toàn bộ vùng khả dụng của màn hình (không phải fullscreen hệ thống); frame cũ được ghi nhớ. *Đã làm (M6):* cửa sổ đổi cỡ tức thì, còn chuyển động nằm ở nội dung (ảnh bay từ đúng vị trí cũ trên màn hình về ô của nó, các ô hiện dần) — animate khung cửa sổ cùng lúc với Metal làm hình bị co giãn trong lúc đổi cỡ. Chọn ảnh để thoát → cửa sổ thu về khung fit của ảnh được chọn, tâm tại tâm cũ. Đang fullscreen thì giữ fullscreen. Filmstrip ẩn trong lúc ở Gallery.
- **Bố cục:** chiều rộng cột mục tiêu theo Settings (mặc định 220pt, 120–480pt), khe 6pt, lề 12pt. `số cột = floor((W − 2·lề + khe) / (mục tiêu + khe))`; chiều rộng cột thực chia đều phần còn lại nên mọi ô **cùng chiều ngang**. Mỗi ảnh theo thứ tự thư mục vào **cột đang thấp nhất** (hoà thì cột trái hơn). Chiều cao ô = rộng cột × (cao/rộng của ảnh), kẹp trong [0.3, 3.0] × rộng cột; ảnh vượt giới hạn thì cắt giữa.
- **Khi kích thước ảnh chưa đọc xong:** thư mục ≤ 2.000 ảnh thì chờ đủ rồi mới hiện lưới (thường dưới 0,5s; quá 300ms thì hiện lưới giữ chỗ trước). Thư mục lớn hơn: phần đầu đã biết kích thước được xếp chính thức, phần còn lại là ô giữ chỗ tỉ lệ 3:2 màu xám, kèm vạch tiến độ mảnh ở thanh trên. Ô đã xếp chính thức **không bao giờ nhảy cột**; khi ô giữ chỗ được thay bằng ô thật, ô đang chọn được giữ đứng yên trên màn hình.
- Ô bo góc 4pt; ô đang chọn có vòng màu nhấn (accent) dày 2pt nằm ngoài ô 3pt; ô đang rê có viền xám mảnh. Thanh trên hiện đường dẫn thư mục, số ảnh, tên file của ô đang chọn/rê, và hai nút đổi cỡ ô (⊖ ⊕, biểu tượng tròn 15pt như các nút ở thanh tiêu đề).
- Thanh trên giống thanh tiêu đề cửa sổ xem ảnh (mục 2.2): cùng chiều cao, nền kính, chữ 13pt đậm canh giữa, nút bên phải; nút đèn giao thông luôn hiện trong Gallery; kéo để dời cửa sổ, nhấn đúp để phóng to cửa sổ.
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

Cửa sổ Settings kiểu chuẩn của macOS: `NSTabViewController` kiểu `.toolbar` (hàng biểu tượng trên thanh công cụ, `toolbarStyle = .preference`), mỗi tab là một SwiftUI `Form` kiểu grouped (các nhóm bo góc như System Settings), công tắc dạng switch. 5 tab (Chung, Hiển thị, Điều khiển, Định dạng, Hiệu năng), rộng 520pt; cửa sổ đổi chiều cao theo tab, giữ mép trên; tiêu đề cửa sổ là tên tab. Mọi thay đổi có hiệu lực ngay, không có nút Lưu. Chỉ gồm các tham số cần thiết:

```
┌───────────────────────────────────────────────────────┐
│  Chung   Hiển thị   Điều khiển   Định dạng   Hiệu năng │
├───────────────────────────────────────────────────────┤
│ Kích thước 100%          (•) Point   ( ) Pixel        │
│ Khi mở ảnh               [Vừa màn hình, tối đa 100% ▾]│
│ Nền                      [Ô caro ▾]                   │
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
| **Chung** | Ngôn ngữ | **Theo hệ thống** / từng ngôn ngữ ở mục 12 (tên viết bằng chính ngôn ngữ đó); có hiệu lực khi mở lại app |
| | Sắp xếp ảnh trong thư mục | **Tên (như Finder)** / Ngày sửa / Ngày chụp / Dung lượng; tăng/giảm |
| | Khi tới ảnh cuối | **Dừng lại** / Quay vòng về đầu |
| | Hỏi trước khi chuyển vào Thùng rác | **Bật** / Tắt |
| | Thoát app khi đóng cửa sổ | **Bật** / Tắt |
| **Hiển thị** | Kích thước 100% | **Point** / Pixel |
| | Khi mở ảnh | **Vừa màn hình, tối đa 100%** / Luôn vừa màn hình / Luôn 100% |
| | Nền | Đen / Xám đậm / Xám / Xám nhạt / Nửa trong suốt / **Ô caro** (chỉ hiện sau phần trong suốt của ảnh; ảnh không trong suốt vẫn trên nền đen). Trên nền Xám nhạt, dòng chữ giữa cửa sổ (gợi ý mở ảnh, lỗi) đổi sang chữ tối. Nửa trong suốt: các cửa sổ phía sau hiện qua một lớp làm mờ tối (`NSVisualEffectView` `.behindWindow`, `.hudWindow`); ở fullscreen không có gì phía sau cửa sổ (Space riêng) nên nền là đen |
| | Status bar | **Khi rê chuột** / Luôn hiện / Không bao giờ |
| | Click lên ảnh để ghim status bar | Bật / **Tắt** (chỉ dùng được khi Status bar = Khi rê chuột) |
| | Kính lỏng (thanh tiêu đề, status bar và các thanh nổi; chỉ macOS 26+, macOS 14–15 dùng kính mờ kiểu cũ) | Mờ / **Trong** — hai biến thể Liquid Glass của Apple (`NSGlassEffectView.Style` `.regular` / `.clear`); "kính mờ" là vật liệu cũ, không phải tên của biến thể regular |
| | Độ tối của các thanh đó | 0–80%, **35%** (lớp đen dưới nội dung thanh; áp dụng ngay cho mọi thanh đang mở) |
| | Hiệu ứng chuyển ảnh | **Trượt + mờ** / Chỉ mờ / Không |
| | Thời lượng hiệu ứng | 0–300ms, **160ms** |

Mọi thanh kéo có một vạch nhỏ dưới rãnh ở giá trị mặc định; kéo tới gần (trong 2% chiều dài) thì nút hít vào vạch.
| | Filmstrip | **Tự ẩn** / Luôn hiện |
| | Cỡ thumbnail filmstrip | Nhỏ / **Vừa** / Lớn |
| | Độ rộng cột Gallery | 120–480pt, **220pt** |
| | Đảo chiều vuốt chuyển ảnh | **Tắt** / Bật |
| | Bước zoom bằng phím | 1.1 / **1.25** / 1.5 / 2 |
| | Giữ mức zoom khi chuyển ảnh | **Tắt** (mỗi ảnh về fit) / Bật |
| **Hiệu năng** | Số ảnh nạp trước mỗi phía | 1 / **2** / 3 / 4 |
| | Bộ nhớ cho thumbnail | **Tự động** (1/16 RAM máy, 256 MB–2 GB; 16 GB RAM → 1 GB ≈ 20.000 ảnh) / 128 / 256 / 384 / 768 MB. Thiếu RAM thì tự giảm |
| | Bộ nhớ cho ảnh lớn (tile) | 256 / **512** / 1024 / 2048 MB |
| | RAW | **Dùng ảnh xem trước nhúng** / Luôn xử lý RAW đầy đủ |
| | Dòng ghi chú | "ViVuView không lưu thumbnail hay bộ nhớ đệm ra đĩa." |

Bảng phím tắt không chỉnh được trong đợt này; xem ở bảng phím tắt (mục 6.1, nút "Xem phím tắt…" ở tab Điều khiển).

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
  - **Ảnh thông dụng:** JPEG, PNG, HEIC/HEIF, GIF, WebP, AVIF, BMP, JPEG XL, SVG, ICO/ICNS.
  - **RAW máy ảnh:** Canon (CR2, CR3), Nikon (NEF), Sony (ARW), Fujifilm (RAF), Adobe DNG, Olympus/OM (ORF), Panasonic (RW2), Pentax (PEF); thêm một dòng "RAW khác" gộp các loại còn lại mà hệ thống đọc được.
  - **Chuyên dụng:** TIFF/BigTIFF, PSD/PSB, OpenEXR, JPEG 2000, TGA.
- Mỗi dòng: tên định dạng, dòng phụ chữ mờ gồm các đuôi file và tên app hiện đang là mặc định của loại đó (ghi "ViVuView" khi đã gắn), công tắc ở bên phải.
- **Trạng thái ô chọn phản ánh hệ thống**, không phải một giá trị lưu riêng: mỗi lần mở tab, app hỏi macOS xem trình mặc định của từng loại là gì. Nếu người dùng đổi trong Finder (Get Info → Open with) thì tab này hiển thị đúng theo.
- **Tích:** đặt ViVuView làm mặc định cho loại đó, có hiệu lực ngay. macOS có thể hiện hộp thoại xác nhận của hệ thống; nếu người dùng từ chối thì ô tự bỏ tích.
- **Bỏ tích:** trả về app đã là mặc định trước khi ViVuView nhận (app được ghi nhớ lúc tích); nếu không còn app đó thì trả về Preview.
- Nút "Chọn cả nhóm", "Chọn tất cả", "Bỏ chọn tất cả" áp dụng hàng loạt; khi đó chỉ hiện một dòng tổng kết lỗi (nếu có) thay vì từng thông báo.
- Mặc định khi mới cài: **không tích gì**. ViVuView không tự chiếm định dạng nào; file vẫn mở được bằng ViVuView qua "Open With", kéo-thả, ⌘O.
- Dòng ghi chú cuối tab: "Bạn cũng có thể đổi trong Finder: chọn file → Get Info → Open with → Change All."

## 11. Trạng thái đặc biệt

- **Chưa mở ảnh:** cửa sổ 480×320pt nền đen giữa màn hình, dòng chữ "Kéo ảnh vào đây, nhấn đúp hoặc ⌘O để mở". Nhấn đúp vào cửa sổ trống mở hộp chọn file (như ⌘O).
- **Đang nạp, chưa có hình nào:** giữ ảnh cũ; status bar ghi tên file mới + `đang nạp…`. Nếu quá 300ms: vòng tiến độ nhỏ ở giữa.
- **Ảnh khổng lồ đang dựng:** ảnh mờ hiện trước; vạch tiến độ 2pt ở mép dưới ảnh; vùng đang zoom nét dần từng mảng.
- **File lỗi / không hỗ trợ:** biểu tượng cảnh báo + tên file + lý do ngắn; vẫn chuyển ảnh bình thường.
- **Thư mục chỉ có 1 ảnh:** vuốt/phím chuyển ảnh làm ảnh nhún nhẹ rồi về chỗ cũ.
- **Hết thư mục** (khi không quay vòng): cùng hiệu ứng nhún.

## 12. Ngôn ngữ

- Có sẵn: English, Tiếng Việt, 简体中文, 繁體中文, 日本語, 한국어, Français, Deutsch, Español, Português (Brasil), Русский, Italiano.
- Mặc định macOS chọn theo danh sách ngôn ngữ ưa thích của người dùng; ngôn ngữ app không có thì dùng **tiếng Anh** (`CFBundleDevelopmentRegion = en`).
- Đổi riêng cho app: Settings → Chung → Ngôn ngữ (ghi `AppleLanguages` vào miền cài đặt của app, giống System Settings → Ngôn ngữ & Vùng → Ứng dụng), có hiệu lực khi mở lại app.
- Chuỗi nguồn trong mã là tiếng Việt; bản dịch nằm trong `Resources/Localizable.xcstrings`. Tên định dạng, đơn vị, phím tắt và tên menu Finder giữ theo cách Apple dịch trong từng ngôn ngữ.
