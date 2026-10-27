---
name: qa-visual
description: Vai QA của Low-Poly Tile City — tái hiện lỗi, chụp ảnh trước/sau, đo fps tương đối trên Chromium và đọc số CPU thật của app qua window.__tileCity. Dùng khi tái hiện yêu cầu, trước khi báo xong thay đổi nhìn thấy được, hoặc khi đo hiệu năng trình duyệt.
---

# QA

## Công cụ
- Playwright + Chromium swiftshader cài sẵn trong sandbox (`require('playwright')` chạy từ mọi thư mục). **Không** chạy `playwright install`.
- swiftshader chỉ ~2–7 fps: số fps chỉ dùng **so tương đối** giữa hai bản build trên cùng máy. Diễn biến theo thời gian (lá rơi, xe chạy, hiệu ứng dựng) tua bằng `cmd({op:'advance', v:giây})` hoặc kiểm bằng unit test.

## Chuẩn bị
```bash
.claude/skills/qa-visual/scripts/serve.sh 8082          # build DEBUG_HOOK + serve nền
```
So với bản cũ: `git worktree add /tmp/.../base <commit>`, chép `lib/debug_hook.dart` + 2 dòng gọi trong `main.dart` nếu bản cũ chưa có, build `-o build/web` và serve cổng khác.

## Script (`.claude/skills/qa-visual/scripts/`)
- `shoot.cjs <url> <outDir> '[["tên","js"],…]'` — mỗi bước chạy `js` trong trang với `c(obj)` = `__tileCity.cmd`, chờ `WAIT` ms rồi lưu `<tên>.png`. Bước chuột: `"@click x y"`, `"@drag x y dx dy"`, `"@wheel dy"`. Env: `W`, `H`, `WAIT`.
  ```bash
  node shoot.cjs http://localhost:8082/ /tmp/shots '[["noon","c({op:\"hour\",v:12}); return c({op:\"advance\",v:1}).fps"]]'
  ```
- `perf.cjs <url> [nhãn]` — 4 kịch bản 6 s: tĩnh có tilt-shift, đang xoay, đang kéo Light, tĩnh không tilt-shift. In fps, p50/p95 khung, "dart render" (EMA CPU render của app), số tam giác.
- `grid.py out.png <cột> ảnh…` — ghép lưới ảnh trước/sau có nhãn.
- `loadtime.cjs <url> [nhãn]` — giả lập mạng chậm (env `MBPS`, `RTT`), chụp lúc 300 ms và 2 s, đo thời gian đến khi app sẵn sàng (#10).
- `shoot.cjs` còn có bước `"@hold x y"` (chạm giữ), `"@reload"` (tải lại, giữ localStorage — kiểm autosave), `"@goto <url>"` (mở link chia sẻ). Mỗi lần chạy là một profile mới (localStorage trống).

## Lệnh `__tileCity.cmd`
`hour` (số giờ), `mode` (`view|move|build`), `tile` ([i,j,kind]), `selectTile`, `selectLot`, `edit` ([block,lot,{floors,facade,roof,roofKind,style,rotSteps,demolished}]), `undo`, `build` ([block,lot,monument|null]), `lot`, `camera`, `share` (trả thêm `code`), `season` (`spring|summer|autumn|winter`), `resize` ([nx,nz]), `tilt` (bool), `orbit` ([dx,dy] px), `zoom` (hệ số), `wholeMap`, `advance` (giây mô phỏng), `gust`, `devil`, `lod` (hệ số ngưỡng LOD). Mọi lệnh trả về `stats()`: fps, cpuMs, simMs, triangles, drawCalls, objects, blocks, houses, kinds[], particles, building, hour, season.

## Kiểm theo loại thay đổi
- **Dữ liệu/bố cục:** đếm trước/sau (unit test hoặc `stats().kinds`).
- **Hình ảnh:** ảnh 2–4 góc trước/sau, ghép bằng `grid.py`.
- **Hiệu năng:** `flutter test test/bench_test.dart` (VM) + `perf.cjs` (trình duyệt) trước/sau.
- **Tương tác:** `@click`/`@drag` theo toạ độ (UI vẽ trên canvas, không có DOM); kiểm kết quả qua `stats()`.
- **Điện thoại:** `W=390 H=844`.

## Báo cáo
Ghi rõ phần nào chỉ đo trên swiftshader và cần chủ dự án thử trên máy thật.
