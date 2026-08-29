# Minh Cảnh Mobile V3

Ứng dụng Flutter quản lý cửa hàng điện thoại, chạy offline bằng SQLite.

## Chức năng V3.10

- Tạo mẫu điện thoại hoặc phụ kiện.
- Một mẫu điện thoại chứa nhiều máy, mỗi máy có một IMEI và giá vốn riêng.
- Phiếu nhập hàng làm tăng tồn kho.
- Bán đúng IMEI; phụ kiện không được bán vượt tồn.
- Hóa đơn, doanh thu và lợi nhuận theo đúng giá vốn.
- Hủy hóa đơn để hoàn lại IMEI/số lượng tồn.
- Một phiếu nhập chứa nhiều sản phẩm, nhiều IMEI và giá/giảm giá riêng từng dòng.
- Quản lý phân loại hàng hóa hai cấp và danh mục hãng.
- Lọc kiểm kho theo phân loại, không làm mất dữ liệu từ các bản cũ.
- Có mã PIN bảo vệ ứng dụng và cho phép đổi PIN trong phần cài đặt.

## Build APK bằng GitHub Actions

1. Tạo repository GitHub trống và tải toàn bộ dự án này lên.
2. Mở tab **Actions**.
3. Chọn workflow **Build Android APK** và bấm **Run workflow**.
4. Khi hoàn tất, tải artifact `MinhCanhMobileV3-apk`.

Workflow tự chạy `flutter create` để sinh phần khung Android trước khi build.
