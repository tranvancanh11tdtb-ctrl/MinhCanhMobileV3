# Cảnh App Lock

Ứng dụng khóa app riêng cho điện thoại Samsung/Android, không quảng cáo và không cần mạng.

## Tính năng bản 1.0

- Chọn từng ứng dụng cần khóa.
- Mở bằng mã PIN riêng 4–8 số.
- Mở bằng vân tay hoặc khuôn mặt qua hộp thoại bảo mật của Android.
- Tự khóa lại ngay sau khi rời ứng dụng hoặc tắt màn hình.
- Màn quản lý cũng yêu cầu xác thực trước khi thay đổi cài đặt.
- Không lưu dữ liệu vân tay/khuôn mặt; mã PIN chỉ được lưu dưới dạng PBKDF2 hash kèm salt.
- Không dùng mạng, không quảng cáo, không gửi dữ liệu ra ngoài.

## Cài và bật trên Samsung

1. Cài file APK rồi mở **Cảnh App Lock**.
2. Tạo mã PIN riêng.
3. Nhấn **Bật dịch vụ khóa ứng dụng**, tìm **Cảnh App Lock** rồi bật.
4. Nhấn **Cho phép xuất hiện trên cùng** rồi bật quyền.
5. Chọn Zalo, Facebook, Thư viện hoặc app muốn khóa.
6. Mở thử app vừa chọn và xác thực bằng vân tay, khuôn mặt hoặc PIN.

Nếu mục Hỗ trợ tiếp cận bị mờ trên Android 13 trở lên: mở **Thông tin ứng dụng Cảnh App Lock → dấu ba chấm ⋮ → Cho phép cài đặt bị hạn chế**, sau đó quay lại bật dịch vụ.

## Lưu ý kỹ thuật

- App dùng `AccessibilityService` chỉ để nhận tên gói ứng dụng vừa xuất hiện. Cấu hình đặt `canRetrieveWindowContent=false`, nên không đọc nội dung màn hình.
- Quyền **Xuất hiện trên cùng** giúp Android cho phép màn khóa hiện đúng lúc từ nền.
- Một số mẫu Samsung không cho ứng dụng bên thứ ba dùng nhận diện khuôn mặt. Trong trường hợp đó, vân tay và PIN vẫn hoạt động.
- Đây là lớp khóa riêng tư tiện lợi. Vì là app bên thứ ba, người có quyền mở khóa điện thoại và vào Cài đặt hệ thống vẫn có thể gỡ hoặc tắt dịch vụ.

## Build

Mở thư mục bằng Android Studio (JDK 17, Android SDK 35), sau đó chọn **Build → Build APK(s)**.

Nếu đưa mã nguồn lên GitHub, workflow `.github/workflows/build-apk.yml` sẽ build `app-debug.apk` và đưa vào mục **Actions → Artifacts**.

## Cấu trúc chính

- `MainActivity.java`: thiết lập PIN, cấp quyền và chọn app.
- `AppLockAccessibilityService.java`: phát hiện ứng dụng đang mở.
- `UnlockActivity.java`: màn PIN và xác thực sinh trắc học.
- `AppPrefs.java`: lưu cấu hình và PBKDF2 hash của PIN.
- `LockSession.java`: quản lý phiên mở khóa trong bộ nhớ.
