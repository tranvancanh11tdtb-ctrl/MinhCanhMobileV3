class VietQrAccount {
  const VietQrAccount({
    required this.bankBin,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
  });

  final String bankBin;
  final String bankName;
  final String accountNumber;
  final String accountName;

  bool get isValid =>
      RegExp(r'^\d{6}$').hasMatch(bankBin.trim()) &&
      RegExp(r'^[A-Za-z0-9]{6,19}$').hasMatch(accountNumber.trim());
}

String buildVietQrPayload({
  required String bankBin,
  required String accountNumber,
  required int amount,
  required String description,
}) {
  final normalizedBin = bankBin.trim();
  final normalizedAccount = accountNumber.trim();
  if (!RegExp(r'^\d{6}$').hasMatch(normalizedBin)) {
    throw ArgumentError('Mã BIN ngân hàng phải gồm 6 chữ số');
  }
  if (!RegExp(r'^[A-Za-z0-9]{6,19}$').hasMatch(normalizedAccount)) {
    throw ArgumentError('Số tài khoản phải có từ 6 đến 19 ký tự');
  }
  if (amount <= 0 || amount.toString().length > 13) {
    throw ArgumentError('Số tiền tạo QR không hợp lệ');
  }

  final accountInfo = _tlv('00', normalizedBin) +
      _tlv('01', normalizedAccount);
  final consumerAccount = _tlv('00', 'A000000727') +
      _tlv('01', accountInfo) +
      _tlv('02', 'QRIBFTTA');
  final safeDescription = _ascii(description, maxLength: 25);

  final payload = _tlv('00', '01') +
      _tlv('01', '12') +
      _tlv('38', consumerAccount) +
      _tlv('53', '704') +
      _tlv('54', amount.toString()) +
      _tlv('58', 'VN') +
      (safeDescription.isEmpty
          ? ''
          : _tlv('62', _tlv('08', safeDescription))) +
      '6304';
  return '$payload${crc16Ccitt(payload)}';
}

String _tlv(String id, String value) {
  final length = value.length;
  if (length > 99) throw ArgumentError('Dữ liệu VietQR quá dài');
  return '$id${length.toString().padLeft(2, '0')}$value';
}

String _ascii(String value, {required int maxLength}) {
  var normalized = value
      .replaceAll(RegExp('[ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ]'), 'A')
      .replaceAll(RegExp('[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp('[ÈÉẸẺẼÊỀẾỆỂỄ]'), 'E')
      .replaceAll(RegExp('[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp('[ÌÍỊỈĨ]'), 'I')
      .replaceAll(RegExp('[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp('[ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ]'), 'O')
      .replaceAll(RegExp('[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp('[ÙÚỤỦŨƯỪỨỰỬỮ]'), 'U')
      .replaceAll(RegExp('[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp('[ỲÝỴỶỸ]'), 'Y')
      .replaceAll(RegExp('[ỳýỵỷỹ]'), 'y')
      .replaceAll('Đ', 'D')
      .replaceAll('đ', 'd');
  normalized = normalized.replaceAll(RegExp(r'[^A-Za-z0-9 ._\-]'), '');
  final compact = normalized.trim().replaceAll(RegExp(r'\s+'), ' ');
  return compact.length <= maxLength
      ? compact
      : compact.substring(0, maxLength);
}

String crc16Ccitt(String input) {
  var crc = 0xffff;
  for (final byte in input.codeUnits) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x1021) & 0xffff
          : (crc << 1) & 0xffff;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}
