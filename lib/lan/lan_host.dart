import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'pairing_service.dart';
final lanHost=LanHost();
class LanHost {
 final pairing=PairingService();
 HttpServer? _server;
 Timer? _networkCheck;
 final List<String> addresses=[];
 bool get running=>_server!=null;
 static const channel=MethodChannel('vn.minhcanhmobile/lan');
 Future<void> start(Future<Map<String,Object?>> Function(Map<String,Object?>) handler) async {
   if(running)return;
   final interfaces=await NetworkInterface.list(type:InternetAddressType.IPv4);
   final ips=interfaces.expand((i)=>i.addresses).where((a)=>a.address.startsWith('192.168.')||a.address.startsWith('10.')||(a.address.startsWith('172.')&&int.parse(a.address.split('.')[1])>=16&&int.parse(a.address.split('.')[1])<=31)).map((a)=>a.address).toSet();
   if(ips.isEmpty)throw StateError('Hãy kết nối Wi-Fi cửa hàng trước.');
   // Verify packaged desktop entry before starting an advertised service.
   await rootBundle.load('assets/desktop/index.html');
   final server=await HttpServer.bind(InternetAddress.anyIPv4,0);
   _server=server;addresses..clear()..addAll(ips.map((ip)=>'http://$ip:${server.port}'));
   pairing.newCode();
   channel.setMethodCallHandler((call) async {if(call.method=='stopped')await _close();});
   try {await channel.invokeMethod('start',{'address':addresses.first});}catch(_){await server.close(force:true);_server=null;addresses.clear();rethrow;}
   server.listen((request)=>_serve(request,handler));
   _networkCheck=Timer.periodic(const Duration(seconds:5), (_) async {
     try {
       final current=await NetworkInterface.list(type:InternetAddressType.IPv4);
       final hosts=current.expand((i)=>i.addresses).map((a)=>a.address).toSet();
       if(running && !addresses.any((a)=>hosts.contains(Uri.parse(a).host)))await stop();
     } catch(_) {await stop();}
   });
 }
 Future<void> _close() async {_networkCheck?.cancel();_networkCheck=null;pairing.revokeAll();final old=_server;_server=null;addresses.clear();await old?.close(force:true);}
 Future<void> stop() async {await _close();await channel.invokeMethod('stop');}
 Future<void> _serve(HttpRequest req,Future<Map<String,Object?>> Function(Map<String,Object?>) handler) async {
   final res=req.response;
   try{
     final host=req.headers.value('host');
     if(host==null||!addresses.any((a)=>Uri.parse(a).authority==host)){res.statusCode=403;return;}
     res.headers.set('X-Content-Type-Options','nosniff');
     res.headers.set('X-Frame-Options','DENY');
     res.headers.set('Referrer-Policy','no-referrer');
     if(req.uri.path.startsWith('/api/')){
       res.headers.contentType=ContentType.json;res.headers.set('Cache-Control','no-store');
       if(req.method!='POST'){res.statusCode=405;res.write(jsonEncode({'error':'Phương thức không hợp lệ'}));return;}
       if(req.headers.value('origin')!='http://$host'){res.statusCode=403;res.write(jsonEncode({'error':'Nguồn truy cập không hợp lệ'}));return;}
       if(req.headers.contentType?.mimeType!='application/json'){res.statusCode=415;res.write(jsonEncode({'error':'Định dạng không hợp lệ'}));return;}
       if(req.uri.path!='/api/pair'){
         final token=(req.headers.value('authorization')??'').replaceFirst('Bearer ','');
         if(!pairing.valid(token)){res.statusCode=401;res.write(jsonEncode({'error':'Phiên đã hết hạn. Hãy ghép nối lại.'}));return;}
       }
       final data=<int>[];
       await for(final bytes in req.timeout(const Duration(seconds:30))){data.addAll(bytes);if(data.length>16*1024*1024){res.statusCode=413;res.write(jsonEncode({'error':'Dữ liệu vượt quá 16 MB'}));return;}}
       final body=Map<String,Object?>.from(jsonDecode(utf8.decode(data)) as Map);
       if(req.uri.path=='/api/pair'){
         final token=pairing.exchange(body['code'] as String? ?? '',req.connectionInfo?.remoteAddress.address??'unknown');
         res.write(jsonEncode({'token':token}));
       }else if(req.uri.path=='/api/call'){
         res.write(jsonEncode(await handler(body)));
       }else{res.statusCode=404;res.write(jsonEncode({'error':'Không có chức năng này'}));}
     }else{
       if(req.method!='GET'&&req.method!='HEAD'){res.statusCode=405;return;}
       final path=req.uri.path=='/'?'index.html':req.uri.path.substring(1);
       if(path.split('/').any((s)=>s=='..'||s.startsWith('.'))||path.contains('\\')){res.statusCode=403;return;}
       try{
         final data=await rootBundle.load('assets/desktop/$path');
         final ext=path.split('.').last;
         const types={'html':'text/html; charset=utf-8','js':'application/javascript','json':'application/json','css':'text/css','wasm':'application/wasm','png':'image/png','svg':'image/svg+xml','ttf':'font/ttf','otf':'font/otf','woff2':'font/woff2'};
         res.headers.set('Content-Type',types[ext]??'application/octet-stream');
         res.headers.set('Cache-Control','no-cache');
         if(req.method=='GET')res.add(data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes));
       }on FlutterError {res.statusCode=404;}
     }
   }catch(e){res.statusCode=400;res.headers.contentType=ContentType.json;res.write(jsonEncode({'error':e is StateError?e.message.toString():e is ArgumentError?'Dữ liệu không hợp lệ': 'Không thể thực hiện. Kiểm tra dữ liệu và thử lại.'}));}
   finally{await res.close();}
 }
}
