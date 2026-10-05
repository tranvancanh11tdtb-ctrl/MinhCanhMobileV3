part of '../main.dart';

class PairGate extends StatefulWidget {
  const PairGate({super.key});
  @override State<PairGate> createState()=>_PairGateState();
}
class _PairGateState extends State<PairGate> {
  final code=TextEditingController();
  bool loading=false, paired=false;
  String? error;
  @override void dispose(){code.dispose();super.dispose();}
  Future<void> pair() async {
    if(!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      setState(()=>error='Nhập đủ 6 số trên điện thoại');return;
    }
    setState((){loading=true;error=null;});
    try{await remoteBridge.pair(code.text.trim());if(mounted)setState(()=>paired=true);}
    catch(e){if(mounted)setState(()=>error='Không ghép nối được. Kiểm tra mã và Wi-Fi trên điện thoại.');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context) {
    if(paired)return const HomeShell();
    return Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:440),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.devices_rounded,size:64,color:Color(0xff0877d1)),
        const SizedBox(height:20),const Text('Minh Cảnh Mobile',textAlign:TextAlign.center,style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),const Text('Ghép nối với điện thoại',textAlign:TextAlign.center,style:TextStyle(fontSize:20)),
        const SizedBox(height:12),const Text('Trên điện thoại: Nhiều hơn → Kết nối máy tính. Nhập mã đang hiển thị để mở dữ liệu cửa hàng.'),
        const SizedBox(height:24),TextField(controller:code,enabled:!loading,maxLength:6,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.digitsOnly],decoration:const InputDecoration(labelText:'Mã ghép nối 6 số'),onSubmitted:(_)=>pair()),
        if(error!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
        FilledButton(onPressed:loading?null:pair,child:Text(loading?'Đang kết nối…':'Kết nối')),
        const SizedBox(height:16),const Text('Điện thoại và máy tính cần cùng mạng cửa hàng. Dữ liệu được lưu trên điện thoại.',textAlign:TextAlign.center),
      ])))));
  }
}

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});
  @override State<ConnectionPage> createState()=>_ConnectionPageState();
}
class _ConnectionPageState extends State<ConnectionPage> {
  bool busy=false;
  Timer? timer;
  @override void initState(){super.initState();timer=Timer.periodic(const Duration(seconds:2),(_){if(mounted)setState((){});});}
  @override void dispose(){timer?.cancel();super.dispose();}
  Future<void> toggle() async {
    setState(()=>busy=true);
    try{if(lanHost.running){await lanHost.stop();}else{await lanHost.start(StoreDb.instance.executeRemote);}}
    catch(e){if(mounted)showError(context,e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Kết nối máy tính')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Icon(Icons.wifi_rounded,size:60,color:Color(0xff0877d1)),const SizedBox(height:16),
      const Text('Dùng chung dữ liệu qua Wi-Fi',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
      const SizedBox(height:12),const Text('Máy tính mở địa chỉ bên dưới bằng Chrome hoặc Edge. Điện thoại giữ dữ liệu chính; khi điện thoại ngắt mạng, máy tính sẽ dừng ghi dữ liệu.'),
      const SizedBox(height:12),const Text('Chỉ bật trên mạng cửa hàng tin cậy. Không mở cổng router ra Internet.'),
      const SizedBox(height:20),FilledButton.icon(onPressed:busy?null:toggle,icon:Icon(lanHost.running?Icons.stop_circle_outlined:Icons.play_circle_outline),label:Text(busy?'Đang xử lý…':lanHost.running?'Tắt kết nối máy tính':'Bật kết nối máy tính')),
      if(lanHost.running)...[
        const SizedBox(height:24),const Text('Địa chỉ mở trên máy tính',style:TextStyle(fontWeight:FontWeight.bold)),
        for(final address in lanHost.addresses)SelectableText(address,style:const TextStyle(fontSize:21,color:Color(0xff0877d1))),
        const SizedBox(height:20),Text(lanHost.pairing.code==null?'Mã đã được sử dụng':'Mã ghép nối: ${lanHost.pairing.code}',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
        const Text('Mã dùng một lần, hết hạn sau 5 phút.'),
        TextButton.icon(onPressed:()=>setState(()=>lanHost.pairing.newCode()),icon:const Icon(Icons.refresh),label:const Text('Tạo mã mới')),
        Text('Phiên đang hoạt động: ${lanHost.pairing.deviceCount}'),
        OutlinedButton(onPressed:()=>setState(()=>lanHost.pairing.revokeAll()),child:const Text('Ngắt tất cả máy tính')),
      ],
    ]),
  );
}

Future<void> offerBrowserPdf(BuildContext context,Uint8List bytes,String name) async {
  await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
    title:const Text('Bản in đã sẵn sàng'),
    content:const Text('Tải PDF, mở tệp và chọn In. Đặt đúng khổ giấy, tỷ lệ 100%: tem 40×30 mm hoặc hóa đơn 80 mm.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Đóng')),FilledButton(onPressed:(){browserOpenPdf(bytes,name);Navigator.pop(ctx);},child:const Text('Tải PDF để in'))],
  ));
}
