import 'package:flutter_test/flutter_test.dart';
import 'package:minh_canh_mobile_v3/features/device_unlock.dart';

void main() {
  late Map<String,String> settings;
  late DeviceUnlock unlock;
  late int prompts;
  bool success=true;
  setUp(() {
    settings={'pin':'1234'}; prompts=0;success=true;
    unlock=DeviceUnlock(read:(k) async=>settings[k],write:(k,v)async{settings[k]=v;},
      available:()async=>true,authenticate:()async{prompts++;return success;});
  });
  test('disabled biometrics never prompts; enable requires current PIN',()async {
    expect(await unlock.biometricUnlock(),false);expect(prompts,0);
    await expectLater(unlock.setEnabled(true,'0000'),throwsStateError);
    expect(prompts,0);expect(settings['biometric_enabled'],isNull);
    await unlock.setEnabled(true,'1234');
    expect(await unlock.biometricUnlock(),true);
  });
  test('cancel leaves PIN fallback available and changed PIN takes effect',()async {
    await unlock.setEnabled(true,'1234');success=false;
    expect(await unlock.biometricUnlock(),false);
    settings['pin']='5678';
    expect(await unlock.checkPin('1234'),false);
    expect(await unlock.checkPin('5678'),true);
  });
  test('relocks at sixty seconds; duplicate background events do not reset timer',() {
    final t=DateTime(2026,10,6);
    unlock.background(t);unlock.background(t.add(const Duration(seconds:50)));
    expect(unlock.resume(t.add(const Duration(seconds:60))),true);
    expect(unlock.resume(t.add(const Duration(seconds:61))),false);
    unlock.background(t);
    expect(unlock.resume(t.add(const Duration(seconds:59))),false);
  });
}
