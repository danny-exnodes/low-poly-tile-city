---
name: developer
description: Vai Developer của Low-Poly Tile City — code trên nhánh feature/vX.Y.Z theo issue status: ready, chạy check.sh (analyze + test + bench + build) trước push, commit theo Conventional Commits có số trước → sau và Refs #N. Dùng khi bắt tay code hoặc khi cần cài môi trường Flutter.
---

# Developer

## Môi trường
- Container mới thường **chưa có Flutter**. Cài bản ghim:
  ```bash
  cd /opt && curl -sSo f.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz \
    && tar xf f.tar.xz && rm f.tar.xz && git config --global --add safe.directory /opt/flutter
  export PATH=/opt/flutter/bin:$PATH
  ```
  (CI ghim cùng phiên bản trong `.github/workflows/deploy-pages.yml`.)
- `github.com` bị chặn với curl; pub.dev và storage.googleapis.com dùng được.

## Nhánh
- `feature/vX.Y.Z` từ `master` mới nhất. PR cũ của nhánh đã merge thì tạo lại nhánh từ `master`, không chồng commit lên lịch sử đã merge.

## Bản đồ mã nguồn
| Vùng | File |
| --- | --- |
| Primitive, part, LOD | `lib/engine/mesh.dart` |
| Ánh sáng, mùa, đêm, tuyết | `lib/engine/lighting.dart` |
| Object, hạt, cảnh | `lib/engine/scene.dart` |
| Camera, vẽ, tilt-shift, chọn object | `lib/engine/renderer.dart` |
| Bố cục khối, dựng khối, bóng, heightmap, resize | `lib/world/city.dart` |
| Kiểu nhà | `lib/world/buildings.dart` |
| Tượng đài | `lib/world/monuments.dart` |
| Cây, xe, người, đèn, ghế, đài phun | `lib/world/props.dart` |
| Xe chạy, người đi, gió, lá/tuyết/bụi | `lib/world/simulation.dart` |
| Trạng thái chung, thao tác, hiệu ứng dựng | `lib/world/world.dart` |
| Panel | `lib/ui/*.dart` |
| Âm thanh | `lib/audio/audio_engine.dart` |
| Hook cho QA | `lib/debug_hook.dart` |
| Test, benchmark | `test/world_test.dart`, `test/bench_test.dart` |

## Quy ước code
- Viết giống code xung quanh; comment giải thích *vì sao*, kèm số issue `(#4)`.
- Hàm dữ liệu thuần, test được trên Dart VM (`flutter test`) — đừng phụ thuộc trình duyệt trong `lib/world`, `lib/engine`.
- Mesh dùng chung không được sửa tại chỗ.
- Sửa file bằng script: luôn `assert` chuỗi gốc có trong file (`str.replace` thất bại im lặng).
- Thư viện mới: đã phát hành ≥ 2 tuần, ghim đúng phiên bản.

## Debug hook
- `lib/debug_hook.dart` đưa `window.__tileCity` (`stats()`, `cmd('{"op":…}')`) **chỉ** khi build với `--dart-define=DEBUG_HOOK=true`. Đây là cờ build nên không cần gỡ trước commit.
- Thêm lệnh mới vào `cmd()` khi QA cần điều khiển tính năng mới.

## Trước khi push
```bash
.claude/skills/developer/scripts/check.sh   # flutter analyze && flutter test (gồm bench) && flutter build web
```
Đụng hiệu năng: chạy thêm `perf.cjs` (skill `qa-visual`) và ghi số vào commit.

## Commit
- Conventional Commits tiếng Anh: `perf: …`, `feat: …`, `fix: …`, `docs: …`, `test: …`, `chore: …`.
- Body: số đo trước → sau; dòng cuối `Refs #N`.
- `.claude/skills/developer/scripts/commit.sh "perf: …" "body…" "Refs #4"` thêm trailer attribution (đặt `CLAUDE_COAUTHOR`, `CLAUDE_SESSION_URL` theo đúng dòng session yêu cầu).
- Không ghi model ID vào repo.

## Bẫy đã gặp
- `pkill -f <pattern>` khớp cả lệnh shell đang chạy nên tự giết shell. Dừng server bằng `fuser -k <port>/tcp`.
- Flutter chạy bằng root in cảnh báo "Woah!", vô hại.
- `toImageSync` trong `flutter_tester` rất chậm (raster phần mềm).
