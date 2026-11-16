# Sổ hiệu năng

Mỗi mốc ghi kết quả đo ở đây (TECH_SPEC mục 11.2). Mốc sau chậm hơn mốc trước quá 20% ở cùng phép đo là lỗi phải sửa trước khi commit. Mục tiêu nằm ở PLAN mục 3.

| Mốc | Ngày | Máy | Commit | Phép đo | p50 | p95 | max | Ghi chú |
|---|---|---|---|---|---|---|---|---|
| M0 | 2026-11-16 | Apple Silicon, 8 nhân, 16GB, macOS 27.0.1 | — | — | — | — | — | Chưa có phép đo; khung bench sẵn sàng |
| M0.5 | 2026-11-16 | như trên | — | PSB 480MP fit 3024, bộ đọc riêng | 750ms (ấm) | — | 950ms | RAM đỉnh 43MB; ImageIO 2,4–3,0s |
| M0.5 | 2026-11-16 | như trên | — | JPEG 12MP decode đầy đủ (ImageIO) | 30ms | — | 39ms | + chuyển màu vImage 2–3ms |
| M0.5 | 2026-11-16 | như trên | — | HEIC 12MP decode đầy đủ + lấy pixel | ~190ms | — | 240ms | |
| M0.5 | 2026-11-16 | như trên | — | TIFF 720MP fit 3024 (ImageIO) | 6,6s | — | 9,0s | Lý do cần bộ đọc TIFF riêng |
