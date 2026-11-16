# Sổ hiệu năng

Mỗi mốc ghi kết quả đo ở đây (TECH_SPEC mục 11.2). Mốc sau chậm hơn mốc trước quá 20% ở cùng phép đo là lỗi phải sửa trước khi commit. Mục tiêu nằm ở PLAN mục 3.

| Mốc | Ngày | Máy | Commit | Phép đo | p50 | p95 | max | Ghi chú |
|---|---|---|---|---|---|---|---|---|
| M0 | 2026-11-16 | Apple Silicon, 8 nhân, 16GB, macOS 27.0.1 | — | — | — | — | — | Chưa có phép đo; khung bench sẵn sàng |
| M0.5 | 2026-11-16 | như trên | — | PSB 480MP fit 3024, bộ đọc riêng | 750ms (ấm) | — | 950ms | RAM đỉnh 43MB; ImageIO 2,4–3,0s |
| M0.5 | 2026-11-16 | như trên | — | JPEG 12MP decode đầy đủ (ImageIO) | 30ms | — | 39ms | + chuyển màu vImage 2–3ms |
| M0.5 | 2026-11-16 | như trên | — | HEIC 12MP decode đầy đủ + lấy pixel | ~190ms | — | 240ms | |
| M0.5 | 2026-11-16 | như trên | — | TIFF 720MP fit 3024 (ImageIO) | 6,6s | — | 9,0s | Lý do cần bộ đọc TIFF riêng |
| M3 | 2026-11-16 | như trên | M3 | Next/prev đã preload (A, 150 bước, JPEG 12MP), tới khung trình chiếu | 3,1ms | 10,9ms | 16,8ms | Vòng 2; footprint vòng 1 → vòng 2: 813 → 781MB (không rò rỉ) |
| M3 | 2026-11-16 | như trên | M3 | Next/prev liên tục, chờ ảnh sắc nét (B, 100 bước) | 12–13ms | 58–60ms | 73–111ms | |
| M3 | 2026-11-16 | như trên | M3 | Giữ phím 30Hz (C, 120 bước), tới khung đầu | 3,1ms | 6,8ms | 9,0ms | 120/120 ảnh hiện, 0 bước chậm hơn 1 khung 60Hz, hàng đợi rỗng khi kết thúc |
| M3 | 2026-11-16 | như trên | M3 | Mở ảnh tính từ lúc khởi động tiến trình (JPEG 12MP / PSD 6MP / HEIC 15MP) | 245ms / 202ms / 723ms | — | — | Gồm cả thời gian khởi động app |
| M3 | 2026-11-16 | như trên | M3 | Mở JPEG 200MP tính từ khởi động | 1011ms | — | — | Footprint 2,7GB do nạp trước các file khổng lồ cạnh nó qua ImageIO; xử lý ở M7–M8 |
| M3 | 2026-11-16 | như trên | M3 | CPU khi đứng yên 10s với ảnh tĩnh | 0,03% | — | — | Mục tiêu < 1% |
| M4 | 2026-11-16 | như trên | M4 | Next/prev đã preload (A2, hiệu ứng tắt khi đo) | 2,8ms | 10,5ms | 17,7ms | Không chậm hơn M3 quá 20%; footprint vòng 1 → 2: 782 → 787MB |
| M4 | 2026-11-16 | như trên | M4 | Giữ phím 30Hz (C) | 3,1ms | 6,9ms | 8,9ms | 120/120 ảnh hiện |
| M5 | 2026-11-16 | như trên | M5 | Next/prev đã preload (A2) | 2,6–3,1ms | 10,6–11,6ms | 14,7ms | Có filmstrip/thumbnail nền |
| M5 | 2026-11-16 | như trên | M5 | Liên tục, chờ sắc nét (B) | 10,8–13,8ms | 63–65ms | 72–89ms | Lần đầu đo được p50 15,5–17,7ms (vượt 20%) do thumbnail ±20 tranh CPU → tách hàng đợi thumbnail (2 luồng, QoS utility) và hoãn thumbnail điều hướng tới khi dừng duyệt 250ms |
| M5 | 2026-11-16 | như trên | M5 | Giữ phím 30Hz (C) | 3,3ms | 6,8–7,1ms | 9,9ms | 120/120 ảnh hiện |
| M7 | 2026-11-16 | như trên | M7 | JPEG 200MP: có hình / pyramid xong / 100% đủ tile / pan đủ tile | 629ms / 2,6s / 20ms / 79ms | — | — | RAM đỉnh 3,1GB (ImageIO giữ thêm một bản decode 0,8GB trong lúc dựng) |
| M7 | 2026-11-16 | như trên | M7 | JPEG 72MP: có hình / pyramid xong / 100% đủ tile / pan | 302ms / 758ms / 22ms / 9ms | — | — | RAM đỉnh 1,3GB |
| M7 | 2026-11-16 | như trên | M7 | Next/prev đã preload (A2) / liên tục (B) / giữ phím (C) | 2,8 / 9,8 / 3,2ms | 10,8 / 63,3 / 7,1ms | 16,1 / 114 / 8,8ms | Không chậm hơn M5 |
| M8 | 2026-11-16 | như trên | M8 | BigTIFF 720MP có 5 overview (3GB): ảnh vừa màn hình (bench) / mở tính từ khởi động app | 21–58ms / 225ms | — | — | ImageIO 8,9s; RAM đỉnh 0,7GB khi zoom/pan |
| M8 | 2026-11-16 | như trên | M8 | TIFF 720MP không overview (2,2GB): fit + tầng RAM / mở từ khởi động | 0,77–0,97s / 0,97s | — | — | ImageIO 6,6–8,6s; mục tiêu ấm 300ms **chưa đạt** (đọc 2,2GB); RAM đỉnh 1,04GB |
| M8 | 2026-11-16 | như trên | M8 | PSB 480MP RLE (1,4GB): fit + tầng RAM / mở từ khởi động | 0,66–1,05s / 0,95s | — | — | ImageIO 2,4–3,0s; mục tiêu ấm 300ms **chưa đạt**; RAM đỉnh 0,72GB |
| M8 | 2026-11-16 | như trên | M8 | Ảnh khổng lồ: đủ tile ở 100% / sau khi pan | 74–278ms / 50–124ms | — | — | Mục tiêu pan ≤150ms: đạt |
