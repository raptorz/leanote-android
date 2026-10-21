import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/services/app_lock.dart';

class _Authenticator implements DeviceAuthenticator {
  _Authenticator({this.available = true});
  bool available;
  final responses = <bool>[];
  int calls = 0;

  @override
  Future<bool> supported() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return responses.removeAt(0);
  }
}

void main() {
  test('enabled lock protects cold start and foreground return', () async {
    final authenticator = _Authenticator()..responses.addAll([true, true]);
    bool saved = true;
    final lock = AppLockController(
      load: () async => saved,
      save: (value) async => saved = value,
      authenticator: authenticator,
    );
    addTearDown(lock.dispose);
    await lock.initialize('unlock');
    expect(lock.enabled, isTrue);
    expect(lock.locked, isFalse);
    lock.backgrounded();
    expect(lock.locked, isTrue);
    expect(await lock.unlock('unlock'), isTrue);
    expect(lock.locked, isFalse);
    expect(authenticator.calls, 2);
  });

  test('cancelled authentication never enables or unlocks the app', () async {
    final authenticator = _Authenticator()..responses.addAll([false, false]);
    bool saved = false;
    final lock = AppLockController(
      load: () async => saved,
      save: (value) async => saved = value,
      authenticator: authenticator,
    );
    addTearDown(lock.dispose);
    await lock.initialize('unlock');
    expect(await lock.setEnabled(true, 'enable'), isFalse);
    expect(saved, isFalse);
    expect(lock.enabled, isFalse);

    saved = true;
    final restored = AppLockController(
      load: () async => saved,
      save: (value) async => saved = value,
      authenticator: authenticator,
    );
    addTearDown(restored.dispose);
    await restored.initialize('unlock');
    expect(restored.enabled, isTrue);
    expect(restored.locked, isTrue);
  });

  test('logout cleanup disables the saved app lock', () async {
    final authenticator = _Authenticator()..responses.add(true);
    bool saved = true;
    final lock = AppLockController(
      load: () async => saved,
      save: (value) async => saved = value,
      authenticator: authenticator,
    );
    addTearDown(lock.dispose);
    await lock.initialize('unlock');
    await lock.clear();
    expect(saved, isFalse);
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
  });

  test('unsupported devices leave app lock disabled', () async {
    final lock = AppLockController(
      load: () async => true,
      save: (_) async {},
      authenticator: _Authenticator(available: false),
    );
    addTearDown(lock.dispose);
    await lock.initialize('unlock');
    expect(lock.supported, isFalse);
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
  });
}
