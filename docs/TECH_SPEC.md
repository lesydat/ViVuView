# ViVuView — Yêu cầu và thiết kế kỹ thuật

Xem [PLAN.md](PLAN.md) cho phạm vi và các mốc, [UI_SPEC.md](UI_SPEC.md) cho giao diện.

## 1. Dự án và công cụ

```
Package.swift                 swift-tools-version: 6.2 trở lên; mọi target Swift ở Swift 6 language mode
Sources/
  CTIFFShim/                  target C: bọc hàm variadic của libtiff (Swift không gọi được TIFFGetField/TIFFSetField)
    include/ctiffshim.h, shim.c
  ViVuCore/                   library, không import AppKit; toàn bộ có unit test
    Model/      ImageMeta.swift, PixelBuffer.swift, Geometry.swift, Viewport.swift, Tuning.swift
    Decode/     ImageIODecoder.swift, RegionSource.swift, RAMPyramidSource.swift,
                TIFFRegionSource.swift, PSBRegionSource.swift, FitDecode.swift, FileRead.swift,
                Stretch.swift, SourceFactory.swift, AnimatedDecoder.swift, ImageInfo.swift, Histogram.swift
    Folder/     FolderIndex.swift
    Schedule/   DecodeScheduler.swift, PreloadPlanner.swift, LatestWins.swift
    Cache/      ByteLRU.swift, ThumbnailCache.swift, FolderMeta.swift
    Layout/     MasonryLayout.swift, FilmstripLayout.swift
    Signposts.swift
  ViVuRender/                 library: Metal, không phụ thuộc cửa sổ; test được bằng cách vẽ ra texture ngoài màn hình
    Renderer.swift, Shaders.swift, Scene.swift (Quad), TextureFactory.swift,
    TileCache.swift, TileLayerRenderer.swift
  ViVuView/                   executable: AppKit (+ SwiftUI cho Settings và Info)
    main.swift, AppDelegate.swift, MainMenu.swift, Settings.swift, FileAssociations.swift
    Window/     ViewerWindow.swift, ViewerController.swift, TransitionOverlay.swift, MetalView.swift,
                ImageSlotCache.swift
    Input/      KeyBindings.swift, TrackpadController.swift
    Overlay/    OverlayBackground.swift, TitleBarOverlay.swift, StatusBar.swift, FilmstripPanel.swift,
                GalleryLayer.swift, InfoPanel.swift (SwiftUI), SettingsWindow.swift (SwiftUI)
    Debug/      ScriptRunner.swift (--script), BenchRunner.swift (--bench-navigate, --bench-open)
  ViVuBench/                  executable `vivu-bench`: đo riêng phần decode, không cần cửa sổ
Tests/ViVuCoreTests/          Swift Testing, fixture sinh bằng code
Tests/ViVuRenderTests/        test ảnh mẫu (vẽ ngoài màn hình, so pixel)
Scripts/bundle.sh, Scripts/build-libtiff.sh, Scripts/make-fixtures.swift
Vendor/                       kết quả build libtiff tĩnh (không commit)
docs/, CLAUDE.md
```

**Phiên bản và nền tảng:**
- Công cụ luôn dùng bản mới nhất đang có: Swift 6.4 (Xcode 27.2), Swift 6 language mode, Swift Testing (`import Testing`), Observation (`@Observable`). libtiff bản phát hành mới nhất, ghim phiên bản trong `Scripts/build-libtiff.sh`.
- **Deployment target macOS 14**; `Package.swift` khai `platforms: [.macOS(.v14)]`. Trình biên dịch sẽ báo lỗi nếu dùng API mới hơn mà không bọc `#available`.
- **Universal:** arm64 + x86_64.
- API chỉ có trên macOS mới hơn 14 chỉ được dùng ở **một chỗ**: `OverlayBackground` (nền của thanh tiêu đề, status bar, filmstrip, panel) — `if #available(macOS 26, *)` dùng vật liệu kính của hệ thống, ngược lại dùng `NSVisualEffectView` (material `.hudWindow`, luôn tối). Không rải `#available` ở nơi khác. API kính của macOS 26 phải tra tài liệu trước khi dùng, không đoán.
- Khoá: dùng `OSAllocatedUnfairLock` (có từ macOS 13). Không dùng `Synchronization.Mutex` (cần macOS 15).
- Không dùng API đã deprecated. Giới hạn kích thước texture và bộ nhớ GPU lấy từ `MTLDevice` lúc chạy (máy Intel có GPU khác nhau), không giả định hằng số.

**Quy ước concurrency (Swift 6):**
- Mọi thứ đụng UI là `@MainActor`.
- Decode chạy trên `OperationQueue` (mục 5.3). Dữ liệu qua lại giữa luồng là kiểu `Sendable`: `struct` giá trị, hoặc `final class` bất biến sau khi tạo. `PixelBuffer` là `final class … @unchecked Sendable`, chỉ ghi trong lúc tạo.
- Trạng thái chia sẻ có thể thay đổi (cache, pool handle) bọc trong `OSAllocatedUnfairLock<State>`. Không dùng actor cho đường nóng của decode.
- Lỗi strict concurrency tốn quá 3 lượt sửa thì dừng, ghi `docs/OPEN_ISSUES.md`; không dùng `@unchecked Sendable` ngoài `PixelBuffer` và lớp bọc handle C, không dùng `nonisolated(unsafe)`.
- Kết quả về main bằng `Task { @MainActor in … }`.

**Build:**
- Shader Metal là chuỗi MSL trong `Shaders.swift`, compile lúc chạy bằng `device.makeLibrary(source:options:)` (SwiftPM dòng lệnh không compile `.metal`).
- **libtiff build tĩnh** (`Scripts/build-libtiff.sh`, chạy một lần trước khi build app từ M8):
  - Tải mã nguồn theo phiên bản ghim trong script: libtiff, libjpeg-turbo (cho TIFF nén JPEG), zstd (cho TIFF nén ZSTD); kiểm tra SHA-256 của từng gói.
  - Build bằng CMake với `MACOSX_DEPLOYMENT_TARGET=14.0`, tắt công cụ dòng lệnh/tài liệu/test, chỉ thư viện tĩnh. Codec bật: LZW, PackBits, Deflate (zlib của hệ thống), JPEG, ZSTD.
  - **Build riêng từng kiến trúc** (arm64, x86_64) cho cả ba thư viện rồi ghép bằng `lipo -create`. Không build universal trong một lần CMake: libjpeg-turbo có mã SIMD riêng cho từng kiến trúc.
  - Kết quả vào `Vendor/lib/*.a` và `Vendor/include`; `Vendor/` nằm trong `.gitignore`.
  - `CTIFFShim` trỏ `Vendor/include`; liên kết tĩnh `libtiff.a`, `libjpeg.a`, `libzstd.a` và `-lz`.
  - App không mang dylib ngoài; không cần chép hay ký thư viện. Kiểm tra: `otool -L` trên file thực thi chỉ liệt kê thư viện hệ thống.
  - Homebrew chỉ cần cho `cmake` lúc build. Ghi chú bản quyền của ba thư viện đặt ở `Resources/Licenses/` và hiện trong mục Giấy phép của app.
- `Scripts/bundle.sh`: `swift build -c release --arch arm64 --arch x86_64` → `build/ViVuView.app/Contents/{MacOS,Resources,Info.plist}` → `codesign --force -s -` → kiểm tra `lipo -archs` đủ hai kiến trúc. `Info.plist` sinh từ `FormatCatalog` (mục 9.1), có `NSHighResolutionCapable`, `LSMinimumSystemVersion 14.0`. Bundle id tạm: `app.vivuview.ViVuView`.
- Chuỗi giao diện dùng String Catalog (`Localizable.xcstrings`), có tiếng Việt và tiếng Anh.
- Khởi động bằng `main.swift` + `AppDelegate`, không storyboard/xib. Nhận file qua `application(_:open:)`, tham số dòng lệnh, kéo-thả, ⌘O.

## 2. Mô hình dữ liệu

```swift
struct ImageMeta: Sendable {           // đọc từ header, không decode pixel
  var storedSize: PixelSize            // như lưu trong file
  var orientation: UInt8               // EXIF 1...8
  var orientedSize: PixelSize          // sau khi áp orientation; UI chỉ dùng cái này
  var frameCount: Int; var hasAlpha: Bool; var uti: String
  var fileSize: Int64; var mtime: Double
}

final class PixelBuffer: @unchecked Sendable {   // BGRA8 premultiplied, Display P3, bộ nhớ căn trang
  let width, height, bytesPerRow: Int; let data: UnsafeMutableRawPointer
}

struct Viewport: Sendable {
  var scale: Double        // device pixel trên 1 pixel ảnh
  var center: CGPoint      // điểm ảnh (oriented space) ở tâm view
  var quarterTurns: Int    // xoay do người dùng, 0...3
}
```

**Toạ độ** (nguồn lỗi kinh điển, phải nhất quán):
- *Oriented space*: pixel ảnh sau EXIF orientation, gốc trên-trái. UI, `Viewport`, layout dùng không gian này.
- *Stored space*: pixel như trong file. Chỉ `RegionSource` dùng. Renderer giữ ma trận `storedToOriented` cho mỗi ảnh.
- Ảnh decode qua API thumbnail của ImageIO với `kCGImageSourceCreateThumbnailWithTransform: true` đã ở oriented space; dữ liệu từ `RegionSource` ở stored space.
- `MetalView.isFlipped = true`; tính toán view theo device pixel, gốc trên-trái.

**Chế độ Point / Pixel:** `unitScale = backingScaleFactor` ở chế độ Point (mặc định), `= 1` ở chế độ Pixel. "100%" nghĩa là `viewport.scale == unitScale`; phần trăm hiển thị = `scale / unitScale × 100`. Quy tắc co cửa sổ theo ảnh, phím `0`, chạm đúp đều đi qua `unitScale`. Đổi tuỳ chọn có hiệu lực ngay; khi cửa sổ sang màn hình có hệ số khác thì tính lại.

**Màu:** mọi decode ra BGRA8 premultipliedFirst/byteOrder32Little trong colorspace Display P3; `CAMetalLayer.pixelFormat = .bgra8Unorm`, `colorspace = displayP3`, hệ thống tự khớp ra màn hình. HDR/EDR ngoài phạm vi.

## 3. Render (Metal)

- `MetalView: NSView`, `makeBackingLayer()` trả về `CAMetalLayer`; `layerContentsRedrawPolicy = .duringViewResize`; cập nhật `drawableSize` trong `setFrameSize` và `viewDidChangeBackingProperties`.
- **Vẽ theo yêu cầu:** `setNeedsRender()` gộp yêu cầu vào frame kế. Display link (`NSView.displayLink(target:selector:)`) chỉ chạy khi có animation, quán tính, ảnh động, hoặc dữ liệu đang về.
- Khi cửa sổ đổi kích thước (mỗi lần chuyển ảnh): bật `presentsWithTransaction`, vẽ đồng bộ (`commit` → `waitUntilScheduled` → `present`) trong cùng lượt đổi frame, rồi tắt lại. Tránh hình bị kéo giãn một frame.
- **Một pipeline** vẽ danh sách `Quad` mỗi frame (ảnh, tile, thumbnail, nền, viền chọn):

```swift
struct Quad {
  var texture: MTLTexture?          // nil = màu đặc
  var transform: simd_float4x4      // unit quad [0,1]² → clip space
  var uvRect: SIMD4<Float>
  var color: SIMD4<Float>           // nhân với texel (alpha dùng cho fade)
  var sizePx: SIMD2<Float>; var cornerRadius: Float      // bo góc bằng SDF trong fragment shader
  var borderWidth: Float; var borderColor: SIMD4<Float>
  var nearest: Bool                 // lọc nearest khi phóng ≥ 400%
}
```
  Mỗi quad: `setVertexBytes` + `setFragmentTexture` + `drawPrimitives(.triangleStrip, 4)`. Không cần atlas hay instancing.
- `Renderer` dùng chung một `MTLDevice` cho ba nơi vẽ: cửa sổ chính, `FilmstripPanel`, `TransitionOverlay`.
- Upload texture ngoài main thread (`MTLTexture.replace(region:…)`); main chỉ nhận texture đã sẵn sàng.
- Chữ, nút, status bar, panel là view AppKit/SwiftUI đặt chồng lên, không vẽ bằng Metal.

## 4. Pipeline nạp ảnh

### 4.1 Phân tầng

`SourceFactory` đọc `ImageMeta` rồi chọn đường đi. Ngưỡng nằm trong `Tuning.swift`.

| Tầng | Điều kiện | Cách hiển thị |
|---|---|---|
| **S** thường | ≤ 64MP và mỗi cạnh ≤ giới hạn texture của `MTLDevice` | 1 texture (≤ 256MB), 3 giai đoạn (4.2). Bao trọn ảnh máy ảnh phổ thông tới 61MP |
| **M** lớn, tuần tự | > 64MP, raw BGRA ≤ RAM/8 (≈500MP trên máy 16GB); JPEG/PNG/HEIC/WebP/AVIF… | Giai đoạn 1 như tầng S; decode đầy đủ 1 lần vào RAM thành `RAMPyramidSource`; hiển thị theo tile |
| **L-A** khổng lồ, truy cập ngẫu nhiên | TIFF > 64MP mà libtiff đọc được; PSD/PSB > 64MP loại 8-bit RGB, raw hoặc RLE | `TIFFRegionSource` / `PSBRegionSource`: chỉ đọc phần đang nhìn thấy (4.4) |
| **L-B** khổng lồ, tuần tự | Vượt ngưỡng tầng M và không thuộc L-A | Decode ImageIO với hệ số giảm mẫu f ∈ {2,4,8} nhỏ nhất vừa ngân sách RAM, thành `RAMPyramidSource`; status bar ghi "tối đa 1/f" |

Quy tắc rơi về: bộ đọc riêng từ chối (định dạng con không hỗ trợ) hoặc ném lỗi → đi đường ImageIO của tầng M/L-B. Từ chối không phải là lỗi.

### 4.2 Ba giai đoạn (tầng S; cũng là bước đầu của M và L-B)

- **Giai đoạn 0, bản xem trước (≤ 5ms):** lấy theo thứ tự (a) thumbnail trong `ThumbnailCache` (RAM), (b) thumbnail/preview nhúng trong file: `CGImageSourceCreateThumbnailAtIndex` với `FromImageIfAbsent: false`, `WithTransform: true`. Không có thì bỏ qua.
- **Giai đoạn 1, sắc nét cỡ màn hình:** `CGImageSourceCreateThumbnailAtIndex` với `FromImageAlways: true`, `ThumbnailMaxPixelSize` = cạnh dài vùng hiển thị tối đa tính bằng device pixel, `WithTransform: true`, `ShouldCacheImmediately: true`; vẽ vào `CGContext` P3 → `PixelBuffer` → texture. Kích thước yêu cầu làm tròn lên bậc ½, ¼, ⅛ của ảnh gốc khi là JPEG (decoder giảm mẫu ngay trong DCT; cỡ lẻ sẽ phải resample chậm). **RAW:** dùng `FromImageIfAbsent: true` để lấy JPEG preview nhúng.
- **Giai đoạn 2, đủ phân giải:** chỉ cho ảnh hiện tại, khi (a) zoom vượt độ phân giải giai đoạn 1, hoặc (b) dừng ở ảnh ≥ 250ms. `CGImageSourceCreateImageAtIndex` → vẽ vào context (áp orientation bằng CTM) → 1 texture. Giữ tối đa 2 texture giai đoạn 2. **RAW:** chỉ develop bằng `CIRAWFilter` khi zoom vượt preview nhúng.

Giai đoạn nào về thì thay texture ngay, không animation.

### 4.3 Hiển thị theo tile

```swift
protocol RegionSource: AnyObject, Sendable {
  var meta: ImageMeta { get }
  var maxLevel: Int { get }             // level k = ảnh thu nhỏ 2^k lần; level 0 = đầy đủ
  /// Đọc vùng `rect` (pixel level 0, stored space), trả về ảnh thu nhỏ 2^level lần bằng trung bình diện tích.
  /// Chặn, thread-safe.
  func read(rect: PixelRect, level: Int) throws -> PixelBuffer
}
```

Tile hiển thị 512×512 ở mỗi level là một lần gọi `read`.

**Chọn level:** `level = clamp(floor(log2(1 / scale)), 0, maxLevel)`: texel không bị thu nhỏ quá 2 lần nên lọc linear là đủ sắc.

**Vẽ mỗi frame** (`TileLayerRenderer`):
1. Vẽ lớp nền = texture fit (giai đoạn 1 hoặc kết quả fit-decode) phủ cả ảnh. Không bao giờ có lỗ đen.
2. Biến đổi ngược 4 góc view về stored space → vùng nhìn thấy → dải (col,row) ở level đích.
3. Vẽ đè các tile có trong `TileCache` giao với vùng nhìn thấy, từ level thô tới level đích.
4. Tile thiếu ở level đích: gửi yêu cầu, ưu tiên gần tâm view; sau đó prefetch 1 vòng tile bao quanh.
5. Mỗi lần viewport đổi thì tăng `generation`; tác vụ kiểm tra trước khi decode, tile không còn cần thì bỏ.

**`TileCache`:** khoá `(imageID, level, col, row)` → `MTLTexture`; LRU theo byte, mặc định 512MB (chỉnh trong Settings); xoá ngay khi rời ảnh. Số worker = `max(2, số nhân − 2)`.

**`RAMPyramidSource` (tầng M, L-B):** decode đầy đủ 1 lần vào `PixelBuffer` (trong lúc đó màn hình đã có giai đoạn 1), dựng level thô bằng `vImageScale` ÷2 tới khi nhỏ hơn cỡ fit. `read` là `memcpy`. Chỉ giữ cho ảnh hiện tại.

### 4.4 Ảnh khổng lồ truy cập ngẫu nhiên (tầng L-A)

Lý do cần bộ đọc riêng: theo số đo công khai của FeatherView, ImageIO mất 5–15 giây cho một lần fit-decode PSB 4.6GB hoặc TIFF lớn và chiếm tới ~8GB khi decode đầy đủ. Đọc thẳng từ file, chỉ phần cần, đưa con số này về dưới 1 giây và vài trăm MB. M0.5 sẽ đo lại trên máy này để xác nhận.

**Nguyên tắc chung**
- Đọc file bằng `pread` trên file descriptor (`FileRead.swift`), không nạp cả file, không cần khoá vì `pread` không dùng con trỏ file chung.
- **Fit-decode song song** (`FitDecode.swift`): chia ảnh đầu ra thành các dải hàng, `DispatchQueue.concurrentPerform` trên mọi nhân; mỗi dải tự đọc phần nguồn nó cần và tính **trung bình diện tích chính xác** (tổng số nguyên, mỗi pixel nguồn được tính đúng một lần). Không được lấy mẫu thưa (bỏ hàng/cột): ảnh thiên văn sẽ mất sao nằm giữa các hàng.
- **Level trung gian trên RAM:** sau khi ảnh fit đã hiện, một tác vụ nền chạy thêm một lượt fit-decode để dựng level mịn nhất còn ≤ 64MP (≤ 256MB); các level thô hơn suy ra từ nó bằng thu nhỏ trong RAM. Level mịn hơn nữa đọc trực tiếp từ file theo từng tile. Preload ảnh hàng xóm chờ tới khi ảnh khổng lồ hiện xong để không tranh nhân CPU.
- Mọi kết quả `read` đi qua kiểm tra `generation`; lỗi đọc một tile thì giữ nguyên lớp nền ở chỗ đó.

**`TIFFRegionSource` (libtiff)**
- Duyệt IFD: IFD chính là level 0; IFD có `NewSubfileType` bit 0, SubIFD (tag 330), và file phụ `<tên>.ovr` (overview của GDAL) là các level có sẵn, dùng thay cho việc tự tính khi kích thước khớp. Bỏ qua IFD mask (bit 2).
- Mỗi worker dùng một handle `TIFF*` riêng từ pool (handle không thread-safe).
- Tile/strip gốc của file được giải nén rồi ghép/cắt về vùng yêu cầu; cache nhỏ (64 mục) cho khối gốc đã giải nén.
- 8-bit: `TIFFReadRGBATile` / `TIFFReadRGBAStrip` (lo photometric, palette, YCbCr; kết quả gốc dưới-trái và thứ tự ABGR, phải lật và đổi kênh).
- 16-bit, float, 1 kênh, đa phổ: `TIFFReadEncodedTile/Strip` + chuẩn hoá về 8-bit bằng LUT kéo giãn tương phản percentile 2–98% tính trên ảnh fit (`Stretch.swift`); đa phổ lấy 3 kênh đầu, 1 kênh thành xám. Phím `E` bật/tắt.
- Có overview: mở chỉ đọc header + vài khối của level thô, tức thì bất kể dung lượng. Không có overview: fit-decode song song như trên.
- Strip quá lớn (một strip nén chứa cả ảnh) coi như không truy cập ngẫu nhiên → từ chối, rơi về ImageIO.

**`PSBRegionSource` (bộ đọc riêng, viết bằng Swift)**
- Chỉ nhận PSD/PSB 8-bit RGB có ảnh composite, nén raw hoặc RLE (PackBits), orientation 1. Mọi trường hợp khác từ chối.
- Phần ảnh composite lưu theo từng kênh, từng hàng. Với RLE, bảng độ dài từng hàng (2 byte mỗi hàng ở PSD, 4 byte ở PSB) được cộng dồn thành mảng offset → nhảy thẳng tới bất kỳ hàng nào của bất kỳ kênh nào. Với raw, offset tính trực tiếp.
- `read`: với mỗi hàng nguồn trong vùng, `pread` đúng số byte của hàng cho 3 kênh, giải PackBits, lấy đoạn cột cần, cộng vào bộ trung bình.
- Chuyển màu từ ICC nhúng sang P3 chạy theo dải trên mọi nhân.
- **Dữ liệu không tin cậy:** mọi offset, độ dài, kích thước đọc từ file phải kiểm tra biên (không âm, không vượt kích thước file, phép cộng/nhân không tràn) trước khi dùng; PackBits giải ra quá hoặc thiếu so với chiều rộng hàng là lỗi. File cắt cụt hoặc hỏng thì ném lỗi (→ rơi về ImageIO), không bao giờ crash hay đọc ngoài vùng nhớ. Có test với file cắt cụt, bảng độ dài hàng sai, kích thước khai báo vô lý.

**Giới hạn nói thẳng:** PNG/JPEG cực lớn không truy cập ngẫu nhiên được và ImageIO không có API đọc theo dòng, nên mỗi lần mở phải decode tuần tự cả file (có thể hàng chục giây, có vòng tiến độ), và vì không lưu cache ra đĩa nên lần sau vẫn vậy. JPEG2000 lớn, FITS, GDAL ngoài phạm vi; `RegionSource` cho phép thêm backend sau.

## 5. Chuyển ảnh cực nhanh

### 5.1 `FolderIndex`
- Hiển thị ảnh được mở trước; quét thư mục ở nền: `contentsOfDirectory(at:includingPropertiesForKeys:[.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles)`, lọc theo tập đuôi file, không đọc nội dung file. Sắp xếp theo Settings (mặc định tên, `localizedStandardCompare` như Finder).
- Phím next/prev bấm trước khi quét xong được giữ lại và áp dụng khi có index.
- Theo dõi thư mục bằng `DispatchSource` (vnode); giữ ảnh hiện tại theo URL.

### 5.2 `ImageSlotCache` + `PreloadPlanner`
Mỗi ảnh lân cận có `ImageSlot { url, meta?, stage0Tex?, stage1Tex?, stage2/regionSource?, operations }`.

Với vị trí `i`, hướng duyệt gần nhất `d` (±1), số ảnh preload mỗi phía `n` (Settings, mặc định 2), thứ tự ưu tiên giai đoạn 1:

`i` → `i+d` → `i+2d` → `i−d` → `i+3d` → `i−2d` (tổng quát: `n+1` ảnh phía trước, `n` ảnh phía sau)

- Slot ngoài tập bị huỷ tác vụ và giải phóng texture. Mỗi texture giai đoạn 1 ≤ cỡ màn hình (~24MB với màn 14"), 6 slot ≈ 150MB.
- Giai đoạn 0 nạp trước cho `i±20`, dùng chung với filmstrip.
- Ảnh tầng M/L khi preload chỉ làm ảnh fit, không dựng pyramid.

### 5.3 `DecodeScheduler`
Hai `OperationQueue`:
- `interactive`: QoS userInteractive, `maxConcurrent = 2`, chỉ cho ảnh hiện tại.
- `background`: QoS utility, `maxConcurrent = max(2, số nhân − 3)`, cho hàng xóm, thumbnail, dựng pyramid; `queuePriority` theo thứ tự ở 5.2.

Mỗi operation kiểm tra `isCancelled` trước decode và trước upload. Hàng xóm thành ảnh hiện tại mà tác vụ chưa chạy: huỷ ở `background`, tạo lại ở `interactive`. Việc chỉ cần kết quả mới nhất (tile, vùng zoom) đi qua `LatestWins`.

### 5.4 `ViewerController.go(to:)`
1. Cập nhật `i`, `d`; tăng `navGeneration`.
2. Chọn hình tốt nhất đang có của slot `i`: stage2 > stage1 > stage0 > không có (giữ hình cũ, status bar hiện tên file mới).
3. Chạy hiệu ứng chuyển ảnh (mục 6) hoặc đổi tức thì; cửa sổ nhận kích thước theo ảnh mới, vẽ đồng bộ.
4. `PreloadPlanner` tính lại tập mong muốn → huỷ/tạo operation.
5. Kết quả decode về sau gắn vào slot theo URL; chỉ vẽ lại nếu slot là ảnh hiện tại; slot đã bị loại thì bỏ.

**Giữ phím / vuốt dài:** mỗi bước chỉ làm 1–5, không chờ gì. Từ lần lặp phím thứ hai trở đi bỏ hiệu ứng (đổi tức thì). Ảnh lướt qua chưa có stage1 thì hiện stage0 và tác vụ bị huỷ ở bước kế; chỉ ảnh dừng lại mới decode stage1 trên `interactive`.

### 5.5 Khởi động
Bắt đầu decode ngay trong `application(_:open:)`, song song với tạo cửa sổ và Metal pipeline; cửa sổ chỉ `orderFront` khi đã có frame đầu. Mặc định app thoát khi đóng cửa sổ cuối.

## 6. Hiệu ứng chuyển ảnh (kỹ thuật)

Hành vi nhìn thấy mô tả ở UI_SPEC mục 4. Cách làm:
- `TransitionOverlay`: một `NSWindow` không viền, trong suốt, `ignoresMouseEvents = true`, phủ toàn bộ `frame` của màn hình hiện tại, nằm ngay trên cửa sổ chính, chứa một `MetalView` dùng chung `Renderer`.
- Bắt đầu: overlay vẽ ảnh cũ đúng vị trí cửa sổ đang đứng (1 frame), rồi cửa sổ chính đặt `alphaValue = 0`. Trong lúc chạy, overlay vẽ 2 quad: ảnh cũ trượt ra một phía và giảm alpha; ảnh mới (texture tốt nhất của slot đích) trượt vào từ phía kia và tăng alpha, kích thước nội suy về khung fit của nó.
- Kết thúc: cửa sổ chính nhận frame mới + vẽ đồng bộ ảnh mới, `alphaValue = 1`, overlay `orderOut`. Hai việc nằm trong cùng một `CATransaction` để không chớp.
- Tiến độ `t ∈ [0,1]` do ngón tay điều khiển (trackpad) hoặc do animation theo thời gian (phím, thả tay). Huỷ giữa chừng thì chạy ngược về 0.
- Ở fullscreen không cần overlay: vẽ 2 quad ngay trong view chính.
- Tắt hiệu ứng trong Settings → đổi tức thì.
- Đây là phần dễ chớp hình nhất (đổi giữa lớp phủ và cửa sổ, nhiều màn hình, Spaces), nên được thử ở M0.5. Nếu không khử được chớp: hiệu ứng chạy trong khung cửa sổ (2 quad trong view chính, cửa sổ đổi kích thước ở cuối), bỏ `TransitionOverlay`.

## 7. Thumbnail và metadata thư mục (chỉ RAM)

- `ThumbnailCache` có **2 tầng, đều trong RAM**; không ghi gì ra đĩa, hết phiên là mất:
  1. *Tầng nén:* dữ liệu JPEG q80 của thumbnail cạnh dài 640px (~40KB mỗi ảnh). LRU theo byte, mặc định 384MB (≈ 9.000 ảnh; chỉnh trong Settings). Nhờ tầng này cuộn qua lại thư mục vài nghìn ảnh không phải decode lại từ file gốc.
  2. *Tầng texture:* `MTLTexture` đã giải nén, chỉ cho các ô đang và sắp nhìn thấy; LRU cố định 128MB. Giải nén từ tầng nén ≈ 1ms mỗi ảnh, chạy ở hàng `background`.
- Tạo thumbnail: hiện thumbnail EXIF nhúng trước (≈1ms, mờ) → decode giảm mẫu 640px qua ImageIO → nén JPEG vào tầng 1 và đưa texture vào tầng 2. Ưu tiên ô đang nhìn thấy, huỷ khi cuộn ra ngoài. Với file tầng L-A dùng ảnh fit thu nhỏ. Ảnh có alpha giữ dạng PNG thay vì JPEG.
- `FolderMeta` (RAM): tên file → `orientedSize`. Masonry và filmstrip cần tỉ lệ của mọi ảnh, nên ngay sau khi quét thư mục, một tác vụ nền đọc header (không decode pixel) của mọi file. Làm lại mỗi lần mở thư mục.
  - Thứ tự đọc: đoạn quanh ảnh hiện tại trước (cho filmstrip), sau đó từ đầu thư mục theo đúng thứ tự.
  - `MasonryLayout` chỉ **chốt** vị trí cho đoạn đầu liên tục đã biết kích thước; phần sau đó là ô giữ chỗ. Ô đã chốt không bao giờ đổi cột khi dữ liệu về thêm.
  - Thư mục ≤ 2.000 ảnh: Gallery chờ đủ dữ liệu rồi mới hiện lưới (ước lượng dưới 0,5s trên ổ trong; nếu quá 300ms thì hiện lưới giữ chỗ trước).

## 8. Thông tin ảnh

- `ImageInfo`: gom từ `CGImageSourceCopyPropertiesAtIndex` (EXIF, TIFF, GPS, IPTC, DPI, profile màu) + thuộc tính file. Dùng cho status bar (bản rút gọn) và panel thông tin.
- `Histogram`: tính RGB + luma bằng `vImageHistogramCalculation` trên texture fit (không cần đủ phân giải), ở hàng `background`.
- Panel thông tin viết bằng SwiftUI trong `NSHostingView`; bản đồ dùng MapKit, chỉ tạo khi ảnh có GPS.

## 9. Settings

`Settings.swift`: một `@Observable @MainActor final class` đọc/ghi `UserDefaults`. Mọi thay đổi có hiệu lực ngay, không cần khởi động lại. Danh sách tham số ở UI_SPEC mục 10. Đây là thứ duy nhất app ghi ra đĩa.

### 9.1 Gắn định dạng file (`FileAssociations.swift`, lớp app)

- Bảng định dạng duy nhất `FormatCatalog` (trong `ViVuCore`): mỗi mục gồm tên hiển thị, nhóm, danh sách `UTType` identifier, đuôi file. Bảng này là nguồn cho cả tab Định dạng, tập đuôi file của `FolderIndex`, và `CFBundleDocumentTypes` (`bundle.sh` sinh `Info.plist` từ cùng bảng, để ba nơi không lệch nhau).
- `Info.plist` khai báo **mọi** loại trong bảng ở `CFBundleDocumentTypes` (role Viewer, `LSHandlerRank = Alternate`) để app luôn có mặt trong "Open With" mà không tự chiếm mặc định. Loại nào hệ thống chưa có UTI chuẩn thì khai thêm ở `UTImportedTypeDeclarations`.
- Đọc trạng thái: `NSWorkspace.shared.urlForApplication(toOpen: UTType)`; so với `Bundle.main.bundleURL`.
- Đặt mặc định: `NSWorkspace.shared.setDefaultApplication(at:toOpenContentType:)` (bản async). Hệ thống có thể hỏi người dùng xác nhận; lỗi hoặc bị từ chối thì đọc lại trạng thái và hiển thị đúng thực tế.
- Trước khi nhận một loại, ghi nhớ URL app mặc định cũ vào `UserDefaults` (`previousHandler.<uti>`); bỏ tích thì đặt lại app đó, không còn thì dùng Preview (`com.apple.Preview`).
- Việc gắn chỉ có nghĩa khi app chạy từ `.app` đã đóng gói ở vị trí ổn định; nếu đang chạy từ thư mục build thì tab hiện cảnh báo "Hãy chuyển ViVuView vào /Applications trước khi gắn định dạng".
- Phần chuyển đổi trạng thái (tính danh sách thao tác từ tập đang tích → tập mong muốn, chọn app trả về) là hàm thuần trong `ViVuCore`, có unit test; lời gọi `NSWorkspace` nằm sau một protocol để test bằng bản giả.

## 10. Bộ nhớ và độ bền

- `DispatchSource.makeMemoryPressureSource`: warning → `TileCache` và `ThumbnailCache` còn 50%, bỏ slot preload xa; critical → chỉ giữ ảnh hiện tại.
- File hỏng/không đọc được: ô báo lỗi với tên file, vẫn next/prev bình thường.
- File bị xoá/đổi tên khi đang xem: `FolderIndex` cập nhật, sang ảnh kế.
- Ổ mạng/ổ chậm: mọi I/O ở hàng nền.
- Ảnh động (`AnimatedDecoder`): decode từng khung theo yêu cầu, bộ đệm vòng 8 khung, phát bằng display link; không giải nén toàn bộ vào RAM.

## 11. Kiểm chứng

Bốn lớp kiểm, từ tự động tới thử tay. Kết quả tổng hợp vào bảng "Nghiệm thu cuối" ở PLAN mục 7.

### 11.1 Test tự động (`swift test`)

- **Logic (`ViVuCoreTests`):** natural sort; `PreloadPlanner` (theo i, d, n, biên thư mục); `Viewport` (zoom quanh điểm, kẹp pan, fit, Point/Pixel); chọn level và tập tile (kể cả xoay và orientation 1–8); `MasonryLayout` (cột bằng nhau, cột thấp nhất, ô đã chốt không đổi cột khi dữ liệu về thêm); `FilmstripLayout`; `FormatCatalog` và chuyển trạng thái gắn định dạng (với `NSWorkspace` giả).
- **Bộ đọc ảnh khổng lồ:** `PSBRegionSource`, `TIFFRegionSource` trên fixture sinh bằng code (raw/RLE, tile/strip, 8/16-bit, có/không overview) so từng pixel với ImageIO hoặc với trung bình diện tích tính trực tiếp; `FitDecode` sai lệch ≤ 0,5 mỗi kênh. **File hỏng:** cắt cụt ở nhiều vị trí, bảng độ dài hàng sai, kích thước khai báo vô lý → phải ném lỗi, không crash.
- **Hình vẽ (`ViVuRenderTests`):** `Renderer` vẽ ra texture ngoài màn hình rồi đọc pixel, so với ảnh tham chiếu (sai lệch ≤ 2/255):
  - orientation 1–8 × xoay 0–3; Point/Pixel; bo góc, viền, alpha.
  - Ghép tile: ảnh dựng từ tile ở từng level so với ảnh thu nhỏ trực tiếp — không hở, không lệch 1 pixel ở mép tile.
  - Test bỏ qua (skip, có ghi lý do) nếu máy không có `MTLDevice`.

### 11.2 Đo hiệu năng

- **Trong app thật (số dùng để so với PLAN mục 3):**
  - `--bench-navigate <thư mục>`: app mở cửa sổ, tự chuyển ảnh 500 lần ở 3 nhịp (từng ảnh có nghỉ, liên tục, nhịp lặp phím), đo từ lúc nhận sự kiện tới lúc drawable được trình chiếu (`MTLDrawable.addPresentedHandler`); in p50/p95/max và số frame rớt.
  - `--bench-open <file>`: thời gian từ `application(_:open:)` tới frame đầu và tới frame sắc nét.
- **Không cửa sổ (`vivu-bench`, để tách riêng phần decode):** `decode <file>`, `huge <file>` (fit-decode nguội/ấm, thời gian đọc vùng ở 100%).
- **Bộ nhớ:** mọi bench in `phys_footprint` đỉnh (`task_info`).
  - Rò rỉ: duyệt 5.000 ảnh 2 vòng; footprint cuối vòng 2 không cao hơn cuối vòng 1 quá 10%.
  - Ngân sách: file 4GB ở 100%, pan theo đường zíc-zắc khắp ảnh; đỉnh < 1,5GB.
- **Đứng yên:** mở một ảnh tĩnh, để 10s; CPU trung bình < 1%.
- `os_signpost` với các tên `Decode`, `Navigate`, `FitDecode`, `RegionDecode`, `ThumbFill` để xem trong Instruments.
- **Sổ hiệu năng `docs/BENCH.md`:** mỗi mốc ghi máy, bản build, số đo. Mốc sau chậm hơn mốc trước quá 20% ở cùng phép đo là lỗi phải sửa trước khi commit.

### 11.3 Kịch bản giao diện tự động (`--script <file>`)

- File kịch bản là danh sách lệnh, mỗi dòng một lệnh: `open`, `next`, `prev`, `zoom`, `fit`, `rotate`, `gallery`, `filmstrip`, `info`, `settings`, `wait`, `snapshot <tên>`.
- `snapshot` ghi nội dung cửa sổ ra PNG trong thư mục chỉ định. Dùng làm smoke test mỗi mốc và để xem lại hình thật, không chỉ dựa vào "build xanh".
- Kịch bản mẫu nằm trong `Tests/Scripts/`; mỗi mốc thêm kịch bản cho tính năng mới.

### 11.4 Kiểm tra trên dữ liệu thật

- **Fixture lớn** (`Scripts/make-fixtures.swift`, sinh ra ngoài repo): 5.000 JPEG; JPEG 200MP; BigTIFF tile 4GB có overview; BigTIFF 2GB không overview; TIFF 16-bit 1 kênh; PSB RLE 2GB; PNG 300MP. Thêm RAW/GIF/WebP/HEIC và ảnh vệ tinh/vũ trụ thật do người dùng cung cấp.
- **Độ đúng trên file thật:** với mỗi PSB/TIFF lớn, so ảnh fit của bộ đọc riêng với ảnh fit của ImageIO (sai lệch trung bình ≤ 1/255) và so 20 vùng ngẫu nhiên ở 100% với vùng tương ứng do ImageIO decode.
- **Không ghi đĩa:** chạy kịch bản 5.000 ảnh dưới `fs_usage` lọc theo tiến trình; không có thao tác ghi nào ngoài file `UserDefaults`.

### 11.5 Thử tay (`docs/TEST_CHECKLIST.md`)

Cho thứ không tự động được; mỗi dòng có ô đạt/không và ngày thử: từng cử chỉ trackpad; hiệu ứng chuyển ảnh (kèm quay màn hình để soi frame chớp); filmstrip với Dock ẩn/hiện, nhiều màn hình, fullscreen, Spaces; gắn/bỏ gắn định dạng trong Finder; từng tuỳ chọn trong Settings; tiếng Việt/tiếng Anh.

### 11.6 Kiểm tra bản phát hành

- `lipo -archs` ra `x86_64 arm64`; chạy lát Intel qua Rosetta: `arch -x86_64 build/ViVuView.app/Contents/MacOS/ViVuView <file>` cùng kịch bản smoke.
- `otool -L` chỉ có thư viện hệ thống; `codesign --verify --deep --strict`.
- Chạy `.app` sau khi chép sang thư mục khác, với `PATH` không có Homebrew.
- **Chưa kiểm chứng được ở đây:** macOS 14–15 thật và máy Intel thật. Ghi rõ trạng thái này trong bảng nghiệm thu cho tới khi người dùng thử.

Mỗi mốc: `swift build -c release && swift test && Scripts/bundle.sh && build/ViVuView.app/Contents/MacOS/ViVuView --script Tests/Scripts/smoke.txt`.

## 12. Tham khảo từ FeatherView

Nguồn: https://github.com/featherview/featherview (MIT). Chỉ lấy ý tưởng, không sao chép mã.

| Ý tưởng của FeatherView | Áp dụng ở ViVuView |
|---|---|
| ImageIO trước, bộ đọc riêng chỉ cho trường hợp ImageIO quá chậm; bộ đọc riêng lỗi thì rơi về ImageIO | Giữ nguyên (4.1) |
| Bộ đọc PSD/PSB riêng: `pread`, bảng offset từng hàng từ độ dài RLE | `PSBRegionSource` (4.4) |
| Fit-decode bằng trung bình diện tích chính xác, chạy song song theo dải; không lấy mẫu thưa | `FitDecode` (4.4) |
| Zoom chỉ decode phần trên màn hình; chỉ giữ kết quả mới nhất | Dùng tile 512 + `TileCache` thay cho một vùng duy nhất, để pan liên tục không phải decode lại vùng chồng lấn; `LatestWins` + `generation` |
| Kích thước decode làm tròn theo bậc ½, ¼, ⅛ của JPEG | 4.2 giai đoạn 1 |
| Cache ảnh giới hạn, prefetch 2 mỗi phía, hoãn prefetch khi đang nạp ảnh khổng lồ | 5.2, 4.4 |
| Bench không cửa sổ + signpost, ngân sách thời gian ghi trong tài liệu | `vivu-bench`, mục 11 |
| TIFF: tự viết LZW/Deflate | **Khác:** dùng libtiff để có BigTIFF, JPEG-in-TIFF, 16-bit, đa phổ, overview |
| Hiển thị bằng Core Animation, lưới bằng NSCollectionView | **Khác:** Metal cho ảnh, gallery và filmstrip, để kiểm soát hiệu ứng chuyển ảnh và cuộn với thư mục rất lớn |
