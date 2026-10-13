import 'pairing_service.dart';
final lanHost=LanHost();
class LanHost {
 final pairing=PairingService();
 bool get running=>false;
 List<String> get addresses=>[];
 Future<void> start(Future<Map<String,Object?>> Function(Map<String,Object?>) handler) async=>throw UnsupportedError('Chỉ bật kết nối trên điện thoại');
 Future<void> stop() async{}
}
