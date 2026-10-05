import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../platform/browser_print_stub.dart' if (dart.library.html) '../platform/browser_print.dart';

final remoteBridge=RemoteBridge();
class RemoteBridge extends ChangeNotifier {
  String? _token;
  int? revision;
  int? latestRevision;
  bool connected=false;
  bool busy=false;
  String? message;
  Timer? _poll;
  Map<String,Object?>? pending=readPendingRequest();
  Uri get base=>Uri.base;
  Future<Map<String,dynamic>> _post(String path,Map<String,Object?> body) async {
    final response=await http.post(base.resolve(path),headers:{'Content-Type':'application/json',if(_token!=null)'Authorization':'Bearer $_token'},body:jsonEncode(body)).timeout(const Duration(seconds:20));
    final result=jsonDecode(response.body) as Map<String,dynamic>;
    if(response.statusCode!=200)throw StateError(result['error'] as String? ?? 'Không thể kết nối điện thoại');
    return result;
  }
  Future<void> pair(String code) async {
    final result=await _post('/api/pair',{'code':code});
    _token=result['token'] as String;
    revision=null;latestRevision=null;connected=true;
    await call('dashboard',{},write:false);
    _poll?.cancel();_poll=Timer.periodic(const Duration(seconds:4),(_)=>poll());
    notifyListeners();
  }
  Future<void> poll() async {
    if(_token==null||busy)return;
    try{
      final result=await _post('/api/call',{'operation':'dashboard','arguments':{}});
      latestRevision=result['revision'] as int;
      connected=true;
      message=latestRevision!=revision?'Dữ liệu đã thay đổi trên thiết bị khác. Bấm tải lại.':null;
    }catch(_){connected=false;message='Mất kết nối điện thoại. Kiểm tra Wi-Fi và chế độ kết nối.';}
    notifyListeners();
  }
  void acceptLatest(){revision=latestRevision;message=null;notifyListeners();}
  Future<Object?> call(String operation,Map<String,Object?> args,{required bool write}) async {
    if(write&&busy)throw StateError('Một giao dịch đang xử lý. Vui lòng chờ.');
    if(write&&!connected)throw StateError('Điện thoại đang mất kết nối. Chưa lưu thay đổi.');
    if(write&&pending!=null)throw StateError('Cần kiểm tra lại giao dịch trước khi tạo giao dịch mới.');
    final request=<String,Object?>{'operation':operation,'arguments':args};
    if(write){
      final random=Random.secure();
      request['requestId']=List.generate(24,(_)=>random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
      request['revision']=revision;
      savePendingRequest(request);pending=request;busy=true;notifyListeners();
    }
    try {
      final response=await _post('/api/call',request);
      final current=response['revision'] as int;
      latestRevision=current;
      if(write||revision==null)revision=current;
      connected=true;if(write){pending=null;savePendingRequest(null);}
      return response['value'];
    }on StateError {if(write){pending=null;savePendingRequest(null);}rethrow;}
    catch(_) {connected=false;message=write?'Chưa xác định kết quả lưu. Bấm kiểm tra giao dịch, không nhập lại.':'Không kết nối được điện thoại.';rethrow;}
    finally{if(write)busy=false;notifyListeners();}
  }
  Future<void> resolvePending() async {
    final request=pending;if(request==null)return;
    busy=true;notifyListeners();
    try {final response=await _post('/api/call',request);revision=response['revision'] as int;latestRevision=revision;pending=null;savePendingRequest(null);connected=true;message='Giao dịch đã được xác nhận. Hãy tải lại để xem kết quả.';}
    on StateError catch(e){message=e.message.toString();}
    finally{busy=false;notifyListeners();}
  }
  void disconnect(){_poll?.cancel();_token=null;connected=false;revision=null;notifyListeners();}
}
