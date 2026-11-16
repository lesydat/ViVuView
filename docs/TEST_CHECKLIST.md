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

## M6 — Gallery

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 6.1 | Nhấn G (hoặc Enter, hoặc pinch thu nhỏ quá mức vừa cửa sổ rồi thả) | Cửa sổ mở ra toàn vùng màn hình, ảnh đang xem bay về đúng ô của nó, các ô khác hiện dần | | |
| 6.2 | Nhìn bố cục | Mọi cột cùng rộng, ô cao theo tỉ lệ ảnh, đáy các cột gần đều nhau | | |
| 6.3 | Cuộn 2 ngón / lăn chuột | Cuộn mượt, thumbnail hiện dần, không nhảy ô | | |
| 6.4 | ← → ↑ ↓, PageUp/PageDown, Home/End | Viền trắng di chuyển đúng; ↑↓ theo cột | | |
| 6.5 | Gõ vài chữ đầu của tên file | Nhảy tới file đó | | |
| 6.6 | Pinch hoặc ⌘+ / ⌘− hoặc nút −/+ | Cỡ cột đổi (120–480pt), ô đang chọn đứng yên | | |
| 6.7 | Click một ô / Enter | Ô phóng to thành chế độ xem, cửa sổ thu về cỡ ảnh | | |
| 6.8 | Esc hoặc G | Về lại ảnh lúc mở gallery | | |
| 6.9 | Thư mục vài nghìn ảnh mới mở | Lưới hiện ngay; phần chưa biết cỡ là ô xám 3:2 rồi thành ô thật, ô đã xếp không đổi cột | | |
| 6.10 | Gallery khi đang fullscreen | Giữ fullscreen, vào/ra có animation | | |

## M7 — Ảnh lớn

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 7.1 | Mở ảnh 100–300MP, chờ 1–3s, nhấn 0 | Ảnh hiện ngay bản mờ, sau đó 100% sắc nét; status bar ghi "đang nạp chi tiết…" trong lúc dựng | | |
| 7.2 | Kéo/vuốt pan nhanh khắp ảnh ở 100% | Không có ô đen; vùng mới nét lại trong khoảng 0,1s; không thấy đường nối giữa các tile | | |
| 7.3 | Zoom 400%+ | Hiện từng pixel vuông (nearest) | | |
| 7.4 | Ảnh HEIC/PNG 15–60MP, nhấn 0 | Sau tối đa ~0,5s ảnh nét hẳn | | |
| 7.5 | Activity Monitor khi xem ảnh 200MP | Bộ nhớ quanh 3GB lúc dựng, không tăng mãi khi pan | | |

## M8 — Ảnh khổng lồ (TIFF/PSB)

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 8.1 | Mở ảnh vệ tinh/vũ trụ GeoTIFF/BigTIFF thật vài GB có overview | Có hình dưới 0,3s | | |
| 8.2 | Mở TIFF/PSB vài GB không có overview | Có hình khoảng 1s; zoom 100% và pan mượt | | |
| 8.3 | TIFF 16-bit / float (ảnh thiên văn) | Hiện rõ (kéo giãn); nhấn E chuyển tuyến tính ↔ kéo giãn, status bar ghi trạng thái | | |
| 8.4 | GeoTIFF nén JPEG (YCbCr) | Màu đúng | | |
| 8.5 | File TIFF/PSB hỏng hoặc bị cắt | Không crash; hoặc hiện được qua ImageIO, hoặc báo lỗi | | |

## M9 — Panel thông tin và Cài đặt

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 9.1 | Nhấn I | Panel 280pt gắn bên phải cửa sổ (hoặc bên trái khi hết chỗ), đi theo khi kéo/đổi cỡ cửa sổ; histogram, Chung, Máy ảnh, Vị trí (ảnh có GPS), Hiển thị | | |
| 9.2 | Chuyển ảnh khi panel mở | Nội dung đổi ngay | | |
| 9.3 | Chọn/copy một giá trị; click đường dẫn thư mục; click bản đồ | Copy được; mở Finder; mở Maps | | |
| 9.4 | Panel khi fullscreen / gallery | Phủ lên mép phải | | |
| 9.5 | Thoát app khi panel đang mở, mở lại | Panel vẫn mở | | |
| 9.6 | ⌘, → từng tab; đổi từng tuỳ chọn | Có hiệu lực ngay, giữ sau khi mở lại app | | |
| 9.7 | Chép `build/ViVuView.app` vào /Applications, mở từ đó, tab Định dạng: tích JPEG | Hệ thống có thể hỏi xác nhận; double-click .jpg trong Finder mở ViVuView | | |
| 9.8 | Bỏ tích JPEG | Trả về app mặc định trước đó | | |
| 9.9 | Nền "Ô caro", mở PNG trong suốt | Ô caro sau phần trong suốt | | |
| 9.10 | Trợ giúp → Phím tắt | Bảng phím đúng UI_SPEC mục 6 | | |
