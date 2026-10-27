---
name: tile-city-workflow
description: Điều phối một đợt việc trên Low-Poly Tile City theo quy trình PO → TechLead → Developer ⇄ QA → Release → Steward. Dùng khi mở session, khi chủ dự án gửi một đợt yêu cầu mới, hoặc khi không rõ bước tiếp theo.
---

# Quy trình một đợt việc

Một agent lần lượt đóng các vai của một nhóm nhỏ. Mỗi vai có skill riêng:
`product-owner`, `tech-lead`, `developer`, `qa-visual`, `release-checkpoint`, `steward`.

```
Chủ dự án ─ yêu cầu ─▶ PO ─▶ TechLead ─▶ Developer ⇄ QA ─▶ Release ─▶ Steward ─▶ báo cáo
                      issue  status:ready  commit    ảnh/số  checkpoint  PR/CI/merge
```

## Nguyên tắc
1. **Không code khi chưa có issue gắn `status: ready`** (PO và TL đã đồng ý).
2. **Đo, đừng đoán.** Lỗi phải tái hiện được; mỗi sửa đổi có số trước → sau (`flutter test test/bench_test.dart`, `perf.cjs`).
3. **Không báo xong khi chưa nhìn thấy kết quả** (ảnh `shoot.cjs` hoặc số đo).
4. **Mỗi đợt kết thúc bằng checkpoint** `docs/releases/vX.Y.Z.md`, đủ để agent mới không có lịch sử chat làm tiếp.
5. **Chủ dự án giao toàn quyền.** Chỉ hỏi lại khi việc tốn tiền thật, đổi giấy phép/điều khoản, hoặc không đảo ngược được.

## Các bước

**0. Mở đầu session**
- Đọc `CLAUDE.md` và checkpoint mới nhất (`docs/releases/v*.md`, số lớn nhất).
- Xem Roadmap (#1) và các issue `status: ready`.
- `git status`, `git log --oneline -5`; nhánh nào còn dở thì làm tiếp.
- Cài Flutter nếu container chưa có (xem `developer`).

**1. Nhận yêu cầu**
- Tách thành từng mục, giữ đúng đánh số của chủ dự án; báo cáo cuối đợt theo đúng thứ tự đó.
- Có bước tái hiện thì tái hiện trước bằng `qa-visual`, ghi hiện trạng (ảnh + số).
- Tạo task list, mỗi nhóm việc một task.

**2. Issue** (`product-owner`, `tech-lead`)
- Gom việc cùng vùng code/trải nghiệm vào một issue; mỗi issue xong được trong một PR.
- PO viết **[PO] Đề xuất**, TL viết **[TechLead] Phân tích**, cuối issue `✅ PO đồng ý · ✅ TechLead đồng ý`, label loại (`feature`/`bug`/`perf`/`chore`) + `status: ready` + ưu tiên `P1`–`P3`.
- Cập nhật Roadmap #1.

**3. Code** (`developer`)
- Một nhánh cho cả đợt: `feature/vX.Y.Z` từ `master` mới nhất.
- Mỗi commit là một nhóm việc, body có số trước → sau, cuối `Refs #N`.

**4. Kiểm tra** (`developer`, `qa-visual`)
- Trước mỗi push: `.claude/skills/developer/scripts/check.sh` (analyze + test + bench + build).
- Thay đổi nhìn thấy được: ảnh trước/sau (`shoot.cjs` + `grid.py`).
- Thay đổi hiệu năng: bench (VM) + `perf.cjs` (trình duyệt, so tương đối).

**5. Phát hành** (`release-checkpoint`, `steward`)
- Bump `version:` trong `pubspec.yaml`, viết checkpoint, cập nhật README + CLAUDE.md.
- Push, mở PR có `Closes #…`, theo dõi CI, merge khi xanh. Merge vào `master` tự deploy Pages **và** tự tạo tag + release từ version.

**6. Báo cáo**
- Theo thứ tự yêu cầu; mỗi mục: đã làm gì, nguyên nhân gốc, số trước → sau.
- Ghi rõ phần chưa kiểm được và vì sao (ví dụ: swiftshader không phản ánh GPU thật).
- Liệt kê việc chủ dự án cần làm (nếu có).
- Không lặp lại chi tiết kỹ thuật đã có trong checkpoint.

## Quy ước ngôn ngữ
- UI, tài liệu, body issue/PR: tiếng Việt. Commit message, tiêu đề PR, comment trong code: tiếng Anh.
- Gọi chủ dự án là "bạn"; khi viết tiếng Anh về người dùng dùng they/them.
- Không ghi model ID vào repo.
