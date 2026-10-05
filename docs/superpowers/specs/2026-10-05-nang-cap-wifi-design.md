# Minh Cảnh Mobile — thiết kế nâng cấp Wi-Fi và giao diện

Ngày: 05/10/2026. Trạng thái: anh Cảnh đã duyệt thiết kế ngày 05/10/2026, 19:11 (giờ Việt Nam).

## Mục tiêu

Giữ nghiệp vụ hiện có, sửa sáu yêu cầu trên điện thoại, cho máy tính sử dụng đầy đủ nghiệp vụ qua mạng nội bộ, bổ sung báo cáo hàng hóa theo hai ảnh tham khảo và làm giao diện dễ dùng hơn. Không thuê máy chủ Internet. Không giới hạn máy tính ở chức năng xem hoặc in.

## Hiện trạng đã kiểm tra

- Kho mã nguồn: `tranvancanh11tdtb-ctrl/MinhCanhMobileV3`, nhánh main, commit `5ccf1a9a50692622b120745c1f2dd65c9a502130`.
- Flutter; SQLite cục bộ, cơ sở dữ liệu `minh_canh_mobile_v3.db`, schema phiên bản 6.
- Nghiệp vụ và phần lớn giao diện nằm trong `lib/main.dart`.
- Tổng quan có bảy thẻ số liệu nhưng chưa có thao tác mở chi tiết.
- Truy vấn bảo hành đang lấy cả hàng không có IMEI.
- Đã có danh bạ nhà cung cấp, chọn bằng danh sách; cần bổ sung tìm kiếm.
- Đã có xuất PDF tem 40×30mm, hóa đơn 80mm và một số phương thức in trên điện thoại.
- Tên APK được gửi là V3.10.1 nhưng pubspec nhánh main ghi 3.9.0+39. Trước khi sửa phải đối chiếu nhánh/tag/lần build để xác định nguồn đúng; không mặc định main là bản tương ứng APK.
- Chưa có máy chủ nội bộ hoặc bản trình duyệt được xác nhận chạy.

### Kết quả đối chiếu tiếp theo

- Đã tìm được nhánh `origin/agent/v3-10-multi-purchase-categories`, commit `906f10e`, pubspec `3.10.1+311`; đây là nền tảng được chọn để giữ nhập nhiều dòng, phân loại hai cấp và PIN. Schema nhánh này là phiên bản 7; thông tin main ở trên chỉ là kết quả khảo sát ban đầu.
- APK đính kèm xác minh chữ ký thành công. SHA-256 chứng thư: `d7154e2a61954557a9bd621f35b208cba9fdbbe53afc48bdf26f6aa1f9364f76`.
- Có khóa ký ứng dụng từ công việc trước trong môi trường; cần đối chiếu chứng thư khi đóng gói, không đưa khóa hoặc thông tin ký vào Git.
- Chưa xác nhận APK tương ứng nhánh chỉ bằng số phiên bản; vẫn phải đối chiếu gói và bản build trước phát hành.

## Lựa chọn kiến trúc

### Đề xuất: điện thoại giữ dữ liệu, máy tính truy cập qua trình duyệt

App Android cung cấp máy chủ nội bộ khi người dùng bật “Kết nối máy tính”. Máy tính cùng LAN/Wi-Fi mở địa chỉ mà app hiển thị, ghép nối và truy cập giao diện quản lý. Mọi thao tác nghiệp vụ trên hai thiết bị đi qua cùng lớp xử lý, cùng cơ sở dữ liệu điện thoại.

Đây là dùng chung dữ liệu trực tiếp, không phải hai bản cơ sở dữ liệu tự hòa trộn. Máy tính không có chế độ ghi ngoại tuyến khi mất kết nối điện thoại. Điện thoại vẫn dùng độc lập như hiện nay.

Khi điện thoại ra khỏi mạng, tắt app/dịch vụ hoặc mất điện, máy tính hiện trạng thái mất kết nối và chặn thao tác ghi. Không hiển thị giao dịch chưa lưu thành công. Khi nối lại phải tải dữ liệu mới và xác minh kết quả thao tác đang dở trước khi cho thử lại.

Một dịch vụ Android chạy nền có thông báo sẽ duy trì phiên kết nối trong phạm vi hệ điều hành cho phép. Kiểm tra thực tế khi khóa màn hình và đổi mạng; không cam kết luôn chạy khi người dùng buộc dừng ứng dụng.

### Các hướng đã cân nhắc

- Máy tính giữ dữ liệu chính: thuận lợi nếu máy tính luôn bật, nhưng thay đổi cách điện thoại đang hoạt động; điện thoại ra ngoài sẽ cần cơ chế ngoại tuyến và đồng bộ riêng.
- Mỗi thiết bị giữ bản dữ liệu và đồng bộ hai chiều: có thể dùng độc lập nhưng phức tạp hơn nhiều về IMEI, tồn kho, hủy hóa đơn, thu nợ và xử lý xung đột. Không thuộc bản thiết kế này.

## Chức năng trên máy tính

Đủ nghiệp vụ hiện có: tổng quan, hàng hóa/IMEI/phụ kiện, phân loại, nhập hàng nhiều dòng, bán hàng, hóa đơn và hủy/xóa theo quy tắc hiện tại, khách hàng, nhà cung cấp, công nợ/thu nợ, kiểm kho, điều chỉnh tồn, sửa chữa, bảo hành, thu chi, báo cáo, cài đặt thanh toán/VietQR, sao lưu và khôi phục.

Máy tính dùng trình duyệt; bố cục có thanh menu trái, bảng hàng rộng, ô tìm kiếm và khu vực thao tác. Không cần chốt hệ điều hành để thiết kế bản này. Máy in dùng trình điều khiển của máy tính và hộp thoại in của trình duyệt/PDF, không cam kết in im lặng.

Máy quét mã vạch dạng bàn phím USB nhập trực tiếp vào ô tìm kiếm. Camera và Bluetooth là khả năng theo thiết bị: không hứa dùng camera trình duyệt trên HTTP nội bộ; máy tính vẫn nhập/quét bằng USB được. Vân tay thuộc mở khóa Android, không tự động chuyển thành tính năng vân tay trình duyệt.

Sao lưu tạo từ cơ sở dữ liệu có thẩm quyền trên điện thoại. Khôi phục chỉ chạy độc quyền, chặn thao tác ghi khác, giữ một bản dự phòng và báo lại kết quả cho các máy đang kết nối.

## An toàn và tính nhất quán trong mạng nội bộ

- Mặc định kết nối máy tính tắt; chỉ bật sau khi mở khóa app.
- Ghép nối bằng mã dùng một lần, có thời hạn và giới hạn thử; điện thoại cho xem và ngắt thiết bị được ghép.
- Phiên có token ngẫu nhiên, hết hạn và thu hồi khi ngắt kết nối; không đưa PIN vào URL hoặc log.
- Máy chủ chỉ cung cấp API nghiệp vụ định nghĩa sẵn, không nhận câu SQL tùy ý từ trình duyệt. Kiểm tra dữ liệu và xác thực phía máy chủ cho mọi thao tác.
- Ràng buộc nguồn truy cập/Host, bảo vệ yêu cầu ghi khỏi CSRF và truy cập chéo nguồn. Không mở cổng router ra Internet.
- HTTP nội bộ không mã hóa nội dung truyền: bản này dành cho mạng cửa hàng tin cậy, không dùng trên Wi-Fi công cộng. Ghép nối không đồng nghĩa mã hóa đường truyền.
- Giao dịch bán hàng/nhập hàng/thu nợ cập nhật nguyên tử trong SQLite. Kiểm tra lại tồn và trạng thái IMEI ngay khi lưu, không dựa vào số liệu giao diện cũ.
- Mỗi yêu cầu ghi có mã chống gửi trùng; ngắt mạng hoặc bấm hai lần không tạo hai hóa đơn/phiếu thu.
- Các sửa đổi có kiểm tra phiên bản bản ghi; dữ liệu đã thay đổi thì yêu cầu tải lại thay vì ghi đè âm thầm.
- Sau ghi thành công phát tín hiệu cập nhật cho thiết bị còn lại; kết nối lại luôn tải trạng thái mới.

## Sáu thay đổi ban đầu

1. **Bảo hành:** danh sách chỉ lấy dòng bán hàng gắn máy quản lý IMEI; phụ kiện không xuất hiện. Không xóa lịch sử cũ. Lọc Tất cả/Ngày/Tháng/Năm theo ngày bán, tìm tên khách/SĐT/IMEI/mã hóa đơn. Lịch sử tiếp nhận bảo hành vẫn có ngày và trạng thái riêng.
2. **Khách hàng:** có Tất cả/Còn nợ; tổng nợ và danh sách khách dư nợ dương. Chi tiết hiển thị hóa đơn, các lần trả và điều chỉnh; thu tiền cập nhật cùng quy tắc hiện có.
3. **Tổng quan:** bảy thẻ mở đúng chi tiết: doanh thu/lợi nhuận → báo cáo tương ứng, hóa đơn → danh sách hóa đơn, công nợ → khách còn nợ, số dư đã thu → chi tiết thu/chi cấu thành số dư, sửa chữa → phiếu đang sửa, giá trị tồn → báo cáo tồn. Thêm thẻ Bảo hành đếm máy có IMEI trong danh sách bảo hành và mở danh sách đó; không gọi số máy là số lượt tiếp nhận sửa bảo hành.
4. **Hóa đơn:** Tất cả/Ngày/Tháng/Năm; ô tìm mã, khách, SĐT, IMEI. Mặc định tháng hiện tại; có nút về Tất cả rõ ràng.
5. **Sinh trắc học:** tùy chọn mở khóa Android bằng sinh trắc học đã đăng ký của hệ điều hành; bật sau xác minh PIN, vẫn có PIN dự phòng. Không lưu dữ liệu vân tay. Khi quay lại app sau thời gian khóa phải xác thực lại.
6. **Nhà cung cấp:** hộp tìm theo tên/SĐT trong phiếu nhập; chọn nhà cung cấp đã lưu hoặc thêm mới rồi tự chọn lại, không tạo danh bạ trùng vì mỗi lần nhập hàng.

## Báo cáo hàng hóa theo ảnh

### Trang tổng hợp

- Bộ chọn Hôm nay/Tuần này/Tháng này/Quý/Năm/Khoảng ngày; lọc danh mục, hãng, hàng quản lý IMEI/phụ kiện.
- Khối Top hàng theo doanh thu; có thể chuyển doanh thu/số lượng bán/lợi nhuận.
- Thẻ xanh Tồn kho: tổng giá trị theo giá vốn và tổng số đơn vị còn tồn.
- Khối Top hàng theo giá trị tồn: tên, giá trị tiền căn phải và thanh ngang tỷ lệ như ảnh; bấm để mở danh sách đầy đủ.
- Phân biệt “mẫu hàng” (số mã sản phẩm) và “sản phẩm tồn” (tổng số đơn vị), không dùng lẫn hai số.

### Trang danh sách chi tiết

- Ô tìm kiếm, lọc, sắp xếp tăng/giảm theo tên, doanh thu, số lượng bán, lợi nhuận, số lượng tồn hoặc giá trị tồn.
- Dòng tổng số mẫu hàng và tổng chỉ tiêu theo bộ lọc; mỗi dòng mở chi tiết mặt hàng/IMEI.
- Chia trang/tải thêm để danh sách dài vẫn dễ dùng. Tổng chỉ tiêu tính trên toàn bộ kết quả lọc, không chỉ trang đang thấy.
- Trên máy tính dùng bảng nhiều cột; điện thoại dùng dòng gọn giống ảnh tham khảo.

### Quy tắc số liệu

- Doanh thu, số lượng bán, lợi nhuận theo khoảng thời gian và trạng thái giao dịch, cùng công thức báo cáo hiện tại sau đối chiếu kiểm thử.
- Tồn kho là **tồn hiện tại**, ghi rõ nhãn này; bộ lọc thời gian chỉ tác động số liệu bán. Không giả lập tồn lịch sử nếu dữ liệu chưa đủ để dựng chính xác.
- Máy IMEI: cộng giá vốn từng máy còn trong kho. Phụ kiện: số lượng tồn nhân giá vốn bình quân theo nghiệp vụ hiện có.
- Không tính máy đã bán/đã trả nhà cung cấp/đã loại khỏi kho vào tồn; xử lý hủy giao dịch theo quy tắc hiện tại.
- Số liệu trong ảnh chỉ là tham khảo bố cục, không đưa vào dữ liệu app.

## Hướng giao diện

- Giữ nhận diện Minh Cảnh Mobile: xanh dương chủ đạo, nền xám sáng, thẻ trắng, màu trạng thái có ý nghĩa.
- Hệ chữ và khoảng cách thống nhất; tiền căn phải, nhãn rõ, không cắt mất số tiền dài.
- Tổng quan có thao tác nhanh Bán hàng/Nhập hàng/Sửa chữa; thẻ số liệu có dấu hiệu bấm được.
- Bộ lọc, tìm kiếm đặt cố định ở đầu trang; trạng thái rỗng có hành động tiếp theo, đang tải có phản hồi, lỗi có hướng thử lại.
- Điện thoại giữ thanh điều hướng dưới; máy tính chuyển menu trái và bố cục rộng theo kích thước màn hình.
- Thông báo lưu thành công/thất bại rõ ràng, nút lưu chặn bấm lặp. Trạng thái kết nối máy tính luôn dễ thấy.
- Không dùng logo hoặc tên KiotViet làm nhận diện của app; tham khảo cách tổ chức nghiệp vụ và báo cáo.

## Chuyển đổi dữ liệu và phát hành

Trước triển khai cần xác nhận mã nguồn tương ứng APK, application ID, phiên bản dữ liệu và khóa ký bản đang cài. Dùng migration bổ sung, không xóa/cài lại cơ sở dữ liệu. Sao lưu và thử nâng cấp trên bản sao trước khi phát hành. Nếu không có khóa ký tương thích, phải trình bày đường chuyển dữ liệu trước khi hướng dẫn cài; không bảo người dùng gỡ app đang có dữ liệu.

## Kiểm tra bắt buộc

- Hóa đơn hỗn hợp máy và phụ kiện: bảo hành chỉ hiện máy IMEI; lịch sử không mất.
- Lọc ngày/tháng/năm qua ranh giới tháng, năm, tìm kiếm kết hợp lọc.
- Nợ sau bán, trả một phần, trả hết, hủy và điều chỉnh khớp tổng quan.
- Từng thẻ tổng quan mở đúng danh sách và số tổng khớp.
- Báo cáo IMEI/phụ kiện, nhập khác giá, bán, hủy, trả hàng và điều chỉnh khớp tồn/giá vốn.
- Hai thiết bị bán cùng IMEI đồng thời: chỉ một giao dịch thành công; gửi lại yêu cầu không tạo trùng.
- Mất kết nối giữa lúc lưu: xác định kết quả theo mã yêu cầu trước khi thử lại.
- Ghép nối sai/hết hạn, phiên thu hồi và truy cập API không xác thực bị từ chối.
- Android có/không có sinh trắc học, hủy xác thực và PIN dự phòng.
- Tem 40×30mm, hóa đơn 80mm giữ đúng kích thước, không cắt tiền/chữ; xác nhận trên máy in thực tế trước khi kết luận in đạt.
- Kiểm tra tính đầy đủ từng nghiệp vụ giữa điện thoại và máy tính, không để màn chỉ có nút nhưng chưa có chức năng.
- Build APK, kiểm tra tĩnh, kiểm thử nghiệp vụ, thử trên Android và trình duyệt máy tính; báo riêng phần chưa có thiết bị kiểm tra.

## Điểm anh Cảnh cần xác nhận

Máy tính dùng đủ nghiệp vụ khi điện thoại ở cùng mạng và bật chế độ kết nối; khi điện thoại rời mạng, máy tính dừng thao tác dữ liệu. Nếu cần máy tính tiếp tục bán khi điện thoại ra ngoài, phải đổi kiến trúc trước khi triển khai.
