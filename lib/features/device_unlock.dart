import 'package:local_auth/local_auth.dart';

/// Device-only authentication. Settings callbacks are never exposed over LAN.
class DeviceUnlock {
  DeviceUnlock({required this.read, required this.write,
    Future<bool> Function()? authenticate, Future<bool> Function()? available})
      : _authenticate=authenticate ?? _nativeAuthenticate,
        _available=available ?? _nativeAvailable;
  final Future<String?> Function(String) read;
  final Future<void> Function(String,String) write;
  final Future<bool> Function() _authenticate, _available;
  DateTime? _backgroundAt;
  static Future<bool> _nativeAvailable() async =>
      (await LocalAuthentication().getAvailableBiometrics()).isNotEmpty;
  static Future<bool> _nativeAuthenticate() => LocalAuthentication().authenticate(
    localizedReason:'Xác thực để mở Minh Cảnh Mobile',
    options:const AuthenticationOptions(biometricOnly:true,stickyAuth:false));
  Future<bool> checkPin(String pin) async =>
      pin.isNotEmpty && pin == await read('pin');
  Future<bool> biometricUnlock() async {
    if(await read('biometric_enabled')!='1')return false;
    try {return await _available() && await _authenticate();} catch(_){return false;}
  }
  Future<void> setEnabled(bool enabled,String pin) async {
    if(!await checkPin(pin))throw StateError('Mã PIN không đúng');
    if(enabled) {
      bool verified=false;
      try {verified=await _available() && await _authenticate();} catch(_){verified=false;}
      if(!verified)throw StateError('Chưa xác thực sinh trắc học. Hãy đăng ký vân tay trong cài đặt điện thoại hoặc dùng mã PIN.');
    }
    await write('biometric_enabled',enabled?'1':'0');
  }
  void background(DateTime now) { _backgroundAt ??= now; }
  bool resume(DateTime now) {
    final previous=_backgroundAt; _backgroundAt=null;
    return previous!=null && now.difference(previous)>=const Duration(seconds:60);
  }
}
