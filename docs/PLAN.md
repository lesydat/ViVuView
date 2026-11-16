# ViVuView — Kế hoạch thực hiện

Trình xem ảnh cực nhanh cho macOS, phong cách LilyView, tham khảo Pixea (status bar, panel thông tin, hàng thumbnail) và FeatherView (đọc ảnh khổng lồ).

Bộ tài liệu:
- `docs/PLAN.md` (file này): phạm vi, quyết định, các mốc, rủi ro, nghiệm thu cuối.
- [TECH_SPEC.md](TECH_SPEC.md): yêu cầu và thiết kế kỹ thuật.
- [UI_SPEC.md](UI_SPEC.md): yêu cầu giao diện, cử chỉ, phím tắt, cửa sổ cấu hình.

Trạng thái: **M0–M10 đã làm** (2026-11-16). Còn lại các mục "chưa kiểm chứng" ở mục 7, cần người dùng thử tay theo `docs/TEST_CHECKLIST.md`.

## 1. Mục tiêu

1. Mở ảnh gần như tức thì, kể cả file rất lớn (RAW, TIFF/PSD/PSB khổng lồ, ảnh vệ tinh/vũ trụ vài GB).
2. Chuyển ảnh kế tiếp/lùi cực nhanh, có hiệu ứng trượt + mờ kiểu LilyView.
3. Cửa sổ chỉ có ảnh; điều khiển bằng trackpad và bàn phím.
4. Status bar thông tin cơ bản khi rê/click chuột; panel thông tin chi tiết (phím I) kiểu Pixea.
5. Filmstrip: một hàng thumbnail sát đáy màn hình, nằm ngoài cửa sổ chính, rộng hết màn hình.
6. Gallery masonry (cột bằng nhau, cao theo tỉ lệ ảnh, xếp vào cột thấp nhất), cửa sổ tự phóng to.
7. Cửa sổ cấu hình gọn, chỉ các tham số cần thiết, có phần chọn định dạng file gắn với ứng dụng.

## 2. Quyết định đã chốt

| Hạng mục | Quyết định |
|---|---|
| Tên app | ViVuView |
| Ngôn ngữ | Swift 6.4, **Swift 6 language mode** (strict concurrency), Swift Testing |
| Nền tảng | AppKit + Metal cho phần xem ảnh; SwiftUI cho cửa sổ cấu hình và panel thông tin |
| macOS tối thiểu | **macOS 14** (build bằng SDK mới nhất đang cài: Xcode 27.2) |
| Kiến trúc | **Universal**: Apple Silicon (arm64) + Intel (x86_64) |
| Build | SwiftPM + `Scripts/bundle.sh` tạo `.app`, không dùng `.xcodeproj` |
| Phát hành | Không sandbox, ký ad-hoc |
| Thư viện ngoài | Chỉ libtiff (kèm libjpeg-turbo, zstd cho TIFF nén), **build tĩnh bằng script**, ghim phiên bản; app không mang dylib ngoài. Mọi thứ khác dùng framework của Apple |
| Bộ nhớ đệm | **Chỉ trên RAM.** Không ghi thumbnail hay bất kỳ cache ảnh nào ra đĩa |
| Chế độ render | Mặc định **Point** (100% = 1 pixel ảnh : 1 point); có tuỳ chọn **Pixel** |
| Gallery | Masonry, xếp vào cột thấp nhất |
| Filmstrip | Panel riêng sát đáy màn hình, ngoài cửa sổ chính |
| Phím | `0` = 100%, `\` = Fit, `[` xoay trái, `]` xoay phải; không có phím `1`, `2` |
| Ngôn ngữ giao diện | Tiếng Việt và tiếng Anh (String Catalog), theo ngôn ngữ hệ thống |

## 3. Mục tiêu hiệu năng

Đây là mục tiêu thiết kế cho **Apple Silicon**, chưa phải số đã đo. Số tham chiếu công khai của FeatherView: ~20ms sang ảnh kế (JPEG 12MP đã prefetch), ảnh PSB 4.6GB hiện sau ~1 giây. Trên Intel không cam kết con số (không có máy để đo).

| Tình huống | Mục tiêu | Đo bằng |
|---|---|---|
| Next/prev, ảnh đã preload | ≤ 16ms từ sự kiện tới khi frame được trình chiếu | `--bench-navigate` |
| Next/prev, chưa preload | ≤ 50ms có bản xem trước, ≤ 150ms sắc nét (JPEG; HEIC ~150–250ms vì decoder hệ thống chậm, chỉ dựa vào preload) | `--bench-navigate` |
| Giữ phím ←/→ | Không rớt frame, không dồn hàng đợi | `--bench-navigate` |
| Mở JPEG 24–60MP (app đã chạy) | ≤ 80ms sắc nét cỡ màn hình | `--bench-open` |
| TIFF/PSB vài GB | ≤ 1s có hình (≤ 300ms khi file đã trong page cache hoặc TIFF có overview) | `--bench-open`, `vivu-bench huge` |
| Zoom/pan ảnh khổng lồ | 60–120fps; vùng mới sắc nét ≤ 150ms sau khi dừng | signpost `RegionDecode` |
| RAM khi xem file 4GB ở 100% | < 1,5GB | `phys_footprint` đỉnh |
| App đứng yên với ảnh tĩnh | CPU < 1% | đo 10s |

## 4. Các mốc

Mỗi mốc là một commit chạy được trên nhánh `develop`; build, test và kịch bản smoke (`--script`) phải đạt trước khi commit; kết quả bench ghi vào `docs/BENCH.md`. Làm đúng thứ tự, không gộp mốc.

| Mốc | Nội dung | Nghiệm thu |
|---|---|---|
| **M0** Khung | `Package.swift`, `Scripts/bundle.sh`, `CLAUDE.md`, app rỗng mở cửa sổ đen, target test, `vivu-bench`, cờ `--script` | `.app` chạy; `swift test` chạy; `lipo -archs` ra `x86_64 arm64` |
| **M0.5** Thử giả định | Ghi `docs/SPIKES.md`: (a) thời gian decode giảm mẫu ImageIO cho JPEG/HEIC/PNG/RAW; (b) preview nhúng của RAW đủ lớn không; (c) **bản thử fit-decode song song** cho 1 PSB RLE và 1 BigTIFF thật trong `vivu-bench`, so thời gian + RAM với ImageIO; (d) **bản thử hiệu ứng lớp phủ toàn màn hình**: đổi 2 ảnh màu đặc 100 lần, không có frame chớp; (e) **bản thử panel filmstrip**: vùng nóng đáy màn hình với Dock ẩn/hiện, nhiều màn hình; (f) `OverlayBackground` kính trên macOS mới và đường dự phòng | Có số liệu và kết luận cho từng mục; giả định nào sai thì sửa TECH_SPEC/UI_SPEC (dùng phương án lùi ghi ở mục 6) trước khi làm M1 |
| **M1** Hiển thị | `ViVuRender` (`Renderer`, Quad) + test vẽ ngoài màn hình, `MetalView`, `ImageIODecoder` 3 giai đoạn, cửa sổ co theo ảnh, mở file (⌘O, kéo-thả, Open With, dòng lệnh), Point/Pixel | Test ảnh mẫu orientation 1–8 đạt; JPEG/PNG/HEIC/RAW đúng màu; lát x86_64 chạy được qua Rosetta |
| **M2** Xem | `Viewport`, zoom/pan/xoay bằng phím và chuột, fullscreen, thanh tiêu đề hover, status bar | Test Viewport; zoom quanh con trỏ không trôi; status bar đúng dữ liệu; CPU < 1% khi đứng yên |
| **M3** Chuyển ảnh | `FolderIndex`, `ImageSlotCache`, `PreloadPlanner`, `DecodeScheduler`, `--bench-navigate`, `--bench-open` | Đạt mục tiêu next/prev; giữ phím không dồn hàng; test rò rỉ bộ nhớ đạt |
| **M4** Trackpad + hiệu ứng | `TrackpadController`, hiệu ứng trượt + mờ (theo ngón tay và theo phím) | Người dùng thử theo `docs/TEST_CHECKLIST.md`, phản hồi, chỉnh `Tuning.swift` |
| **M5** Filmstrip | `ThumbnailCache` 2 tầng (RAM), `FilmstripPanel` sát đáy màn hình | Thư mục 5.000 ảnh cuộn mượt; `fs_usage` xác nhận không ghi đĩa |
| **M6** Gallery | `MasonryLayout`, Gallery, chuyển cảnh, cửa sổ tự phóng to | Test layout; vào/ra gallery đúng ô; lưới không nhảy cột khi dữ liệu về |
| **M7** Ảnh lớn (RAM) | `RegionSource`, `TileCache`, `TileLayerRenderer`, `RAMPyramidSource` | Test ghép tile không hở/lệch; JPEG 200MP zoom 100% mượt, RAM trong ngân sách |
| **M8** Ảnh khổng lồ | `Scripts/build-libtiff.sh`, `CTIFFShim`, `TIFFRegionSource`, `PSBRegionSource`, `FitDecode`, kéo giãn 16-bit | Đạt mục tiêu mục 3; so pixel với ImageIO trên file thật; file hỏng/cắt cụt không crash; `otool -L` chỉ có thư viện hệ thống |
| **M9** Thông tin + cấu hình | Panel thông tin (I) kiểu Pixea, cửa sổ Settings, tab Định dạng (gắn loại file với app) | Mọi tuỳ chọn có hiệu lực ngay, lưu qua lần chạy sau; tích/bỏ tích một định dạng thì double-click trong Finder mở đúng app |
| **M10** Hoàn thiện | Ảnh động, develop RAW khi zoom, memory pressure, xử lý lỗi file, bản dịch vi/en, kiểm tra bản phát hành | Bảng nghiệm thu cuối (mục 7) có kết quả ở mọi dòng |

## 5. Quy tắc cho người/model thực hiện

Tài liệu được viết để một model nhỏ hơn (Opus 5.5) thực hiện từng mốc mà không phải tự quyết định kiến trúc.

- Đọc `TECH_SPEC.md` và `UI_SPEC.md` trước mỗi mốc; nếu cần lệch khỏi tài liệu thì sửa tài liệu trong cùng commit và nêu lý do.
- Không decode, không đọc file, không `stat` trên main thread.
- Mọi hằng số chỉnh được nằm trong `Tuning.swift`; mọi tuỳ chọn người dùng nằm trong `Settings.swift`.
- Không thêm thư viện ngoài nào khác. Không ghi cache ra đĩa.
- Bộ đọc riêng (TIFF/PSB) thất bại thì rơi về ImageIO: lỗi của bộ đọc chỉ được làm chậm, không được làm mất hình hay crash.
- Logic thuần nằm trong `ViVuCore`, phần vẽ trong `ViVuRender`, đều có test; lớp app mỏng.
- Lỗi strict concurrency: nếu một lỗi tốn quá 3 lượt sửa, dừng và ghi vào `docs/OPEN_ISSUES.md`; không rải `@unchecked Sendable` hay `nonisolated(unsafe)` để cho qua.
- Mốc sau chậm hơn mốc trước quá 20% ở cùng phép đo trong `docs/BENCH.md` là lỗi phải sửa trước khi commit.
- Báo cáo trung thực: thứ gì chưa kiểm được thì ghi "chưa kiểm chứng", không ghi "đạt".
- Không sao chép mã nguồn FeatherView; chỉ tham khảo ý tưởng (TECH_SPEC mục 12).

## 6. Rủi ro và giới hạn

**Rủi ro được thử sớm ở M0.5 (kèm phương án lùi)**

| Rủi ro | Phương án lùi nếu bản thử không đạt |
|---|---|
| Fit-decode ảnh khổng lồ không đạt < 1s | Xem lại thiết kế TECH_SPEC 4.4 (kích thước dải, số luồng, cách đọc) trước khi làm tiếp |
| Hiệu ứng lớp phủ toàn màn hình bị chớp khi đổi giữa lớp phủ và cửa sổ | Hiệu ứng chạy trong khung cửa sổ |
| Vùng nóng đáy màn hình của filmstrip đụng Dock / Spaces / nhiều màn hình | Filmstrip chỉ hiện bằng `T` hoặc vuốt lên, không có vùng nóng |

**Rủi ro còn lại**
- Cảm giác cử chỉ và hiệu ứng LilyView dựa trên mô tả; cần người dùng thử ở M4.
- Swift 6 strict concurrency + Metal + C interop là gánh nặng lớn nhất cho model nhỏ; TECH_SPEC mục 1 quy định sẵn mẫu đồng bộ.
- Cần `brew install cmake` để chạy `build-libtiff.sh`.
- Kết quả M8 (docs/BENCH.md): TIFF/PSB vài GB không có overview mở dưới 1s nhưng **chưa đạt** mục tiêu "≤ 300ms khi file đã trong page cache" (0,66–0,77s, giới hạn bởi việc đọc lại toàn bộ file); TIFF có overview đạt (21–58ms).
- Kết quả M0.5 (docs/SPIKES.md): bộ đọc PSB riêng đạt < 1s nhưng chưa đạt mục tiêu ấm 300ms; HEIC decode chậm; hai bản thử (d) hiệu ứng toàn màn hình và (e) vùng nóng filmstrip dời sang đầu M4 và M5.

**Giới hạn chấp nhận**
- **macOS 14–15 và máy Intel chưa kiểm chứng được trên máy phát triển** (macOS 27, Apple Silicon). Chỉ đảm bảo: biên dịch với kiểm tra availability, và lát x86_64 chạy qua Rosetta. Hành vi thật cần người dùng thử trên máy hoặc máy ảo tương ứng.
- Ảnh tầng M (64MP tới khoảng 500MP) dựng pyramid qua ImageIO: RAM đỉnh khoảng 2,5 lần kích thước pyramid trong lúc dựng (200MP: 3,1GB, docs/BENCH.md M7), vì ImageIO giữ bản decode của nó song song với bản của app.
- PNG/JPEG cực lớn (gigapixel) không truy cập ngẫu nhiên được: mỗi lần mở phải decode tuần tự (có thể hàng chục giây), có thể bị giới hạn độ phân giải theo RAM; vì không cache đĩa nên lần sau vẫn vậy.
- Thư mục vài chục nghìn ảnh trên ổ mạng: bước đọc kích thước ảnh cho Gallery sẽ chậm, làm lại mỗi lần mở.
- Một cửa sổ duy nhất. Màu 8-bit Display P3: không HDR; ảnh 16-bit kéo giãn mạnh có thể thấy dải màu.
- Vuốt 2 ngón bám theo tay chỉ chuyển 1 ảnh mỗi lần vuốt; lướt nhiều ảnh dùng giữ phím hoặc filmstrip.

## 7. Nghiệm thu cuối

App chỉ được coi là xong khi mọi dòng dưới đây có kết quả. Dòng chưa kiểm được ghi "chưa kiểm chứng" kèm lý do, không bỏ trống. Chi tiết từng cách kiểm ở TECH_SPEC mục 11.

| Yêu cầu | Cách kiểm | Kết quả (2026-11-16, Apple Silicon, macOS 27) |
|---|---|---|
| Mở ảnh thường nhanh | `--bench-open` | **Đạt**: JPEG 12MP hiện sau 215ms tính từ lúc khởi động tiến trình (gồm cả khởi động app) |
| Chuyển ảnh cực nhanh, giữ phím mượt | `--bench-navigate` | **Đạt**: đã preload p50 3,0ms / p95 9,5ms / max 16ms; giữ phím 30Hz 120/120 ảnh hiện, max 8,1ms; liên tục chưa preload p50 14ms / p95 58ms. HEIC chưa preload chậm hơn (~150–250ms, decoder hệ thống) |
| Hiệu ứng chuyển ảnh kiểu LilyView | Ảnh chụp giữa hiệu ứng + thử tay | Hình giữa hiệu ứng đúng (ảnh cũ trượt trái mờ dần, ảnh mới vào từ phải). Chớp hình và cảm giác: **chưa kiểm chứng**, cần thử tay (checklist 4.4, 4.15) |
| File vài GB (TIFF, PSB) mở nhanh, zoom mượt | `--bench-open`, `--bench-zoom`, `vivu-bench huge`, test so ImageIO | **Đạt phần chính**: BigTIFF 3GB có overview 225ms; TIFF 2,2GB không overview 0,97s; PSB 1,4GB 0,95s; tile sau pan 50–124ms. **Chưa đạt** mục tiêu ấm 300ms cho file không overview (0,66–0,77s) |
| RAM trong ngân sách, không rò rỉ | `phys_footprint`, 2 vòng duyệt | **Đạt**: file khổng lồ đỉnh ≤ 1,04GB; vòng 1 → vòng 2: 852 → 851MB. Ngoại lệ đã ghi: JPEG 200MP (tầng M qua ImageIO) đỉnh 3,1GB |
| Không tốn CPU khi đứng yên | `--bench-idle` | **Đạt**: 0,04% (ảnh tĩnh); ảnh động đang phát 1,7% |
| Hình vẽ đúng (màu, orientation, tile) | Test `ViVuRender`, `DecodeTests` | **Đạt**: 8 orientation khớp ImageIO; ghép tile khớp một texture ở 4 mức zoom/xoay; chưa so màu bằng thiết bị đo |
| Cử chỉ trackpad | Thử tay | **Chưa kiểm chứng** (checklist mục M4) |
| Phím tắt đúng UI_SPEC mục 6 | Kịch bản `m2`–`m10` + thử tay | **Đạt** với các phím có trong kịch bản; phần còn lại theo checklist |
| Status bar, thanh tiêu đề hover | Kịch bản `m2` (ảnh chụp) | **Đạt** (ảnh chụp); vật liệu kính chỉ thấy khi thử tay |
| Panel thông tin (I) | Kịch bản `m9` (ảnh chụp) | **Đạt** (ảnh chụp); bản đồ GPS **chưa kiểm chứng** (không có ảnh thử có GPS) |
| Filmstrip sát đáy màn hình, ngoài cửa sổ | Kịch bản `m5` + thử tay | Vẽ đúng (ảnh chụp). Vị trí với Dock / nhiều màn hình / vùng nóng: **chưa kiểm chứng** (checklist M5) |
| Gallery masonry, cửa sổ tự phóng to | Test layout + kịch bản `m6` | **Đạt** |
| Point/Pixel | Test Viewport + kịch bản | **Đạt** (test); thử tay trên màn Retina theo checklist |
| Cửa sổ cấu hình, mọi tuỳ chọn có hiệu lực | Kịch bản `m9` + thử tay | Giao diện đạt (ảnh chụp); từng tuỳ chọn: một phần qua kịch bản (`setting …`), còn lại **chưa kiểm chứng** |
| Gắn định dạng file | Test logic + thử tay | Logic đạt test; thao tác thật trong Finder **chưa kiểm chứng** (cần chạy app từ /Applications, sẽ đổi app mặc định thật) |
| Chỉ dùng RAM, không ghi đĩa | Duyệt 500 ảnh + gallery, tìm file mới | **Đạt**: chỉ có file cấu hình UserDefaults. `fs_usage` cần quyền sudo nên không chạy được |
| Universal | `lipo -archs`; lát x86_64 qua Rosetta | **Đạt**: `x86_64 arm64`; mọi kịch bản chạy qua Rosetta |
| Không phụ thuộc Homebrew khi chạy | `otool -L`; chạy bản chép ở thư mục khác, PATH sạch | **Đạt** |
| Chạy trên macOS 14–15 | Máy/máy ảo của người dùng | **Chưa kiểm chứng** |
| Chạy trên máy Intel thật | Máy của người dùng | **Chưa kiểm chứng** (chỉ Rosetta) |
| File hỏng không làm crash | Test file cắt cụt/sai bảng (PSB, TIFF) + kịch bản smoke | **Đạt** |
| Ảnh động | Test + kịch bản `m10` | **Đạt** (GIF); WebP/APNG/AVIF/HEICS dùng cùng đường, chưa có file thử |
| RAW | — | **Chưa kiểm chứng**: máy phát triển không có file RAW |
| Tiếng Việt / tiếng Anh | Chạy với `-AppleLanguages` | **Đạt** |
