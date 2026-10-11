# Minh Cảnh Mobile V3

Ứng dụng Flutter quản lý cửa hàng điện thoại, chạy offline bằng SQLite.

## Bản nâng cấp 3.13 — Bảo vệ vốn & ngân sách

Nhánh `agent/v3-13-capital-guard` kế thừa 3.12, thêm màn **Nhiều hơn → Bảo vệ vốn & ngân sách**. Dữ liệu hàng tồn, IMEI và giá vốn cũ được giữ nguyên, không nhập lại vốn hàng. Người dùng tự chốt tiền mặt và số dư ngân hàng ban đầu, thiết lập vốn sàn, ngân sách gia đình và dự phòng; báo cáo ghi riêng lợi nhuận và dòng tiền. Bản thử nghiệm chỉ nên cài trên thiết bị thử hoặc khi chữ ký tương thích với APK đang dùng. **Không gỡ ứng dụng đang lưu dữ liệu nếu chưa sao lưu.**

Xem [ghi chú nâng cấp 3.13](docs/releases/3.13.md). Workflow `V3.13 finance checks and APK` tạo APK thử nghiệm khi các bước kiểm thử thành công.

## Bản nâng cấp 3.12

Nhánh `agent/v3-12-upgrade` phát triển trên nền 3.11. Bổ sung nhập hàng gọn trên điện thoại/máy tính, lưu tạm, màu và giá vốn từng IMEI, tìm khách, báo cáo nhập–xuất–tồn theo kỳ, Thu–Chi có phân loại và khoản cố định hằng tháng. LAN yêu cầu giao thức tương thích và nút In mở trang chọn máy in.

Xem [ghi chú phát hành 3.12](docs/releases/3.12.md) về kiểm thử, dữ liệu cũ và giới hạn. Workflow **V3.12 upgrade checks** tạo artifact `MinhCanhMobileV312-APK`; APK có giao diện web tích hợp để dùng qua LAN. Cài đè bản 3.11 chỉ được xác nhận khi chứng thư ký trùng nhau; bản dùng thử không đồng nghĩa với bản cài đè.

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
