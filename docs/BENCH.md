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
