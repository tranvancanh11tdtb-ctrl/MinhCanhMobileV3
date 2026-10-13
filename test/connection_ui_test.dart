import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/main.dart';
void main() {
 testWidgets('desktop pairing requires phone code before opening store', (tester) async {
   await tester.pumpWidget(const MaterialApp(home: PairGate()));
   expect(find.text('Ghép nối với điện thoại'),findsOneWidget);
   expect(find.byType(TextField),findsOneWidget);
   expect(find.byType(HomeShell),findsNothing);
   await tester.enterText(find.byType(TextField),'12');
   await tester.tap(find.text('Kết nối'));
   await tester.pump();
   expect(find.byType(HomeShell),findsNothing);
   expect(find.text('Nhập đủ 6 số trên điện thoại'),findsOneWidget);
 });
}
