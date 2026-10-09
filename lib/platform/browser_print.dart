// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

@JS('window.open')
external JSObject? _openPrintWindow(JSString url, JSString target);

extension type _PrintWindow(JSObject value) implements JSObject {
  external _PrintDocument get document;
}

extension type _PrintDocument(JSObject value) implements JSObject {
  external void open();
  external void write(JSString content);
  external void close();
}

void browserPrintPdf(Uint8List bytes, String name) {
  final popup = _openPrintWindow('about:blank'.toJS, '_blank'.toJS);
  if (popup == null)
    throw StateError(
      'Trình duyệt chặn cửa sổ in. Cho phép cửa sổ bật lên rồi bấm In lại.',
    );
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([bytes], 'application/pdf'),
  );
  final document = _PrintWindow(popup).document;
  document.open();
  document.write(
    '''<!doctype html><html><head><meta charset="utf-8"><title>${htmlEscape.convert(name)}</title><style>body{margin:0;font:14px sans-serif}header{padding:12px}iframe{border:0;width:100%;height:90vh}@media print{header{display:none}}</style></head><body><header><button onclick="printPdf()">In / chọn máy in</button> Chọn đúng khổ giấy, tỷ lệ 100%. <a href="$url" target="_blank">Mở PDF</a></header><iframe id="pdf" src="$url"></iframe><script>function printPdf(){try{document.getElementById('pdf').contentWindow.focus();document.getElementById('pdf').contentWindow.print()}catch(e){alert('Hãy mở PDF và chọn In trong trình xem PDF.')}}document.getElementById('pdf').addEventListener('load',function(){setTimeout(printPdf,700)});</script></body></html>'''
        .toJS,
  );
  document.close();
}

void browserOpenPdf(Uint8List bytes, String name) {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([bytes], 'application/pdf'),
  );
  html.AnchorElement(href: url)
    ..target = '_blank'
    ..download = name
    ..click();
  // Keep URL alive until this page is closed; some browsers open the PDF lazily.
}

void browserDownloadBackup(String source, String name) {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([source], 'application/json;charset=utf-8'),
  );
  html.AnchorElement(href: url)
    ..download = name
    ..click();
}

Map<String, Object?>? readPendingRequest() {
  final source = html.window.sessionStorage['mcm_pending'];
  if (source == null) return null;
  return Map<String, Object?>.from(jsonDecode(source) as Map);
}

void savePendingRequest(Map<String, Object?>? request) {
  if (request == null) {
    html.window.sessionStorage.remove('mcm_pending');
  } else {
    html.window.sessionStorage['mcm_pending'] = jsonEncode(request);
  }
}
