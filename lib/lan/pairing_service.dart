import 'dart:math';
class PairingService {
  PairingService({DateTime Function()? now}):_now=now??DateTime.now;
  final DateTime Function() _now;
  final _random=Random.secure();
  String? code;
  DateTime? expires;
  final Map<String,DateTime> _sessions={};
  final Map<String,List<DateTime>> _attempts={};
  int get deviceCount=>_sessions.values.where((e)=>e.isAfter(_now())).length;
  String newCode(){code=_random.nextInt(1000000).toString().padLeft(6,'0');expires=_now().add(const Duration(minutes:5));return code!;}
  String exchange(String value,String address){
    final now=_now();
    final attempts=_attempts.putIfAbsent(address,()=>[]);
    attempts.removeWhere((t)=>now.difference(t)>const Duration(minutes:1));
    if(attempts.length>=5)throw StateError('Thử sai nhiều lần. Chờ một phút rồi thử lại.');
    attempts.add(now);
    if(code==null||value!=code||expires==null||!now.isBefore(expires!))throw StateError('Mã ghép nối sai hoặc đã hết hạn.');
    code=null;
    final token=List.generate(32,(_)=>_random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
    _sessions[token]=now.add(const Duration(hours:8));
    return token;
  }
  bool valid(String token)=>_sessions[token]?.isAfter(_now())??false;
  void revokeAll(){_sessions.clear();code=null;expires=null;}
}
