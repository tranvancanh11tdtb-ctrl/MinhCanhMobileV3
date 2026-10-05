import 'dart:io';
Future<void> sendToPrinter(String host,int port,List<int> bytes,int copies) async {
 final socket=await Socket.connect(host,port,timeout:const Duration(seconds:7));
 try{for(var i=0;i<copies;i++){socket.add(bytes);await socket.flush();}}
 finally{await socket.close();}
}
