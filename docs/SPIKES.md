# M0.5 — Kết quả thử giả định

Máy: Apple Silicon 8 nhân, 16GB RAM, macOS 27.0.1, Swift 6.4.2. Ngày 2026-11-16.
Công cụ: `vivu-bench decode`, `vivu-bench huge`, `vivu-bench make-fixtures`, cộng vài chương trình đo nhỏ (không nằm trong repo).
File thử: thư mục 500 JPEG 4000×3000 tự sinh, JPEG 200MP, PSD 3000×2000, PSB RLE 40000×12000 (1,4GB), BigTIFF tile 36000×20000 có 5 overview (3GB), TIFF tile 36000×20000 không overview (2,2GB); ảnh thật của người dùng: 8 HEIC (8–17MP), JPEG 2560×1440, HEIC iPhone 12MP.

"Lần đầu" ở đây là lần đầu trong tiến trình; file vừa được ghi hoặc đọc gần đây nên có thể vẫn nằm trong page cache. Số "nguội" thật cần `sudo purge`, chưa đo.

## (a) Decode qua ImageIO

| File | Decode đầy đủ | API thumbnail, cạnh dài 3024 | Vẽ vào context P3 | Ghi chú |
|---|---|---|---|---|
| JPEG 12MP (4000×3000) | 29–39ms | 145–205ms | 38–46ms (12MP) | Xin cỡ không phải bậc ½ ¼ ⅛ thì ImageIO decode đủ rồi co lại → chậm gấp 5 lần |
| JPEG 3,7MP thật | 21–29ms | 32ms | 14ms | |
| HEIC 12MP iPhone | 84–90ms (+95–150ms lấy dữ liệu) | 73–88ms | 39–53ms | HEIC decode trễ: phần lớn chi phí rơi vào lúc lấy pixel |
| HEIC 15MP | 96–143ms (+100–120ms lấy dữ liệu) | 135ms | 39–57ms | Không gian màu CoreMedia709 |
| JPEG 200MP | 580–640ms (+0,5–1s lấy dữ liệu), RAM đỉnh 3,1GB | 1,1s (ra bậc ¼) | — | Thuộc tầng M |

Chuyển màu bằng `vImageConvert_AnyToAny` sang BGRA P3: 2–3ms cho JPEG 12MP, 6–11ms cho HEIC 12–15MP — nhanh hơn vẽ CGContext 10 lần.

**Kết luận, sửa TECH_SPEC 4.2:**
1. Giai đoạn 1 với JPEG: chỉ xin cỡ đúng bậc ½ ¼ ⅛; nếu bậc nhỏ nhất ≥ màn hình chính là ảnh gốc thì dùng `CGImageSourceCreateImageAtIndex` (decode đầy đủ) chứ không dùng API thumbnail. GPU co phần còn lại. Texture giai đoạn 1 vì thế có thể lớn tới 2× màn hình mỗi chiều.
2. Ảnh không phải JPEG mà cạnh dài ≤ 1,5× màn hình: decode đầy đủ; lớn hơn: API thumbnail.
3. Chuyển sang BGRA P3 bằng vImage từ dữ liệu của CGImage, không vẽ qua CGContext (trừ khi định dạng nguồn vImage không nhận).
4. HEIC là định dạng chậm nhất (~150–250ms cho ảnh 12–15MP). Mục tiêu "≤ 150ms sắc nét khi chưa preload" không đạt được với HEIC; với HEIC chỉ dựa vào preload. Ghi vào PLAN mục 6.

## (b) Ảnh xem trước nhúng

- **JPEG:** với `CreateThumbnailFromImageIfAbsent: false`, ImageIO **vẫn decode từ ảnh chính** khi file không có thumbnail nhúng (12MP mất 185ms, 200MP mất 5,2s). Không dùng được làm "giai đoạn 0 rẻ".
- **HEIC:** trả về "không có" cho cả ảnh iPhone, dù file có thumbnail riêng.
- **RAW:** máy này không có file RAW nào → **chưa kiểm chứng**. Giữ thiết kế (dùng preview nhúng qua API thumbnail), kiểm lại khi có file RAW thật.

**Kết luận:** giai đoạn 0 chỉ lấy từ `ThumbnailCache` (thumbnail đã tạo cho filmstrip/preload ±20 ảnh, ~20–40ms mỗi JPEG, ~100ms mỗi HEIC). Không gọi ImageIO cho giai đoạn 0 trên luồng của ảnh hiện tại.

## (c) Ảnh khổng lồ

| File | Cách đọc | Thời gian ra ảnh fit 3024 | RAM đỉnh |
|---|---|---|---|
| PSB RLE 480MP, 1,4GB | **Bộ đọc riêng** (`PSBRegionSource`, song song 8 nhân) | 950ms lần đầu, 750ms ấm | 43MB |
| | ImageIO | 2,4–3,0s | ~105MB |
| | Bộ đọc riêng, vùng 3024×2000 ở 100% | 39ms | |
| | Bộ đọc riêng, tile 512 ở level 2 | 15ms | |
| PSD RLE 6MP | Bộ đọc riêng / ImageIO | 22–40ms / 53–63ms | 27MB / ~110MB |
| BigTIFF tile 720MP có 5 overview, 3GB | ImageIO | 8,9–9,0s (bỏ qua overview, chỉ thấy 1 ảnh) | ~440MB |
| TIFF tile 720MP không overview, 2,2GB | ImageIO | 6,6–8,6s | ~440MB |

**Kết luận:**
- Bộ đọc PSB riêng đạt mục tiêu "≤ 1s có hình", **chưa đạt** "≤ 300ms khi ấm" (750ms). Tối ưu ở M8: bỏ bước xen kẽ kênh, cộng thẳng từ mặt phẳng kênh, xử lý theo dải nhiều hàng.
- ImageIO không dùng overview của TIFF và mất gần 9s → bộ đọc TIFF riêng (libtiff, đọc overview) ở M8 là cần thiết, đúng như thiết kế.
- Test: `PSBRegionSourceTests` (PackBits khứ hồi, PSD/PSB × raw/RLE, trung bình diện tích sai lệch ≤ 0,5, file cắt cụt ở 4 vị trí, bảng độ dài hàng sai, file không phải PSD) — đạt.

## (d) Hiệu ứng lớp phủ toàn màn hình và (e) panel filmstrip

**Chưa thử ở M0.5.** Hai bản thử này cần cửa sổ ảnh và renderer thật; làm sớm hơn thì phải viết lại phần lớn M1. Dời vào đúng mốc:
- (d) thử ở đầu M4, trước khi làm cử chỉ: đổi 2 ảnh 100 lần qua lớp phủ; nếu chớp → dùng phương án lùi (hiệu ứng trong khung cửa sổ).
- (e) thử ở đầu M5: vùng nóng đáy màn hình; nếu không ổn định → chỉ hiện bằng `T` / vuốt lên.
Phương án lùi trong PLAN mục 6 giữ nguyên. Phát hiện chớp hình cần mắt người: hai mục này nằm trong `docs/TEST_CHECKLIST.md`.

## (f) Vật liệu kính

SDK có `NSGlassEffectView` (macOS 26+): thuộc tính `contentView`, `cornerRadius`, `tintColor`, `style` (`.regular`, `.clear`); `effectIsInteractive` từ macOS 27. `OverlayBackground` dùng `NSGlassEffectView` style `.regular` trên macOS 26+, `NSVisualEffectView` material `.hudWindow` trên macOS 14–15. Đường macOS 14–15 **chưa kiểm chứng** trên máy thật.

## Việc phát sinh

- Bộ sinh dữ liệu thử nằm trong `vivu-bench make-fixtures` (thay cho `Scripts/make-fixtures.swift` dự kiến), dùng chung `PSBWriter`/`TIFFWriter` với test.
- `MemoryFootprint` tăng dần qua nhiều lần decode liên tiếp trong `vivu-bench decode` (266MB → 1,6GB). Có thể là bộ đệm của ImageIO/malloc chưa trả lại; kiểm tra bằng test rò rỉ ở M3.
