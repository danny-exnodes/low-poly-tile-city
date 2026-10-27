---
name: release-checkpoint
description: Vai Release của Low-Poly Tile City — cuối mỗi đợt viết checkpoint docs/releases/vX.Y.Z.md (10 mục cố định), cập nhật README, CLAUDE.md, bump version trong pubspec.yaml. Dùng cuối đợt, trước PR cuối.
---

# Release và checkpoint

## Việc cần làm
1. Bump `version:` trong `pubspec.yaml` (`X.Y.Z+N`, N tăng 1 mỗi bản). Merge vào `master` sẽ tự tạo tag + release.
2. Viết `docs/releases/vX.Y.Z.md` theo đúng 10 mục dưới, cùng tiêu đề với bản trước.
3. README: thêm khối **Mới trong vX.Y.Z** ở đầu mục "Phiên bản", thêm dòng vào danh sách phiên bản.
4. CLAUDE.md: trỏ tới checkpoint mới; thêm dòng nếu kiến trúc đổi.

## Mẫu checkpoint
```
# Low-Poly Tile City vX.Y.Z: release note và checkpoint
> Ngày · Commit (tag `vX.Y.Z` do CI tạo) · Bản chạy: https://danny-exnodes.github.io/low-poly-tile-city/
> Tài liệu này là điểm khôi phục ngữ cảnh: agent mới đọc file này + CLAUDE.md là làm tiếp được. Thay cho [vPrev](vPrev.md).

## 1. Sản phẩm là gì              (mô tả ngắn + yêu cầu của chủ dự án, giữ nguyên đánh số)
## 2. Tính năng mới trong vX.Y.Z   (bảng Nhóm | Tính năng | Issue + số liệu trước/sau)
## 3. Kiến trúc: phần thay đổi    (sơ đồ file/luồng + ghi chú kỹ thuật)
## 4. Giới hạn đã biết            ("Đã biết, chưa sửa")
## 5. Môi trường của agent        (mẹo sandbox)
## 6. Quy trình làm việc đã thống nhất
## 7. Lệnh hay dùng
## 8. Trạng thái issue            (✅ xong / 🟡 đang làm / ⏸️ hoãn / 🔒 chờ chủ dự án)
## 9. Gợi ý việc tiếp theo (chưa thống nhất; phải qua quy trình PO/TL)
## 10. Lịch sử thay đổi          (git log --oneline <tag trước>..HEAD)
```
