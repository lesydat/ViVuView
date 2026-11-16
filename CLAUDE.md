# ViVuView

Trình xem ảnh cực nhanh cho macOS (Swift + AppKit + Metal), phong cách LilyView, mở được ảnh khổng lồ vài GB.

## Đọc trước mỗi mốc

- `docs/PLAN.md`: quyết định đã chốt, các mốc M0–M10, quy tắc, nghiệm thu cuối.
- `docs/TECH_SPEC.md`: kiến trúc và thiết kế kỹ thuật.
- `docs/UI_SPEC.md`: giao diện, cử chỉ, phím tắt, Settings.

Ba tài liệu này là nguồn thiết kế duy nhất. Cần lệch khỏi tài liệu thì sửa tài liệu trong cùng commit và nêu lý do.

**Mốc hiện tại:** M1 xong. Tiếp theo: M2.

Dữ liệu thử: `swift run -c release vivu-bench make-fixtures <thư mục ngoài repo> [--huge]`.

## Lệnh

```bash
swift build                      # debug
swift test                       # Swift Testing: ViVuCoreTests, ViVuRenderTests
Scripts/bundle.sh                # build/ViVuView.app, universal arm64 + x86_64, ký ad-hoc
build/ViVuView.app/Contents/MacOS/ViVuView --script Tests/Scripts/smoke.txt          # smoke, ghi build/smoke/*.png
arch -x86_64 build/ViVuView.app/Contents/MacOS/ViVuView --script Tests/Scripts/smoke.txt  # lát Intel qua Rosetta
swift run vivu-bench <lệnh>      # đo decode không cần cửa sổ
```

Mỗi mốc phải qua: `swift build -c release`, `swift test`, `Scripts/bundle.sh`, smoke (cả arm64 và x86_64); xem lại ảnh snapshot; ghi số đo vào `docs/BENCH.md`.

## Cấu trúc

- `Sources/ViVuCore`: logic thuần, không import AppKit, có test.
- `Sources/ViVuRender`: Metal, không phụ thuộc cửa sổ, test bằng vẽ ngoài màn hình.
- `Sources/ViVuView`: lớp app AppKit mỏng (+ SwiftUI cho Settings, panel thông tin). `Debug/ScriptRunner.swift` xử lý `--script`.
- `Sources/ViVuBench`: `vivu-bench`.
- `Tests/Scripts`: kịch bản giao diện cho `--script`.

## Quy tắc (tóm tắt PLAN mục 5)

- macOS 14+, universal. API mới hơn macOS 14 chỉ dùng trong `OverlayBackground`. Khoá dùng `OSAllocatedUnfairLock`, không dùng `Synchronization.Mutex`.
- Swift 6 language mode. Lỗi concurrency tốn quá 3 lượt sửa thì ghi `docs/OPEN_ISSUES.md`; không rải `@unchecked Sendable` / `nonisolated(unsafe)`.
- Không decode, đọc file hay `stat` trên main thread.
- Hằng số chỉnh được ở `Tuning.swift`; tuỳ chọn người dùng ở `Settings.swift`.
- Chỉ cache trong RAM, không ghi cache ra đĩa. Không thêm thư viện ngoài ngoài libtiff (build tĩnh, M8).
- Bộ đọc riêng (TIFF/PSB) lỗi thì rơi về ImageIO, không crash.
- Mốc sau chậm hơn mốc trước quá 20% trong `docs/BENCH.md` là lỗi.
- Báo cáo trung thực: chưa kiểm được thì ghi "chưa kiểm chứng".
- Commit trên `develop`, mỗi mốc một commit; không push khi chưa được yêu cầu.
