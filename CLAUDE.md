# CLAUDE.md — Low-Poly Tile City

Ứng dụng Flutter web: một thị trấn low-poly sinh thủ tục trên bàn cờ ô vuông, renderer tự viết (painter's algorithm trên `Canvas.drawVertices`). Bản chạy: https://danny-exnodes.github.io/low-poly-tile-city/

- **Checkpoint mới nhất:** [`docs/releases/v0.0.3.md`](docs/releases/v0.0.2.md) — đọc trước khi làm gì.
- **Quy trình nhóm agent:** bộ skill trong `.claude/skills/` — bắt đầu từ `tile-city-workflow` (PO → TechLead → Developer ⇄ QA → Release → Steward).
- **Lộ trình:** issue Roadmap #1; chỉ code issue có label `status: ready`.
- **Kiểm tra trước push:** `.claude/skills/developer/scripts/check.sh` (analyze + test + benchmark + build).
- **Ngôn ngữ:** UI/tài liệu/issue/PR tiếng Việt; commit, tiêu đề PR, comment code tiếng Anh. Không ghi model ID vào repo.

## Kiến trúc tóm tắt
- `lib/engine/` — mesh, ánh sáng theo giờ/mùa, cảnh, renderer (sort theo độ sâu, LOD, nền cache thành Picture, tilt-shift).
- `lib/world/` — bố cục khối (`City`, mỗi `Block` giữ object của mình để dựng lại cục bộ), nhà, tượng đài, cây/xe/người, mô phỏng gió/lá/giao thông, trạng thái `World`.
- `lib/ui/` — panel Flutter; `lib/audio/` — Web Audio; `lib/debug_hook.dart` — `window.__tileCity` cho QA (chỉ khi `--dart-define=DEBUG_HOOK=true`).
- `test/bench_test.dart` — ngân sách hiệu năng, chạy trong CI.
- CI `.github/workflows/deploy-pages.yml`: build + test mọi push/PR; push vào `master` deploy Pages và tự tạo tag + release theo `version:` trong `pubspec.yaml`.
