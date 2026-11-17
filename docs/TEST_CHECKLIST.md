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
| 9.10 | Trợ giúp → Phím tắt | Bảng phím tắt kính lỏng hiện giữa cửa sổ, đúng UI_SPEC mục 6.1 | | |

## M10 — Hoàn thiện

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 10.1 | Mở GIF / WebP / APNG động | Phát đúng tốc độ; Space dừng/phát; `,` `.` từng khung; status bar ghi "khung i/n" | | |
| 10.2 | Mở RAW (CR3, NEF, ARW, DNG…) | Hiện nhanh từ ảnh xem trước nhúng; zoom 100% thì xử lý RAW đầy đủ | | |
| 10.3 | Settings → RAW "Luôn xử lý RAW đầy đủ" | Mọi RAW hiện bản xử lý đầy đủ | | |
| 10.4 | Đổi ngôn ngữ hệ thống sang một ngôn ngữ app có (English, 日本語, Deutsch…) và một ngôn ngữ app không có (ví dụ Polski) | Giao diện theo ngôn ngữ đó; ngôn ngữ app không có thì tiếng Anh | | |
| 10.5 | Mở nhiều ảnh lớn liên tục khi máy thiếu RAM | App không bị đóng; ảnh hiện tại vẫn xem được | | |
| 10.6 | Chạy trên macOS 14 hoặc 15 (máy thật hoặc máy ảo) | Mọi mục ở trên chạy; lớp phủ dùng nền mờ tối thay cho kính | | |
| 10.7 | Chạy trên máy Mac Intel thật | Mọi mục ở trên chạy; ghi lại tốc độ chuyển ảnh | | |

## Sau M10 — Giao diện hệ thống, SVG, icon, ngôn ngữ

| # | Thao tác | Kỳ vọng | Ngày | Kết quả |
|---|---|---|---|---|
| 11.1 | Rê chuột lên cửa sổ xem ảnh | Nút đèn giao thông và bo góc cửa sổ theo kiểu macOS hiện tại (như Finder, Preview), không phải kiểu phẳng cũ | | |
| 11.2 | Mở app không kèm file; rồi mở một file bằng ⌘O, Finder, kéo-thả | Cửa sổ nằm đúng giữa màn hình (cả chiều ngang và dọc) | | |
| 11.3 | Nhấn đúp vào cửa sổ trống (chưa có ảnh) | Hiện hộp chọn file như ⌘O | | |
| 11.4 | Mở Cài đặt (⌘,), bấm qua 5 tab | Hàng biểu tượng trên thanh công cụ; nội dung là các nhóm bo góc; cửa sổ đổi chiều cao theo tab, không thừa khoảng trống | | |
| 11.5 | Mở một file SVG, zoom sâu (⌘↑ nhiều lần) | Hình nét ở mọi mức zoom; thumbnail SVG có trong filmstrip/gallery | | |
| 11.6 | Nhìn icon app trong Dock, Finder, Launchpad, ⌘Tab | Icon logo ViVuView, đúng hình dạng icon macOS; trên macOS 26+ có hiệu ứng kính | | |
| 11.7 | Cài đặt → Chung → Ngôn ngữ: chọn 日本語, mở lại app; chọn lại "Theo hệ thống" | Giao diện tiếng Nhật sau khi mở lại; về ngôn ngữ hệ thống sau khi chọn lại | | |
| 11.8 | Rê chuột lên cửa sổ có ảnh; vào rồi thoát fullscreen, rê chuột lại | Dải tiêu đề thấp vừa nút, cùng chiều cao trước và sau fullscreen; nút đèn giao thông, tên file và 3 nút bên phải nằm giữa dải | | |
| 11.9 | Mở PNG trong suốt và một SVG khi chưa từng đổi "Nền" | Ô caro sau phần trong suốt; ảnh JPEG vẫn trên nền đen | | |
| 11.10 | Giữ ⌘ + lăn chuột (chuột thường và trackpad); lăn chuột không giữ ⌘ khi đang zoom | ⌘ + lăn: zoom quanh con trỏ. Lăn thường: cuộn ảnh khi đang zoom, không làm gì khi đang vừa cửa sổ | | |
| 11.11 | Mặc định: click lên ảnh, rê chuột rồi để yên 2s | Status bar ẩn cùng thanh tiêu đề (click không ghim) | | |
| 11.12 | Bật Hiển thị → "Click lên ảnh để ghim status bar"; click một lần lên ảnh, rồi click lại | Ghim, có biểu tượng ghim; click lại thì bỏ ghim. Cú click đưa cửa sổ từ sau lên trước không ghim | | |
| 11.13 | Fullscreen, đưa chuột lên đỉnh màn hình | Thanh tiêu đề trượt xuống có đủ 3 nút đèn giao thông | | |
| 11.14 | Fullscreen, nhấn `T` (hoặc Filmstrip = Luôn hiện) | Ảnh co lên phía trên filmstrip, không bị đè; nhấn `T` lại thì ảnh trở về toàn màn hình | | |
| 11.15 | Cài đặt → Định dạng | Mỗi định dạng một dòng; SVG thấy ngay trong nhóm Ảnh thông dụng, không cần cuộn | | |
| 11.16 | Để chuột yên trên ảnh, chuyển ảnh bằng phím ← → | Thanh tiêu đề và status bar không tự hiện; rê chuột thì hiện | | |
| 11.17 | Chuột phải (hoặc Control-click) lên ảnh và lên một thumbnail filmstrip | Menu: Mở bằng ▸, Hiện trong Finder, Copy ảnh, Copy đường dẫn, Xoay trái/phải, Theo kích thước ảnh, Chuyển vào Thùng rác; trên filmstrip thì chuyển tới ảnh đó trước | | |
| 11.18 | Gallery toàn màn hình ở thư mục nhiều ảnh (ví dụ ~/Downloads), cuộn lên xuống | Mọi ô nhìn thấy đều có thumbnail sau ít giây | | |
| 11.19 | Mở Gallery | Thanh trên cùng chiều cao, kiểu chữ với thanh tiêu đề cửa sổ xem ảnh; có nút đèn giao thông | | |
| 11.20 | Cài đặt → Nền = Xám đậm; chuyển nhiều ảnh, đổi cỡ cửa sổ, thoát rồi mở lại app | Nền luôn xám, không lúc nào nháy hay nhảy sang đen | | |
| 11.21 | Fullscreen; để chuột giữa màn hình, rồi đưa lên đỉnh | Thanh tiêu đề ẩn; đưa lên đỉnh thì trượt xuống cùng menu, có đủ 3 nút đèn giao thông | | |
| 11.22 | Vào rồi thoát fullscreen, chuyển sang ảnh khác cỡ | Cửa sổ vẫn tự co theo ảnh | | |
| 11.23 | Mở một file .ico / .icns | Ảnh tĩnh, status bar không ghi "khung i/n" | | |
| 11.24 | Gallery ở ~/Downloads (có `ba er diagram.png` / `.svg`) | Các ô khác có thumbnail trong vài giây; riêng file rất nặng hiện sau | | |
| 11.25 | Gallery và filmstrip trên ảnh nền trắng | Ô đang chọn/ảnh hiện tại có vòng màu nhấn bên ngoài, thấy rõ | | |
| 11.26 | Chuyển ảnh ở chế độ cửa sổ (hiệu ứng trượt) | Ảnh trượt có góc bo như cửa sổ, không có lúc góc vuông đổi sang góc bo | | |
| 11.27 | Chuột phải lên ảnh; xem menu Xem, Đi tới | Phím tắt hiện ở cột phải; menu chuột phải có Chia sẻ, zoom, xoay, Thông tin/Filmstrip/Gallery/Toàn màn hình; trong Gallery gõ chữ vẫn nhảy tới file | | |
| 11.28 | Cài đặt → Hiệu năng → Bộ nhớ cho thumbnail | Mặc định "Tự động (… MB)" | | |
| 11.29 | Fullscreen, đưa chuột lên đỉnh màn hình | Thanh tiêu đề có "tên file — ViVuView" và 3 nút đèn giao thông; status bar có tên file ở đầu | | |
| 11.30 | Cài đặt → Hiển thị → Kính lỏng (Mờ / Trong) / Độ tối; rê chuột lên ảnh | Thanh tiêu đề, status bar, thanh Gallery đổi ngay theo; 0% trong nhất, 80% gần như đặc | | |
| 11.31 | Cài đặt → Nền = Xám, rồi Xám nhạt; chuyển ảnh, mở Gallery, đổi cỡ cửa sổ | Nền đổi ngay đúng màu, không nháy đen; trên Xám nhạt dòng chữ gợi ý/lỗi là chữ tối, đọc được | | |
| 11.32 | Cài đặt → Nền = Nửa trong suốt; đặt cửa sổ lên trên một app khác, chuyển ảnh, đổi cỡ, vào rồi ra fullscreen | Thấy app phía sau mờ tối qua nền, góc cửa sổ vẫn bo tròn; fullscreen nền đen; ra khỏi fullscreen lại trong suốt | | |
| 11.33 | Cài đặt: kéo các thanh Độ tối, Thời lượng hiệu ứng, Độ rộng cột Gallery qua giá trị mặc định | Có vạch nhỏ dưới rãnh đúng chỗ nút ở giá trị mặc định; kéo gần thì nút hít vào vạch | | |
| 11.34 | Ảnh vừa cửa sổ: nhấn ↑ ↓; zoom vào bằng + rồi nhấn ↑ ↓ | Vừa cửa sổ: không có gì xảy ra; đang zoom: ảnh pan lên/xuống, không đổi mức zoom | | |
| 11.35 | Nhấn `?`, rồi ⌘/, rồi chuột phải → Phím tắt, rồi Settings → Điều khiển → Xem phím tắt…; mỗi lần đóng bằng Esc hoặc click ra ngoài | Bảng mở/đóng đúng; đọc được trên ảnh sáng lẫn tối; kéo cửa sổ thì bảng đi theo; trong fullscreen vẫn hiện; mỗi phím ghi trong bảng làm đúng như ghi | | |
