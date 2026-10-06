// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
void browserOpenPdf(Uint8List bytes, String name) {
  final url=html.Url.createObjectUrlFromBlob(html.Blob([bytes],'application/pdf'));
  html.AnchorElement(href:url)..target='_blank'..download=name..click();
  // Keep URL alive until this page is closed; some browsers open the PDF lazily.
}
void browserDownloadBackup(String source, String name) {
  final url=html.Url.createObjectUrlFromBlob(html.Blob([source],'application/json;charset=utf-8'));
  html.AnchorElement(href:url)..download=name..click();
}
Map<String,Object?>? readPendingRequest() {
  final source=html.window.sessionStorage['mcm_pending'];
  if(source==null)return null;
  return Map<String,Object?>.from(jsonDecode(source) as Map);
}
void savePendingRequest(Map<String,Object?>? request) {
  if(request==null){html.window.sessionStorage.remove('mcm_pending');}
  else {html.window.sessionStorage['mcm_pending']=jsonEncode(request);}
}
