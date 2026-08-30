# Quyền riêng tư — Cảnh App Lock

Cảnh App Lock hoạt động hoàn toàn trên thiết bị và không kết nối Internet.

- Danh sách ứng dụng được khóa chỉ lưu cục bộ trên điện thoại.
- Mã PIN không được lưu ở dạng có thể đọc; ứng dụng lưu PBKDF2 hash với salt ngẫu nhiên.
- Việc nhận diện vân tay/khuôn mặt do giao diện hệ thống Android xử lý. Ứng dụng chỉ nhận kết quả thành công hoặc thất bại và không thể truy cập dữ liệu sinh trắc học.
- Dịch vụ hỗ trợ tiếp cận chỉ nhận sự kiện thay đổi cửa sổ để xác định tên gói ứng dụng đang mở. Ứng dụng đặt `canRetrieveWindowContent=false` và không đọc văn bản, thao tác hay nội dung màn hình.
- Ứng dụng không có quyền Internet, không có quảng cáo và không gửi dữ liệu tới máy chủ.
