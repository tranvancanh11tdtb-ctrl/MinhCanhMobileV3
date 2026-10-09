import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';

void main() {
  testWidgets('customer picker filters by Vietnamese name and phone', (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CustomerSearchPicker(
      rows:const [{'id':1,'name':'Cảnh','phone':'0912345678'},{'id':2,'name':'Lan','phone':'0988888888'}],
      selectedId:0,onSelected:(id)=>selected=id,
    ))));
    await tester.tap(find.text('Tìm / chọn khách hàng'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'091234');
    await tester.pumpAndSettle();
    expect(find.text('Cảnh'),findsOneWidget);
    expect(find.text('Lan'),findsNothing);
    await tester.tap(find.text('Cảnh'));await tester.pumpAndSettle();
    expect(selected,1);
  });
}
