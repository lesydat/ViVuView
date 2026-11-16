# Danh sách thử tay

Những thứ không kiểm tự động được (TECH_SPEC mục 11.5). Mỗi lần thử ghi ngày và Đạt/Không; dòng "Không" kèm mô tả ngắn.
Chạy app: `Scripts/bundle.sh && open build/ViVuView.app --args <ảnh>` hoặc mở ảnh bằng Finder → Open With.

## M4 — Cử chỉ và hiệu ứng chuyển ảnh

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 4.1 | Vuốt 2 ngón sang trái chậm rồi thả khi chưa tới 30% | Ảnh cũ bám ngón tay, ảnh mới hé ra; thả thì bật về, không đổi ảnh | | |
| 4.2 | Vuốt 2 ngón sang trái quá 30% hoặc vuốt nhanh | Đổi sang ảnh sau, ảnh cũ trượt trái + mờ, ảnh mới trượt vào từ phải + rõ dần | | |
| 4.3 | Vuốt sang phải | Về ảnh trước, chiều ngược lại | | |
| 4.4 | Nhấn → một lần | Hiệu ứng 160ms, không chớp khung hình nào lúc bắt đầu và lúc kết thúc (nên quay màn hình để soi) | | |
| 4.5 | Giữ phím → | Lướt nhanh không hiệu ứng, không giật | | |
| 4.6 | Ở ảnh cuối, nhấn → hoặc vuốt tiếp | Ảnh nhún nhẹ rồi về chỗ cũ | | |
| 4.7 | Pinch zoom vào/ra | Zoom quanh vị trí ngón tay, cửa sổ lớn dần tới khi chạm mép màn hình | | |
| 4.8 | Pinch thu nhỏ quá mức vừa cửa sổ rồi thả | Ảnh trở về vừa cửa sổ (từ M6: mở Gallery) | | |
| 4.9 | Xoay 2 ngón | Ảnh xoay theo tay, thả ra bắt dính bội số 90° | | |
| 4.10 | Chạm đúp 2 ngón / double-click | Vừa cửa sổ ↔ 100% tại con trỏ | | |
| 4.11 | Đang zoom, vuốt 2 ngón | Pan ảnh, không đổi ảnh | | |
| 4.12 | Đang fullscreen, nhấn → và vuốt | Hiệu ứng chạy trong màn hình fullscreen | | |
| 4.13 | Hai màn hình: cửa sổ ở màn phụ, nhấn → | Hiệu ứng chạy trên đúng màn hình chứa cửa sổ | | |
| 4.14 | Bật "Giảm chuyển động" trong System Settings → Accessibility | Chỉ còn hiệu ứng mờ, không trượt | | |
| 4.15 | So cảm giác với LilyView (tốc độ, quãng trượt, ngưỡng thả) | Ghi lại chỗ khác để chỉnh `ViewerController+Transition.swift` | | |
