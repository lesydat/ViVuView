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

## M5 — Filmstrip

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 5.1 | Nhấn T | Một hàng thumbnail hiện sát đáy màn hình (ngay trên Dock), rộng hết màn hình, ngoài cửa sổ ảnh; ảnh hiện tại ở giữa có viền trắng | | |
| 5.2 | Cửa sổ ảnh đang chồng lên vùng đáy, nhấn T | Cửa sổ được đẩy lên/thu lại, không bị filmstrip che | | |
| 5.3 | Chuyển ảnh khi filmstrip đang hiện | Dải trượt mượt để ảnh mới vào giữa | | |
| 5.4 | Click một thumbnail | Nhảy tới ảnh đó | | |
| 5.5 | Cuộn 2 ngón trên dải | Dải trượt, ảnh hiện tại không đổi | | |
| 5.6 | Rê chuột lên một thumbnail | Tooltip tên file | | |
| 5.7 | Chế độ Tự ẩn: đưa chuột xuống sát đáy màn hình (Dock hiện / Dock tự ẩn) | Filmstrip hiện; rời chuột 2s thì ẩn; không giành chỗ với Dock | | |
| 5.8 | Vuốt 2 ngón lên / xuống khi ảnh đang vừa cửa sổ | Hiện / ẩn filmstrip | | |
| 5.9 | Chuyển sang app khác | Filmstrip ẩn theo | | |
| 5.10 | Fullscreen + T | Filmstrip phủ lên đáy ảnh | | |
| 5.11 | Thư mục vài nghìn ảnh, cuộn nhanh dải | Mượt, ô xám rồi thumbnail hiện dần | | |
| 5.12 | Hai màn hình | Filmstrip ở đáy màn hình đang chứa cửa sổ ảnh | | |
