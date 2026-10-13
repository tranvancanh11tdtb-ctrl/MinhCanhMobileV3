part of '../main.dart';

// A backup can exceed the size reliably handled by mobile clipboard apps.
// File I/O preserves the exact JSON bytes without sending them through a text
// input field. Never publish real backups in the source repository.
String parseMinhCanhBackupFile(Uint8List bytes) {
  final text = utf8.decode(bytes);
  final value = jsonDecode(text);
  if (value is! Map || value['app'] != 'MinhCanhMobileV3') {
    throw const FormatException('Đây không phải tệp sao lưu Minh Cảnh Mobile V3');
  }
  if (value['backup_version'] != 6 && value['backup_version'] != 7) {
    throw const FormatException('Phiên bản sao lưu chưa được hỗ trợ');
  }
  for (final table in const [
    'products', 'purchases', 'serial_units', 'purchase_items',
    'sales', 'sale_items', 'inventory_movements', 'repairs',
    'warranty_claims', 'cash_entries', 'stocktakes',
    'customer_directory', 'supplier_directory', 'debt_adjustments',
    'product_categories', 'product_brands', 'app_settings',
  ]) {
    if (value[table] is! List) {
      throw FormatException('Tệp sao lưu thiếu bảng $table');
    }
  }
  return text;
}

extension BackupFileWorkflow on _BackupPageState {
  Future<void> saveBackupFile() async {
    setState(() => busy = true);
    try {
      final text = await StoreDb.instance.exportBackup();
      final name = 'MinhCanhMobile-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      if (kIsWeb) {
        browserDownloadBackup(text, name);
      } else {
        await SharePlus.instance.share(ShareParams(
          files: [XFile.fromData(
            Uint8List.fromList(utf8.encode(text)),
            name: name,
            mimeType: 'application/json',
          )],
          subject: 'Sao lưu Minh Cảnh Mobile',
        ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restoreBackupFile() async {
    if (busy) return;
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        allowMultiple: false,
        withData: true,
      );
      if (selected == null || selected.files.isEmpty || !mounted) return;
      final file = selected.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Không đọc được nội dung tệp sao lưu');
      }
      final source = parseMinhCanhBackupFile(bytes);
      final data = jsonDecode(source) as Map;
      if (!mounted) return;
      final proceed = await confirm(
        context,
        'Khôi phục dữ liệu từ tệp',
        'Tệp: ${file.name}\n'
        'Sản phẩm: ${(data['products'] as List).length}\n'
        'IMEI: ${(data['serial_units'] as List).length}\n'
        'Hóa đơn: ${(data['sales'] as List).length}\n\n'
        'Toàn bộ dữ liệu hiện có trong ứng dụng này sẽ được thay thế. Tiếp tục?',
      );
      if (!proceed || !mounted) return;
      setState(() => busy = true);
      await StoreDb.instance.restoreBackup(source);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khôi phục tệp dữ liệu thành công')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
