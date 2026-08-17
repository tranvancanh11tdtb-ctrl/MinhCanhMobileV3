# Minh Cảnh Mobile V3

Ứng dụng Flutter quản lý cửa hàng điện thoại, chạy offline bằng SQLite.

## Chức năng bản lõi 0.1

- Tạo mẫu điện thoại hoặc phụ kiện.
- Một mẫu điện thoại chứa nhiều máy, mỗi máy có một IMEI và giá vốn riêng.
- Phiếu nhập hàng làm tăng tồn kho.
- Bán đúng IMEI; phụ kiện không được bán vượt tồn.
- Hóa đơn, doanh thu và lợi nhuận theo đúng giá vốn.
- Hủy hóa đơn để hoàn lại IMEI/số lượng tồn.
- Không đăng nhập, không mã PIN, không dữ liệu mẫu.

## Build APK bằng GitHub Actions

1. Tạo repository GitHub trống và tải toàn bộ dự án này lên.
2. Mở tab **Actions**.
3. Chọn workflow **Build Android APK** và bấm **Run workflow**.
4. Khi hoàn tất, tải artifact `MinhCanhMobileV3-apk`.

Workflow tự chạy `flutter create` để sinh phần khung Android trước khi build.
